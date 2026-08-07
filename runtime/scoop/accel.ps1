# Apply Scoop mirror and aria2 acceleration. Requires runtime/scoop/utils.ps1.

function Get-ScoopAccelConfig {
    param($Manifest)
    if (-not $Manifest) { $Manifest = Read-Manifest }
    $accel = $Manifest.scoopAccel
    if (-not $accel) {
        Write-ErrorAndExit 'windows manifest is missing scoopAccel'
    }
    return $accel
}

function Get-ScoopMirrorPrefixes {
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(Get-GithubAccelPrefixes)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not $list.Contains($p)) { [void]$list.Add($p) }
    }

    if ($list.Count -eq 0) {
        Write-ErrorAndExit 'common githubAccel.mirrors is empty; configure at least one mirror'
    }
    return $list
}

function Get-ScoopMirrorChoiceId {
    param([string]$Prefix)
    if ([string]::IsNullOrWhiteSpace($Prefix)) { return 'official' }
    foreach ($item in @(Get-GithubAccelMirrors)) {
        if ($item.prefix -eq $Prefix) { return $item.id }
        if ($item.prefix.TrimEnd('/') -eq $Prefix.TrimEnd('/')) { return $item.id }
    }
    try {
        $hostName = ([Uri]$Prefix).Host
        if (-not [string]::IsNullOrWhiteSpace($hostName)) { return $hostName }
    }
    catch { }
    return (($Prefix -replace '^https?://', '') -replace '/$', '')
}

function Show-ScoopMirrorUsage {
    $map = Get-GithubAccelSelectionMap
    $keys = @($map.Keys)
    Write-Host "Usage: vpr pm [$($keys -join '|')]"
    Write-Host ''
    foreach ($k in $keys) {
        $label = if ($k -eq 'official') { 'Upstream' } else { $map[$k] }
        Write-Host ("  {0,-12}  {1}" -f $k, $label)
    }
    Write-Host ''
    Write-Host 'Examples:'
    Write-Host '  vpr pm'
    foreach ($k in $keys) {
        Write-Host "  vpr pm -- $k"
    }
}

function Strip-ScoopMirrorPrefix {
    param(
        [string]$Url,
        $Prefixes
    )
    foreach ($p in @($Prefixes)) {
        $prefix = [string]$p
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
        if ($Url.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $Url.Substring($prefix.Length)
        }
    }
    return $Url
}

function Join-ScoopMirrorUrl {
    param(
        [string]$Url,
        [string]$Prefix,
        $AllPrefixes
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }
    if (-not $AllPrefixes) { $AllPrefixes = @() }
    $bare = Strip-ScoopMirrorPrefix -Url $Url -Prefixes $AllPrefixes
    if ([string]::IsNullOrWhiteSpace($Prefix)) { return $bare }
    if (-not $Prefix.EndsWith('/')) { $Prefix += '/' }
    return ($Prefix + $bare)
}

# Empty string = official (no mirror). Unknown/polluted values → official + warning.
# Accepts arrays: Scoop installer Write-Output can pollute pipeline returns; scan elements.
function Resolve-ScoopKnownMirrorPrefix {
    param(
        [AllowNull()]
        $Prefix,
        $Prefixes,
        [switch]$Quiet
    )
    if ($null -eq $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes }
    if ($null -eq $Prefix) { return '' }

    # Pipeline pollution → Object[]; find the last catalog prefix among elements.
    if ($Prefix -is [System.Array]) {
        $found = ''
        foreach ($item in @($Prefix)) {
            $hit = Resolve-ScoopKnownMirrorPrefix -Prefix $item -Prefixes $Prefixes -Quiet
            if (-not [string]::IsNullOrWhiteSpace($hit)) { $found = $hit }
        }
        if ([string]::IsNullOrWhiteSpace($found) -and -not $Quiet) {
            Write-Warn 'Ignoring invalid Scoop mirror prefix (polluted installer output)'
        }
        return $found
    }

    $needle = [string]$Prefix
    if ([string]::IsNullOrWhiteSpace($needle)) { return '' }
    $needle = $needle.Trim()
    foreach ($p in @($Prefixes)) {
        $known = [string]$p
        if ([string]::IsNullOrWhiteSpace($known)) { continue }
        if (
            $needle.Equals($known, [StringComparison]::OrdinalIgnoreCase) -or
            $needle.TrimEnd('/').Equals($known.TrimEnd('/'), [StringComparison]::OrdinalIgnoreCase)
        ) {
            return $known
        }
    }

    if (-not $Quiet) {
        Write-Warn "Ignoring invalid Scoop mirror prefix (not in catalog): $needle"
    }
    return ''
}

function Test-ScoopRepoUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    $u = $Url.Trim()
    if ($u -match '\s') { return $false }
    if ($u -notmatch '^https?://') { return $false }
    # Classic pollution: installer Write-Output joined into scoop_repo.
    if ($u -match 'Initializing\.\.\.|Scoop was installed|Downloading\.\.\.|Extracting\.\.\.|Creating shim') {
        return $false
    }
    return $true
}

function Get-ScoopRepoTargetUrl {
    param(
        [string]$ActivePrefix,
        $Accel,
        $Prefixes
    )
    if (-not $Accel) { $Accel = Get-ScoopAccelConfig }
    if ($null -eq $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes }
    $prefix = Resolve-ScoopKnownMirrorPrefix -Prefix $ActivePrefix -Prefixes $Prefixes -Quiet
    $bare = [string]$Accel.scoopRepo
    if ([string]::IsNullOrWhiteSpace($bare)) {
        $bare = 'https://github.com/ScoopInstaller/Scoop'
    }
    return (Join-ScoopMirrorUrl -Url $bare -Prefix $prefix -AllPrefixes $Prefixes)
}

function Set-ScoopRepoConfig {
    param([Parameter(Mandatory)][string]$Url)
    if (-not (Test-ScoopRepoUrl -Url $Url)) {
        Write-ErrorAndExit "Refusing to set scoop_repo to invalid URL: $Url"
    }
    # scoop config prints the value; discard so callers never capture it.
    $null = scoop config scoop_repo $Url
}

# Self-heal polluted scoop_repo (from older installer return-value bugs) before scoop update.
function Repair-ScoopRepoConfig {
    param([Parameter(Mandatory)][string]$ExpectedUrl)

    $current = ''
    try {
        $raw = scoop config scoop_repo 2>$null
        if ($null -ne $raw) {
            $current = ([string](@($raw) | Select-Object -Last 1)).Trim()
        }
    }
    catch { }

    if ((Test-ScoopRepoUrl -Url $current) -and $current -eq $ExpectedUrl) {
        return
    }
    if (-not (Test-ScoopRepoUrl -Url $current)) {
        Write-Warn "scoop_repo is invalid/polluted; resetting to $ExpectedUrl"
    }
    else {
        Write-Info "Updating scoop_repo to $ExpectedUrl"
    }
    Set-ScoopRepoConfig -Url $ExpectedUrl
}

function Get-ScoopMirrorFetchAttempts {
    param(
        [string]$Url,
        $Prefixes,
        [string]$PreferredPrefix = $null
    )

    $bare = Strip-ScoopMirrorPrefix -Url $Url -Prefixes $Prefixes
    $attempts = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    $prefixOrder = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($PreferredPrefix)) {
        # official: do not probe mirrors first
        [void]$prefixOrder.Add('')
    }
    else {
        [void]$prefixOrder.Add($PreferredPrefix)
        foreach ($p in @($Prefixes)) {
            $prefix = [string]$p
            if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
            if (
                $prefix -eq $PreferredPrefix -or
                $prefix.TrimEnd('/') -eq $PreferredPrefix.TrimEnd('/')
            ) { continue }
            [void]$prefixOrder.Add($prefix)
        }
        [void]$prefixOrder.Add('')
    }

    foreach ($prefix in $prefixOrder) {
        $fetchUrl = if ([string]::IsNullOrWhiteSpace($prefix)) {
            $bare
        }
        else {
            Join-ScoopMirrorUrl -Url $bare -Prefix $prefix -AllPrefixes $Prefixes
        }
        if (-not $seen.Add($fetchUrl)) { continue }
        [void]$attempts.Add([pscustomobject]@{
                Prefix = if ([string]::IsNullOrWhiteSpace($prefix)) { '' } else { $prefix }
                Url    = $fetchUrl
            })
    }
    return $attempts
}

function Get-ScoopMirrorUrlCandidates {
    param(
        [string]$Url,
        $Prefixes,
        [string]$PreferredPrefix = $null
    )
    return @(
        Get-ScoopMirrorFetchAttempts -Url $Url -Prefixes $Prefixes -PreferredPrefix $PreferredPrefix
        | ForEach-Object { $_.Url }
    )
}

function Test-ScoopUrlReachable {
    param(
        [string]$Url,
        [int]$TimeoutSec = 3
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }

    foreach ($method in @('Head', 'Get')) {
        try {
            $res = Invoke-WebRequest -Uri $Url -Method $method -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
            if ([int]$res.StatusCode -ge 200 -and [int]$res.StatusCode -lt 400) {
                return $true
            }
        }
        catch {
            continue
        }
    }
    return $false
}

function Invoke-NodeMenuSelect {
    param(
        [string]$Title,
        [string[]]$Items,
        [string]$InitialValue = ''
    )

    $menuScript = Join-Path $Script:ProjectRoot 'src\lib\menu-select.js'
    if (-not (Test-Path $menuScript)) {
        Write-ErrorAndExit "Menu script not found: $menuScript"
    }
    $outFile = [System.IO.Path]::GetTempFileName()
    try {
        $env:MENU_SELECT_OUT = $outFile
        if (-not [string]::IsNullOrWhiteSpace($InitialValue)) {
            $env:MENU_SELECT_INITIAL = $InitialValue.Trim()
        }
        $menuArgs = @($Title) + @($Items | Where-Object { $_ })
        & node $menuScript @menuArgs
        if ($LASTEXITCODE -eq 130) {
            # menu-select already printed Canceled
            exit 130
        }
        if ($LASTEXITCODE -ne 0) { return '' }
        $choice = (Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        return "$choice".Trim()
    }
    finally {
        Remove-Item Env:MENU_SELECT_OUT -ErrorAction SilentlyContinue
        Remove-Item Env:MENU_SELECT_INITIAL -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-ScoopMirrorSelection {
    param([string]$Choice = '')

    $map = Get-GithubAccelSelectionMap
    if ($Choice -match '^--(.+)$') { $Choice = $Matches[1] }
    $Choice = "$Choice".Trim()

    # USE_ACCEL is for one-click / non-interactive installers only.
    # Interactive `vpr pm` must always show the menu — leftover USE_ACCEL from a
    # mirrored one-liner ($env:USE_ACCEL='ghfast'; irm ... | iex) must not skip it.
    $hintFromEnv = ''
    if ($Choice -eq '' -and -not [string]::IsNullOrWhiteSpace($env:USE_ACCEL)) {
        $hintFromEnv = "$env:USE_ACCEL".Trim()
        if (-not (Test-InteractivePrompt)) {
            $Choice = $hintFromEnv
        }
    }

    if ($Choice -ne '') {
        if ($map.Contains($Choice)) { return $map[$Choice] }
        foreach ($k in @($map.Keys)) {
            $prefix = $map[$k]
            if ($prefix -eq $Choice) { return $prefix }
            if ($prefix -and ($prefix.TrimEnd('/') -eq $Choice.TrimEnd('/'))) { return $prefix }
        }
        Show-ScoopMirrorUsage
        Write-ErrorAndExit "Unknown mirror: $Choice"
    }

    if (-not (Test-InteractivePrompt)) {
        Show-ScoopMirrorUsage
        Write-ErrorAndExit 'Pass an argument in non-interactive environments (example: vpr pm -- official)'
    }

    $menuItems = New-Object System.Collections.Generic.List[string]
    $keys = @($map.Keys)
    $idWidth = ($keys | Measure-Object -Property Length -Maximum).Maximum
    foreach ($k in $keys) {
        if ($k -eq 'official') {
            [void]$menuItems.Add(('{0}) Upstream' -f $k.PadRight($idWidth)))
        }
        else {
            [void]$menuItems.Add(('{0}) {1}' -f $k.PadRight($idWidth), $map[$k]))
        }
    }

    $initial = if ($hintFromEnv -and $map.Contains($hintFromEnv)) { $hintFromEnv } else { '' }
    $selected = Invoke-NodeMenuSelect -Title 'Choose a Scoop mirror' -Items @($menuItems) -InitialValue $initial
    if ([string]::IsNullOrWhiteSpace($selected) -or -not $map.Contains($selected)) {
        Show-ScoopMirrorUsage
        Write-ErrorAndExit 'Pass an argument in non-interactive environments (example: vpr pm -- official)'
    }
    return $map[$selected]
}

function Format-ScoopMirrorActiveLabel {
    param([string]$ActivePrefix)
    if ([string]::IsNullOrWhiteSpace($ActivePrefix)) { return 'Upstream' }
    return $ActivePrefix
}

function Get-ScoopMirrorLabelFromUrl {
    param(
        [string]$Url,
        $Prefixes
    )
    foreach ($p in @($Prefixes)) {
        $prefix = [string]$p
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
        if ($Url.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $prefix }
    }
    return 'Upstream'
}

function Get-ScoopInstallerBootstrapUrls {
    # Official Scoop installer hardcodes these bootstrap URLs.
    return @(
        'https://github.com/ScoopInstaller/Scoop/archive/master.zip',
        'https://github.com/ScoopInstaller/Main/archive/master.zip',
        'https://github.com/ScoopInstaller/Scoop.git',
        'https://github.com/ScoopInstaller/Main.git'
    )
}

function Rewrite-ScoopInstallerGithubUrls {
    param(
        [string]$Script,
        [string]$Prefix,
        $AllPrefixes
    )

    if ([string]::IsNullOrWhiteSpace($Script) -or [string]::IsNullOrWhiteSpace($Prefix)) {
        return $Script
    }

    # Narrow rewrite: Scoop + Main bucket clone/zip only.
    $targets = @(Get-ScoopInstallerBootstrapUrls) | Sort-Object { $_.Length } -Descending
    $rewritten = 0
    foreach ($bare in $targets) {
        $mirrored = Join-ScoopMirrorUrl -Url $bare -Prefix $Prefix -AllPrefixes $AllPrefixes
        if ($mirrored -eq $bare) { continue }
        if ($Script.Contains($bare)) {
            $Script = $Script.Replace($bare, $mirrored)
            $rewritten++
        }
    }

    if ($rewritten -eq 0) {
        throw 'Scoop installer bootstrap URLs were not rewritten; refusing to run against upstream GitHub'
    }

    # Ensure at least one mirrored Scoop/Main URL is present after rewrite.
    $mirroredHit = $false
    foreach ($bare in $targets) {
        $mirrored = Join-ScoopMirrorUrl -Url $bare -Prefix $Prefix -AllPrefixes $AllPrefixes
        if ($mirrored -ne $bare -and $Script.Contains($mirrored)) {
            $mirroredHit = $true
            break
        }
    }
    if (-not $mirroredHit) {
        throw 'Scoop installer rewrite produced no mirrored Scoop/Main URLs'
    }

    return $Script
}

function Invoke-ScoopInstallScriptWithFallback {
    param(
        $Accel,
        [string]$PreferredPrefix = $null,
        # Prefer [ref] over return: installer Write-Output must never join into ActivePrefix.
        [Parameter(Mandatory)]
        [ref]$OutPrefix
    )

    $url = [string]$Accel.installScript
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-ErrorAndExit 'scoopAccel.installScript is empty'
    }

    $prefixes = @(Get-ScoopMirrorPrefixes)
    $attempts = @(Get-ScoopMirrorFetchAttempts -Url $url -Prefixes $prefixes -PreferredPrefix $PreferredPrefix)
    if ($attempts.Count -eq 0) {
        Write-ErrorAndExit 'No Scoop installer URL candidates'
    }

    $OutPrefix.Value = ''
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($attempt in $attempts) {
        $label = Format-ScoopMirrorActiveLabel -ActivePrefix $attempt.Prefix
        Write-Info "Trying installer ($label): $($attempt.Url)"
        try {
            $script = [string](Invoke-RestMethod -Uri $attempt.Url)
            if ([string]::IsNullOrWhiteSpace($script)) {
                throw 'Empty installer response'
            }
            if ($script -notmatch 'function\s+Install-Scoop' -and $script -notmatch 'SCOOP_PACKAGE_GIT_REPO') {
                throw 'Response does not look like the Scoop installer'
            }

            # Mirror fetch alone is not enough: rewrite Scoop/Main clone+zip URLs too.
            if (-not [string]::IsNullOrWhiteSpace($attempt.Prefix)) {
                $script = Rewrite-ScoopInstallerGithubUrls -Script $script -Prefix $attempt.Prefix -AllPrefixes $prefixes
            }

            # Concatenate (do not interpolate) so installer $-variables stay intact.
            # Scoop Write-InstallInfo → Write-Output: echo to host, never success stream.
            $expression = if (Test-Administrator) {
                '& { ' + $script + ' } -RunAsAdmin'
            }
            else {
                $script
            }
            Invoke-Expression $expression | ForEach-Object { Write-Host $_ }

            # Persist the source that actually installed Scoop (may differ from selection after fallback).
            $successPrefix = Resolve-ScoopKnownMirrorPrefix -Prefix $attempt.Prefix -Prefixes $prefixes
            $successLabel = Format-ScoopMirrorActiveLabel -ActivePrefix $successPrefix
            Write-Info "Installer succeeded ($successLabel); active mirror set to $successLabel"
            $OutPrefix.Value = $successPrefix
            return
        }
        catch {
            $msg = $_.Exception.Message
            Write-Warn "Installer failed ($label): $msg"
            [void]$errors.Add("${label}: $msg")
        }
    }

    $detail = ($errors -join '; ')
    Write-ErrorAndExit "Scoop installation failed after trying all sources: $detail"
}

function Get-ScoopLibDownloadPath {
    $scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { (Read-Manifest).scoopDir }
    $download = Join-Path $scoopRoot 'apps\scoop\current\lib\download.ps1'
    if (-not (Test-Path $download)) {
        Write-ErrorAndExit "Scoop download.ps1 not found: $download"
    }
    return $download
}

function ConvertTo-MirrorUrl {
    param(
        [string]$Url,
        [string]$Prefix,
        [string[]]$AllPrefixes,
        [string[]]$GithubHosts
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }
    if (-not $AllPrefixes) { $AllPrefixes = @() }
    $bare = Strip-ScoopMirrorPrefix -Url $Url.Trim() -Prefixes $AllPrefixes

    if (-not $GithubHosts -or $GithubHosts.Count -eq 0) {
        $GithubHosts = @((Get-ScoopAccelConfig).githubHosts)
    }
    try {
        $hostName = ([Uri]$bare).Host
    }
    catch {
        return $bare
    }
    if ($GithubHosts -contains $hostName) {
        return (Join-ScoopMirrorUrl -Url $bare -Prefix $Prefix -AllPrefixes $AllPrefixes)
    }
    return $bare
}

. (Join-Path $PSScriptRoot 'deploy.ps1')

function Invoke-ScoopMirrorAccelFilterInit {
    param(
        [string]$FailureMessage
    )

    $cliJs = Join-Path $env:SCOOP 'config\scoop-mirror\cli.js'
    if (-not (Test-Path -LiteralPath $cliJs)) {
        Write-ErrorAndExit "scoop-mirror/cli.js not found: $cliJs"
    }

    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-ErrorAndExit 'Node.js is required for scoop mirror repair'
    }

    $output = & $node.Source $cliJs repair 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $FailureMessage }
        else { $detail = "${FailureMessage}: $detail" }
        Write-ErrorAndExit $detail
    }
}

function Test-ScoopCoreGitRepo {
    if ([string]::IsNullOrWhiteSpace($env:SCOOP)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $env:SCOOP 'apps\scoop\current\.git'))
}

function Test-ScoopFormalRepairReady {
    return [bool](Get-Command git.exe -ErrorAction SilentlyContinue) -and (Test-ScoopCoreGitRepo)
}

function Update-ScoopSessionPath {
    if ([string]::IsNullOrWhiteSpace($env:SCOOP)) { return }
    $env:PATH = "$env:SCOOP\shims;$env:SCOOP\apps\scoop\current\bin;$env:PATH"
}

# Append one dot-source line; keep original bytes/BOM/encoding untouched (scoop update discards this file).
function Install-ScoopDownloadHookTemporary {
    $hookHelper = Join-Path $env:SCOOP 'config\scoop-mirror\hook.ps1'
    if (-not (Test-Path -LiteralPath $hookHelper)) {
        Write-ErrorAndExit "scoop-mirror/hook.ps1 not found: $hookHelper (deploy mirror files first)"
    }

    $download = Get-ScoopLibDownloadPath
    $bytes = [System.IO.File]::ReadAllBytes($download)
    # Scoop's download.ps1 is UTF-8; marker check is enough for idempotent append.
    if ([System.Text.Encoding]::UTF8.GetString($bytes).Contains('scoop-mirror\hook.ps1')) {
        return
    }

    $useCrlf = $false
    for ($i = 0; $i -lt ($bytes.Length - 1); $i++) {
        if ($bytes[$i] -eq 13 -and $bytes[$i + 1] -eq 10) {
            $useCrlf = $true
            break
        }
    }
    $nl = if ($useCrlf) { "`r`n" } else { "`n" }
    $prefix = ''
    if ($bytes.Length -eq 0 -or $bytes[$bytes.Length - 1] -ne 10) {
        $prefix = $nl
    }
    $hookLine = [string]::Concat('. "', '$env:SCOOP\config\scoop-mirror\hook.ps1', '"')
    $append = [System.Text.Encoding]::UTF8.GetBytes($prefix + $hookLine + $nl)
    $out = New-Object byte[] ($bytes.Length + $append.Length)
    [System.Buffer]::BlockCopy($bytes, 0, $out, 0, $bytes.Length)
    [System.Buffer]::BlockCopy($append, 0, $out, $bytes.Length, $append.Length)
    [System.IO.File]::WriteAllBytes($download, $out)
}

function Install-ScoopDownloadHook {
    if (-not (Test-ScoopFormalRepairReady)) {
        Install-ScoopDownloadHookTemporary
        return
    }

    Invoke-ScoopMirrorAccelFilterInit -FailureMessage 'Could not install the Scoop download acceleration hook'
    Write-Info 'Scoop mirror hook and clean-worktree filter are ready'
}

function Install-ScoopBootstrapApps {
    param(
        [string[]]$Apps = @('7zip', 'git')
    )

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Scoop is required to install bootstrap apps'
    }

    foreach ($app in $Apps) {
        $commandName = if ($app -eq '7zip') { '7z' } else { $app }
        if (Get-Command $commandName -ErrorAction SilentlyContinue) {
            Write-Info "$app is already available; skipping"
            continue
        }

        Write-Info "Installing $app via Scoop..."
        # --no-update-scoop: Scoop's pre-install update needs Git and aborts on a zip bootstrap.
        Assert-ScoopWorktreeClean
        scoop install --no-update-scoop $app
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorAndExit "Failed to install $app via Scoop"
        }
        Update-ScoopSessionPath
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Git is still unavailable after scoop install git'
    }
}

function Get-ScoopKnownMainBucketUrl {
    $bucketsJson = Join-Path $env:SCOOP 'apps\scoop\current\buckets.json'
    if (Test-Path -LiteralPath $bucketsJson) {
        try {
            $data = Get-Content -LiteralPath $bucketsJson -Raw -Encoding UTF8 | ConvertFrom-Json
            $url = [string]$data.main
            if (-not [string]::IsNullOrWhiteSpace($url)) { return $url.Trim() }
        }
        catch { }
    }
    return 'https://github.com/ScoopInstaller/Main'
}

# Convert zip main → git via mirrored URL BEFORE scoop update.
# scoop update otherwise rm's main and re-adds from official GitHub (no scoop_repo).
function Ensure-ScoopMainBucketGit {
    param(
        [string]$ActivePrefix = '',
        $Prefixes
    )

    $mainRoot = Join-Path $env:SCOOP 'buckets\main'
    $mainGit = Join-Path $mainRoot '.git'
    if (Test-Path -LiteralPath $mainGit) {
        return
    }

    if ($null -eq $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes }
    $ActivePrefix = Resolve-ScoopKnownMirrorPrefix -Prefix $ActivePrefix -Prefixes $Prefixes -Quiet
    $bare = Get-ScoopKnownMainBucketUrl
    $url = Join-ScoopMirrorUrl -Url $bare -Prefix $ActivePrefix -AllPrefixes $Prefixes
    $label = Format-ScoopMirrorActiveLabel -ActivePrefix $ActivePrefix
    Write-Info "Ensuring main bucket as git repo via $label ($url)"

    if (Test-Path -LiteralPath $mainRoot) {
        scoop bucket rm main 2>$null | Out-Null
        if (Test-Path -LiteralPath $mainRoot) {
            Remove-Item -LiteralPath $mainRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $mainRoot) {
        Write-ErrorAndExit "Could not remove zip main bucket at $mainRoot"
    }

    scoop bucket add main $url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $mainGit)) {
        Write-ErrorAndExit (
            "Failed to add main bucket via $label ($url). " +
            'Check network/mirror, then rerun: vpr pm'
        )
    }
}

function Ensure-ScoopGitRepositories {
    param(
        [string]$ActivePrefix = '',
        $Accel
    )

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Git is required to convert Scoop into a git repository'
    }
    if (-not $env:SCOOP) {
        Write-ErrorAndExit 'SCOOP environment variable is not set'
    }

    $scoopGit = Join-Path $env:SCOOP 'apps\scoop\current\.git'
    $mainGit = Join-Path $env:SCOOP 'buckets\main\.git'
    if ((Test-Path -LiteralPath $scoopGit) -and (Test-Path -LiteralPath $mainGit)) {
        Write-Info 'Scoop and main bucket are already git repositories'
        return
    }

    if (-not $Accel) { $Accel = Get-ScoopAccelConfig }
    if ([string]::IsNullOrWhiteSpace($ActivePrefix)) {
        $ActivePrefix = Get-ScoopMirrorActivePrefix
    }
    $prefixes = Get-ScoopMirrorPrefixes
    $ActivePrefix = Resolve-ScoopKnownMirrorPrefix -Prefix $ActivePrefix -Prefixes $prefixes

    $expectedRepo = Get-ScoopRepoTargetUrl -ActivePrefix $ActivePrefix -Accel $Accel -Prefixes $prefixes
    Repair-ScoopRepoConfig -ExpectedUrl $expectedRepo

    # Must run before scoop update so it does not wipe zip main and clone official GitHub.
    Ensure-ScoopMainBucketGit -ActivePrefix $ActivePrefix -Prefixes $prefixes

    Write-Info 'Running scoop update to convert Scoop into a git repository...'
    scoop update
    Update-ScoopSessionPath

    if (-not (Test-Path -LiteralPath $scoopGit)) {
        Write-ErrorAndExit 'Scoop is still missing .git after scoop update'
    }
    if (-not (Test-Path -LiteralPath $mainGit)) {
        Write-ErrorAndExit 'main bucket is still missing .git after mirrored add + scoop update'
    }
}

function Assert-ScoopWorktreeClean {
    if (-not (Test-ScoopFormalRepairReady)) { return }
    Invoke-ScoopMirrorAccelFilterInit -FailureMessage 'Scoop package operation aborted because its tracked worktree is not clean'
}

function Set-ScoopBucketMirrors {
    param(
        [string]$ActivePrefix,
        $Prefixes
    )

    if (-not (Test-ScoopFormalRepairReady)) {
        return
    }

    if (-not $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes }
    $bucketsRoot = Join-Path $env:SCOOP 'buckets'
    if (-not (Test-Path $bucketsRoot)) { return }

    Get-ChildItem $bucketsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $gitDir = Join-Path $_.FullName '.git'
        if (-not (Test-Path $gitDir)) { return }
        $origin = git -C $_.FullName remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) { return }
        $mirrored = ConvertTo-MirrorUrl -Url $origin.Trim() -Prefix $ActivePrefix -AllPrefixes $Prefixes
        if ($mirrored -ne $origin.Trim()) {
            git -C $_.FullName remote set-url origin $mirrored 2>$null | Out-Null
        }
    }
}

function Get-ScoopMirrorActivePrefix {
    $cfgPath = Join-Path $env:SCOOP 'config\scoop-mirror\config.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return '' }
    try {
        $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return [string]$cfg.activePrefix
    }
    catch {
        return ''
    }
}

# Rewrite scoop export bucket Sources to the active mirror before import.
# Backup JSON keeps official GitHub URLs; import must not clone a stale baked-in mirror (e.g. dead ghfast).
function New-ScoopMirroredImportFile {
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,
        [string]$ActivePrefix,
        $Prefixes
    )

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        Write-ErrorAndExit "Scoop backup file not found: $BackupPath"
    }
    if (-not $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes }

    $data = Get-Content -LiteralPath $BackupPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $changed = $false
    foreach ($bucket in @($data.buckets)) {
        $source = [string]$bucket.Source
        if ([string]::IsNullOrWhiteSpace($source)) { continue }
        $mirrored = ConvertTo-MirrorUrl -Url $source -Prefix $ActivePrefix -AllPrefixes @($Prefixes)
        if ($mirrored -ne $source) {
            $bucket.Source = $mirrored
            $changed = $true
        }
    }

    if (-not $changed) { return $BackupPath }

    $temp = Join-Path ([IO.Path]::GetTempPath()) ("use-scoop-import-" + [Guid]::NewGuid().ToString('N') + '.json')
    Write-Utf8NoBomFile -Path $temp -Content (($data | ConvertTo-Json -Depth 8) + "`n")
    return $temp
}

function Install-ScoopAria2Accel {
    param($Accel)

    $aria = $Accel.aria2
    if (-not $aria) { return }

    if (-not (Get-Command aria2c -ErrorAction SilentlyContinue)) {
        Write-Info 'Installing aria2...'
        Assert-ScoopWorktreeClean
        scoop install aria2
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'aria2 installation failed; retry later. If the mirror does not support segmented downloads, run: scoop config aria2-enabled false'
            return
        }
    }

    Write-Info 'Configuring aria2 multithreaded downloads...'
    scoop config aria2-enabled $(if ($aria.enabled) { 'true' } else { 'false' })
    scoop config aria2-warning-enabled $(if ($aria.warningEnabled) { 'true' } else { 'false' })
    if ($null -ne $aria.retryWait) { scoop config aria2-retry-wait $aria.retryWait }
    if ($null -ne $aria.split) { scoop config aria2-split $aria.split }
    if ($null -ne $aria.maxConnectionPerServer) { scoop config aria2-max-connection-per-server $aria.maxConnectionPerServer }
    if ($null -ne $aria.minSplitSize) { scoop config aria2-min-split-size $aria.minSplitSize }
    Write-Info 'aria2 configuration complete'
}

# Deploy scoop-mirror files + scoop_repo. Hook / bucket remotes / aria2 are applied by the caller
# after bootstrap apps and scoop update (see runtime/scoop/install.ps1).
function Enable-ScoopAccel {
    param(
        $Manifest,
        [string]$Mirror = '',
        $ActivePrefix
    )

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Scoop is not installed; acceleration cannot be configured'
    }

    if (-not $env:SCOOP) {
        $env:SCOOP = (Read-Manifest).scoopDir
    }

    $accel = Get-ScoopAccelConfig -Manifest $Manifest
    $prefixes = Get-ScoopMirrorPrefixes

    if (-not $PSBoundParameters.ContainsKey('ActivePrefix')) {
        $ActivePrefix = Resolve-ScoopMirrorSelection -Choice $Mirror
    }
    $ActivePrefix = Resolve-ScoopKnownMirrorPrefix -Prefix $ActivePrefix -Prefixes $prefixes

    $activeLabel = Format-ScoopMirrorActiveLabel -ActivePrefix $ActivePrefix
    Write-Info "Applying Scoop acceleration; active mirror: $activeLabel"

    if (-not [string]::IsNullOrWhiteSpace($ActivePrefix)) {
        $probeTarget = [string]$accel.installScript
        if ([string]::IsNullOrWhiteSpace($probeTarget)) { $probeTarget = [string]$accel.scoopRepo }
        $probeUrl = Join-ScoopMirrorUrl -Url $probeTarget -Prefix $ActivePrefix -AllPrefixes $prefixes
        if (-not (Test-ScoopUrlReachable -Url $probeUrl)) {
            Write-Warn 'The selected mirror failed its probe; configuration will continue and downloads will fall back automatically'
        }
    }

    $scoopRepo = Get-ScoopRepoTargetUrl -ActivePrefix $ActivePrefix -Accel $accel -Prefixes $prefixes
    Set-ScoopRepoConfig -Url $scoopRepo

    Install-ScoopMirrorAccelFiles -Accel $accel -ActivePrefix $ActivePrefix -Prefixes $prefixes
    Install-ScoopServicesFiles
    Write-Info "Scoop acceleration files deployed (mirror: $activeLabel)"
}
