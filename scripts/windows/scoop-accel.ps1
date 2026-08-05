# Apply Scoop mirror and aria2 acceleration. Requires utils.ps1.

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

function Get-ScoopMirrorUrlCandidates {
    param(
        [string]$Url,
        $Prefixes
    )
    $bare = Strip-ScoopMirrorPrefix -Url $Url -Prefixes $Prefixes
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($Prefixes)) {
        $prefix = [string]$p
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
        $candidate = $prefix + $bare
        if (-not $list.Contains($candidate)) { [void]$list.Add($candidate) }
    }
    if (-not $list.Contains($bare)) { [void]$list.Add($bare) }
    return $list
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
        [string[]]$Items
    )

    $menuScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\lib\menu-select.mjs'))
    if (-not (Test-Path $menuScript)) {
        Write-ErrorAndExit "Menu script not found: $menuScript"
    }
    $outFile = [System.IO.Path]::GetTempFileName()
    try {
        $env:MENU_SELECT_OUT = $outFile
        $menuArgs = @($Title) + @($Items | Where-Object { $_ })
        & node $menuScript @menuArgs
        if ($LASTEXITCODE -ne 0) { return '' }
        $choice = (Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        return "$choice".Trim()
    }
    finally {
        Remove-Item Env:MENU_SELECT_OUT -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-ScoopMirrorSelection {
    param([string]$Choice = '')

    $map = Get-GithubAccelSelectionMap
    if ($Choice -match '^--(.+)$') { $Choice = $Matches[1] }
    $Choice = "$Choice".Trim()

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
    foreach ($k in @($map.Keys)) {
        if ($k -eq 'official') {
            [void]$menuItems.Add("${k}) Upstream")
        }
        else {
            [void]$menuItems.Add("${k}) $($map[$k])")
        }
    }

    $selected = Invoke-NodeMenuSelect -Title 'Choose a Scoop mirror' -Items @($menuItems)
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

function Invoke-ScoopInstallScriptWithFallback {
    param(
        $Accel,
        [string]$PreferredPrefix = $null
    )

    # Run the bootstrap installer only from upstream to avoid piping a modified mirror response to iex.
    # PreferredPrefix accelerates downloads and repositories after installation, not remote script execution.
    $null = $PreferredPrefix
    $url = [string]$Accel.installScript
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-ErrorAndExit 'scoopAccel.installScript is empty'
    }

    Write-Info "Trying installer (upstream): $url"
    Write-Info 'Mirror acceleration starts after Scoop installs; run vpr hosts first if upstream is unreachable'
    try {
        if (Test-Administrator) {
            iex "& {$(irm $url)} -RunAsAdmin"
        }
        else {
            Invoke-RestMethod -Uri $url | Invoke-Expression
        }
        Write-Info 'Installer succeeded (upstream)'
        return
    }
    catch {
        Write-ErrorAndExit "Scoop installation failed (upstream installer): $($_.Exception.Message)"
    }
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
        [string[]]$AllPrefixes
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }
    if (-not $AllPrefixes) { $AllPrefixes = @() }
    $bare = Strip-ScoopMirrorPrefix -Url $Url.Trim() -Prefixes $AllPrefixes
    if ($bare -match '^https://github\.com/' -or $bare -match '^https://raw\.githubusercontent\.com/') {
        return (Join-ScoopMirrorUrl -Url $bare -Prefix $Prefix -AllPrefixes $AllPrefixes)
    }
    return $bare
}

function Write-Utf8NoBomFile {
    param(
        [string]$Path,
        [string]$Content
    )
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Install-ScoopMirrorAccelFiles {
    param(
        $Accel,
        [string]$ActivePrefix,
        $Prefixes
    )

    $scoopRoot = $env:SCOOP
    if (-not $scoopRoot) { Write-ErrorAndExit 'SCOOP environment variable is not set' }

    $configDir = Join-Path $scoopRoot 'config'
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    if (-not $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes }

    $jsonPath = Join-Path $configDir 'mirror-accel.json'
    $payload = [ordered]@{
        mirrorPrefix = @($Prefixes)
        activePrefix = $ActivePrefix
        githubHosts  = @($Accel.githubHosts)
    }
    Write-Utf8NoBomFile -Path $jsonPath -Content (($payload | ConvertTo-Json -Depth 5) + "`n")

    $src = Join-Path $PSScriptRoot 'mirror-accel.ps1'
    if (-not (Test-Path $src)) {
        Write-ErrorAndExit "mirror-accel.ps1 not found: $src"
    }
    $dest = Join-Path $configDir 'mirror-accel.ps1'
    Copy-FileDataOnly -SourceFile $src -DestinationFile $dest -Encoding 'utf8Bom'
    Write-Info "Synced mirror-accel to $dest"
}

function Install-ScoopDownloadHook {
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Write-Warn 'Git is not available yet; deferring the Scoop download hook until Git installs'
        return
    }

    $helper = Join-Path $env:SCOOP 'config\mirror-accel.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper -RepairHook
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit 'Could not install the Scoop download acceleration hook'
    }
}

function Assert-ScoopWorktreeClean {
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        # A fresh Scoop bootstrap has no hook yet and installs Git before acceleration is activated.
        return
    }
    $helper = Join-Path $env:SCOOP 'config\mirror-accel.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper -PrepareCommand
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit 'Scoop package operation aborted because its tracked worktree is not clean'
    }
}

function Set-ScoopBucketMirrors {
    param(
        [string]$ActivePrefix,
        $Prefixes
    )

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

function Enable-ScoopAccel {
    param(
        $Manifest,
        [string]$Mirror = '',
        $ActivePrefix,
        [switch]$SkipAria2
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
    $ActivePrefix = [string]$ActivePrefix

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

    if ([string]::IsNullOrWhiteSpace($ActivePrefix)) {
        scoop config scoop_repo ([string]$accel.scoopRepo)
    }
    else {
        $scoopRepo = Join-ScoopMirrorUrl -Url ([string]$accel.scoopRepo) -Prefix $ActivePrefix -AllPrefixes $prefixes
        scoop config scoop_repo $scoopRepo
    }

    Install-ScoopMirrorAccelFiles -Accel $accel -ActivePrefix $ActivePrefix -Prefixes $prefixes
    Install-ScoopDownloadHook
    Set-ScoopBucketMirrors -ActivePrefix $ActivePrefix -Prefixes $prefixes

    if (-not $SkipAria2) {
        Install-ScoopAria2Accel -Accel $accel
    }

    Write-Info "Scoop acceleration configured (mirror: $activeLabel)"
}
