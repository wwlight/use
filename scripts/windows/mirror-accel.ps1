# Scoop download URL mirror helper.
# Deployed to $env:SCOOP\config\mirror-accel.ps1 and sourced from download.ps1.
# Order: activePrefix -> other prefixes -> official.
# Repair/preflight: powershell -NoProfile -File mirror-accel.ps1 -RepairHook

param(
    [switch]$RepairHook,
    [switch]$PrepareCommand,
    [switch]$GitFilterClean,
    [switch]$GitFilterSmudge,
    [switch]$ManageMirror,
    [string]$MirrorChoice = ''
)

$script:ScoopMirrorHookBegin = [Text.Encoding]::UTF8.GetBytes('# >>> scoop-mirror-accel')
$script:ScoopMirrorHookEnd = [Text.Encoding]::UTF8.GetBytes('# <<< scoop-mirror-accel')
$script:ScoopMirrorHook = [Text.Encoding]::UTF8.GetBytes("`n# >>> scoop-mirror-accel`n. `"`$env:SCOOP\config\mirror-accel.ps1`"`n# <<< scoop-mirror-accel`n")

function Find-ByteSequence {
    param([byte[]]$Bytes, [byte[]]$Sequence, [int]$Start = 0)
    if ($Sequence.Length -eq 0) { return $Start }
    for ($i = $Start; $i -le $Bytes.Length - $Sequence.Length; $i++) {
        $matches = $true
        for ($j = 0; $j -lt $Sequence.Length; $j++) {
            if ($Bytes[$i + $j] -ne $Sequence[$j]) {
                $matches = $false
                break
            }
        }
        if ($matches) { return $i }
    }
    return -1
}

function Remove-ScoopMirrorHookBytes {
    param([byte[]]$Bytes)
    $begin = Find-ByteSequence -Bytes $Bytes -Sequence $script:ScoopMirrorHookBegin
    if ($begin -lt 0) { return ,$Bytes }
    $end = Find-ByteSequence -Bytes $Bytes -Sequence $script:ScoopMirrorHookEnd -Start $begin
    if ($end -lt 0) { throw 'Incomplete Scoop mirror acceleration markers' }

    $start = $begin
    if ($start -gt 0 -and $Bytes[$start - 1] -eq 10) {
        $start--
        if ($start -gt 0 -and $Bytes[$start - 1] -eq 13) { $start-- }
    }
    $end += $script:ScoopMirrorHookEnd.Length
    if ($end -lt $Bytes.Length -and $Bytes[$end] -eq 13) { $end++ }
    if ($end -lt $Bytes.Length -and $Bytes[$end] -eq 10) { $end++ }

    $output = New-Object byte[] ($Bytes.Length - ($end - $start))
    if ($start -gt 0) { [Array]::Copy($Bytes, 0, $output, 0, $start) }
    if ($end -lt $Bytes.Length) { [Array]::Copy($Bytes, $end, $output, $start, $Bytes.Length - $end) }
    return ,$output
}

function Add-ScoopMirrorHookBytes {
    param([byte[]]$Bytes)
    if ((Find-ByteSequence -Bytes $Bytes -Sequence $script:ScoopMirrorHookBegin) -ge 0) { return ,$Bytes }
    $output = New-Object byte[] ($Bytes.Length + $script:ScoopMirrorHook.Length)
    if ($Bytes.Length -gt 0) { [Array]::Copy($Bytes, 0, $output, 0, $Bytes.Length) }
    [Array]::Copy($script:ScoopMirrorHook, 0, $output, $Bytes.Length, $script:ScoopMirrorHook.Length)
    return ,$output
}

function Test-ByteArraysEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($i = 0; $i -lt $Left.Length; $i++) {
        if ($Left[$i] -ne $Right[$i]) { return $false }
    }
    return $true
}

function Test-ScoopMirrorLegacyLineEndingDamage {
    param([byte[]]$Current, [byte[]]$Tracked)
    try {
        $utf8 = New-Object Text.UTF8Encoding $false, $true
        $currentText = $utf8.GetString($Current).TrimStart([char]0xFEFF).Replace("`r`n", "`n")
        $trackedText = $utf8.GetString($Tracked).TrimStart([char]0xFEFF).Replace("`r`n", "`n")
        return $currentText -ceq $trackedText
    }
    catch {
        return $false
    }
}

function Invoke-ScoopMirrorGitFilter {
    param([switch]$Clean)
    $inputStream = [Console]::OpenStandardInput()
    $memory = New-Object IO.MemoryStream
    $inputStream.CopyTo($memory)
    $bytes = $memory.ToArray()
    [byte[]]$output = if ($Clean) { Remove-ScoopMirrorHookBytes -Bytes $bytes } else { Add-ScoopMirrorHookBytes -Bytes $bytes }
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($output, 0, $output.Length)
}

if ($GitFilterClean -or $GitFilterSmudge) {
    Invoke-ScoopMirrorGitFilter -Clean:$GitFilterClean
    exit 0
}

function Get-GitBlobBytes {
    param([string]$Repository, [string]$Object)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = 'git.exe'
    $quotedRepo = $Repository.Replace('"', '\"')
    $quotedObject = $Object.Replace('"', '\"')
    $start.Arguments = "-C `"$quotedRepo`" cat-file blob `"$quotedObject`""
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    $memory = New-Object IO.MemoryStream
    $process.StandardOutput.BaseStream.CopyTo($memory)
    $errorText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Could not read Scoop's tracked download.ps1: $errorText" }
    return ,$memory.ToArray()
}

function Initialize-ScoopMirrorAccelFilter {
    if ([string]::IsNullOrWhiteSpace($env:SCOOP)) { throw 'SCOOP environment variable is not set' }

    $helper = Join-Path $env:SCOOP 'config\mirror-accel.ps1'
    $scoopRepo = Join-Path $env:SCOOP 'apps\scoop\current'
    $download = Join-Path $scoopRepo 'lib\download.ps1'
    if (-not (Test-Path -LiteralPath $helper)) { throw "Scoop mirror helper not found: $helper" }
    if (-not (Test-Path -LiteralPath (Join-Path $scoopRepo '.git'))) { throw "Scoop Git repository not found: $scoopRepo" }
    if (-not (Test-Path -LiteralPath $download)) { throw "Scoop download.ps1 not found: $download" }

    $filterPath = $helper.Replace('\', '/').Replace("'", "'\''")
    $filterBase = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$filterPath'"
    & git.exe -C $scoopRepo config --local filter.scoop-mirror-accel.clean "$filterBase -GitFilterClean"
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure the Scoop mirror clean filter' }
    & git.exe -C $scoopRepo config --local filter.scoop-mirror-accel.smudge "$filterBase -GitFilterSmudge"
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure the Scoop mirror smudge filter' }
    & git.exe -C $scoopRepo config --local filter.scoop-mirror-accel.required true
    if ($LASTEXITCODE -ne 0) { throw 'Could not require the Scoop mirror Git filter' }

    $attributes = Join-Path $scoopRepo '.git\info\attributes'
    $attributeLine = 'lib/download.ps1 filter=scoop-mirror-accel -text'
    $attributeContent = if (Test-Path -LiteralPath $attributes) {
        @((Get-Content -LiteralPath $attributes -Encoding UTF8) | Where-Object { $_ -notmatch '^\s*lib/download\.ps1\s+.*filter=scoop-mirror-accel' })
    }
    else { @() }
    $attributeContent += $attributeLine
    [IO.File]::WriteAllText($attributes, (($attributeContent -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))

    # Rebuild only our managed file from the index, then let the smudge transform add the runtime hook.
    # This also repairs line-ending damage from older versions without using destructive Git restore commands.
    $tracked = Get-GitBlobBytes -Repository $scoopRepo -Object ':lib/download.ps1'
    $current = [IO.File]::ReadAllBytes($download)
    $currentWithoutHook = Remove-ScoopMirrorHookBytes -Bytes $current
    if (-not (Test-ByteArraysEqual -Left $currentWithoutHook -Right $tracked) -and
        -not (Test-ScoopMirrorLegacyLineEndingDamage -Current $currentWithoutHook -Tracked $tracked)) {
        throw 'Scoop lib/download.ps1 contains changes unrelated to the mirror hook; refusing to overwrite them'
    }
    $runtime = Add-ScoopMirrorHookBytes -Bytes $tracked
    [IO.File]::WriteAllBytes($download, $runtime)

    $indexObjectBefore = "$(& git.exe -C $scoopRepo rev-parse --verify ':lib/download.ps1')".Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($indexObjectBefore)) {
        throw 'Could not read the Scoop download.ps1 index object'
    }

    # Ask Git to run the clean filter and cache the runtime file's stat data.
    # The byte validation above guarantees the clean result is the tracked blob;
    # verify that invariant explicitly so this cannot stage different content.
    & git.exe -C $scoopRepo update-index --add -- lib/download.ps1
    $refreshExitCode = $LASTEXITCODE
    $indexObjectAfter = "$(& git.exe -C $scoopRepo rev-parse --verify ':lib/download.ps1')".Trim()
    $objectReadExitCode = $LASTEXITCODE
    if ($refreshExitCode -ne 0) { throw 'Could not refresh the Scoop download.ps1 index metadata' }
    if ($objectReadExitCode -ne 0 -or $indexObjectAfter -cne $indexObjectBefore) {
        throw 'Scoop download.ps1 index object changed while refreshing metadata'
    }

    $dirty = @(& git.exe -C $scoopRepo status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify the Scoop Git worktree' }
    if ($dirty.Count -gt 0) {
        throw "Scoop has unrelated tracked changes; refusing to start a package operation:`n$($dirty -join "`n")"
    }
}

if ($RepairHook -or $PrepareCommand) {
    try {
        Initialize-ScoopMirrorAccelFilter
        if ($RepairHook) { Write-Host 'Scoop mirror hook and clean-worktree filter are ready' -ForegroundColor Cyan }
        exit 0
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}

function Get-ScoopMirrorAccelConfig {
    if ($script:ScoopMirrorAccelConfig) { return $script:ScoopMirrorAccelConfig }

    $cfgPath = Join-Path $env:SCOOP 'config\mirror-accel.json'
    if (-not (Test-Path $cfgPath)) { return $null }

    $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $prefixes = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($cfg.mirrorPrefix)) {
        $p = [string]$item
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not $p.EndsWith('/')) { $p += '/' }
        if (-not $prefixes.Contains($p)) { [void]$prefixes.Add($p) }
    }

    $mirrors = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($cfg.mirrors)) {
        $id = [string]$item.id
        $prefix = [string]$item.prefix
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($prefix)) { continue }
        if (-not $prefix.EndsWith('/')) { $prefix += '/' }
        [void]$mirrors.Add([pscustomobject]@{ Id = $id; Prefix = $prefix })
    }
    if ($mirrors.Count -eq 0) {
        foreach ($prefix in $prefixes) {
            try {
                $firstLabel = ([Uri]$prefix).Host.Split('.')[0]
                $id = $firstLabel -replace '[^A-Za-z0-9]', ''
            }
            catch {
                $id = ($prefix -replace '^https?://', '') -replace '[^A-Za-z0-9].*$', ''
            }
            if ([string]::IsNullOrWhiteSpace($id)) { $id = $prefix }
            [void]$mirrors.Add([pscustomobject]@{ Id = $id; Prefix = $prefix })
        }
    }

    $active = $null
    if ($null -ne $cfg.PSObject.Properties['activePrefix']) {
        $active = [string]$cfg.activePrefix
        if (-not [string]::IsNullOrWhiteSpace($active) -and -not $active.EndsWith('/')) {
            $active += '/'
        }
    }
    elseif ($prefixes.Count -gt 0) {
        $active = $prefixes[0]
    }
    else {
        $active = ''
    }

    $script:ScoopMirrorAccelConfig = [pscustomobject]@{
        Prefixes     = $prefixes.ToArray()
        Mirrors      = $mirrors.ToArray()
        ActivePrefix = $active
        GithubHosts  = @($cfg.githubHosts)
        ScoopRepo    = [string]$cfg.scoopRepo
        ConfigPath   = $cfgPath
    }
    return $script:ScoopMirrorAccelConfig
}

function Strip-ScoopMirrorAccelPrefix {
    param(
        [string]$Url,
        [string[]]$Prefixes
    )
    foreach ($p in $Prefixes) {
        if ($Url.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) {
            return $Url.Substring($p.Length)
        }
    }
    return $Url
}

function Test-ScoopMirrorAccelHost {
    param(
        [string]$Url,
        [string[]]$Hosts
    )
    try {
        $uri = [Uri]$Url
    }
    catch {
        return $false
    }
    return ($Hosts -contains $uri.Host)
}

function Get-ScoopMirrorAccelId {
    param(
        [string]$Prefix,
        $Config
    )
    if ([string]::IsNullOrWhiteSpace($Prefix)) { return 'official' }
    if (-not $Config) { $Config = Get-ScoopMirrorAccelConfig }
    foreach ($mirror in @($Config.Mirrors)) {
        if ($mirror.Prefix.TrimEnd('/') -eq $Prefix.TrimEnd('/')) { return $mirror.Id }
    }
    return $Prefix
}

function Resolve-ScoopMirrorAccelChoice {
    param(
        [string]$Choice,
        $Config
    )
    $Choice = "$Choice".Trim()
    if ($Choice -eq 'official') { return '' }
    foreach ($mirror in @($Config.Mirrors)) {
        if ($mirror.Id -eq $Choice -or
            $mirror.Prefix -eq $Choice -or
            $mirror.Prefix.TrimEnd('/') -eq $Choice.TrimEnd('/')) {
            return $mirror.Prefix
        }
    }
    throw "Unknown Scoop mirror '$Choice'. Run 'scoop mirror list' to see available mirrors."
}

function Get-ScoopMirrorUpstreamRepo {
    param($Config)
    if (-not [string]::IsNullOrWhiteSpace($Config.ScoopRepo)) { return $Config.ScoopRepo }

    $repo = "$(& scoop config scoop_repo 2>$null)".Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
        return 'https://github.com/ScoopInstaller/Scoop'
    }
    return (Strip-ScoopMirrorAccelPrefix -Url $repo -Prefixes $Config.Prefixes)
}

function Set-ScoopMirrorBucketRemotes {
    param(
        [string]$ActivePrefix,
        $Config
    )
    $bucketsRoot = Join-Path $env:SCOOP 'buckets'
    if (-not (Test-Path -LiteralPath $bucketsRoot)) { return }

    Get-ChildItem -LiteralPath $bucketsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not (Test-Path -LiteralPath (Join-Path $_.FullName '.git'))) { return }
        $origin = "$(& git.exe -C $_.FullName remote get-url origin 2>$null)".Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) { return }

        $bare = Strip-ScoopMirrorAccelPrefix -Url $origin -Prefixes $Config.Prefixes
        if (-not (Test-ScoopMirrorAccelHost -Url $bare -Hosts $Config.GithubHosts)) { return }
        $target = if ([string]::IsNullOrWhiteSpace($ActivePrefix)) { $bare } else { $ActivePrefix + $bare }
        if ($target -eq $origin) { return }

        & git.exe -C $_.FullName remote set-url origin $target
        if ($LASTEXITCODE -ne 0) { throw "Could not switch bucket '$($_.Name)' to $target" }
    }
}

function Write-ScoopMirrorStatus {
    param($Config)
    $activeId = Get-ScoopMirrorAccelId -Prefix $Config.ActivePrefix -Config $Config
    $activeLabel = if ($activeId -eq 'official') { 'official' } else { "$activeId ($($Config.ActivePrefix))" }
    Write-Host "Active mirror: $activeLabel" -ForegroundColor Cyan

    $repo = "$(& scoop config scoop_repo 2>$null)".Trim()
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($repo)) {
        Write-Host "Scoop repo:    $repo"
    }
    Write-Host 'Download rule: selected mirror -> other mirrors -> official; non-GitHub URLs use direct'
}

function Invoke-ScoopMirrorManager {
    param([string]$Choice)
    if ([string]::IsNullOrWhiteSpace($env:SCOOP)) { throw 'SCOOP environment variable is not set' }
    $config = Get-ScoopMirrorAccelConfig
    if (-not $config) { throw "Scoop mirror config not found at $env:SCOOP\config\mirror-accel.json" }

    $Choice = "$Choice".Trim()
    if ([string]::IsNullOrWhiteSpace($Choice) -or $Choice -in @('status', 'show')) {
        Write-ScoopMirrorStatus -Config $config
        return
    }
    if ($Choice -in @('list', '-h', '--help', 'help')) {
        Write-Host 'Usage: scoop mirror [status|list|<name>|official]'
        Write-Host ''
        foreach ($mirror in @($config.Mirrors)) {
            $marker = if ($mirror.Prefix -eq $config.ActivePrefix) { '*' } else { ' ' }
            Write-Host ("{0} {1,-12} {2}" -f $marker, $mirror.Id, $mirror.Prefix)
        }
        $officialMarker = if ([string]::IsNullOrWhiteSpace($config.ActivePrefix)) { '*' } else { ' ' }
        Write-Host ("{0} {1,-12} {2}" -f $officialMarker, 'official', 'https://github.com/ScoopInstaller/Scoop')
        return
    }

    $activePrefix = Resolve-ScoopMirrorAccelChoice -Choice $Choice -Config $config
    $upstreamRepo = Get-ScoopMirrorUpstreamRepo -Config $config
    $repo = if ([string]::IsNullOrWhiteSpace($activePrefix)) { $upstreamRepo } else { $activePrefix + $upstreamRepo }

    & scoop config scoop_repo $repo
    if ($LASTEXITCODE -ne 0) { throw "Could not set Scoop repo to $repo" }
    Set-ScoopMirrorBucketRemotes -ActivePrefix $activePrefix -Config $config

    $raw = Get-Content -LiteralPath $config.ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $raw.PSObject.Properties['activePrefix']) {
        $raw | Add-Member -NotePropertyName activePrefix -NotePropertyValue $activePrefix
    }
    else {
        $raw.activePrefix = $activePrefix
    }
    $encoding = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($config.ConfigPath, (($raw | ConvertTo-Json -Depth 8) + "`n"), $encoding)
    $script:ScoopMirrorAccelConfig = $null

    $id = Get-ScoopMirrorAccelId -Prefix $activePrefix -Config $config
    Write-Host "Scoop mirror switched to $id" -ForegroundColor Cyan
    Write-ScoopMirrorStatus -Config (Get-ScoopMirrorAccelConfig)
}

if ($ManageMirror) {
    try {
        Invoke-ScoopMirrorManager -Choice $MirrorChoice
        exit 0
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}

function Get-ScoopMirrorAccelCandidates {
    param([string]$Url)

    $cfg = Get-ScoopMirrorAccelConfig
    if (-not $cfg) {
        $one = New-Object System.Collections.Generic.List[string]
        [void]$one.Add($Url)
        return $one
    }

    $bare = Strip-ScoopMirrorAccelPrefix -Url $Url -Prefixes $cfg.Prefixes
    if (-not (Test-ScoopMirrorAccelHost -Url $bare -Hosts $cfg.GithubHosts)) {
        $one = New-Object System.Collections.Generic.List[string]
        [void]$one.Add($bare)
        return $one
    }

    $list = New-Object System.Collections.Generic.List[string]
    $active = [string]$cfg.ActivePrefix

    # Prefer the active prefix, then other mirrors, then upstream.
    if (-not [string]::IsNullOrWhiteSpace($active)) {
        $first = $active + $bare
        if (-not $list.Contains($first)) { [void]$list.Add($first) }
        foreach ($p in $cfg.Prefixes) {
            if ($p -eq $active) { continue }
            $candidate = $p + $bare
            if (-not $list.Contains($candidate)) { [void]$list.Add($candidate) }
        }
    }

    if (-not $list.Contains($bare)) { [void]$list.Add($bare) }
    return $list
}

function Get-ScoopMirrorAccelLabelFromUrl {
    param([string]$Url)

    $cfg = Get-ScoopMirrorAccelConfig
    if (-not $cfg) { return 'direct' }
    foreach ($mirror in @($cfg.Mirrors)) {
        if ($Url.StartsWith($mirror.Prefix, [StringComparison]::OrdinalIgnoreCase)) { return $mirror.Id }
    }
    if (Test-ScoopMirrorAccelHost -Url $Url -Hosts $cfg.GithubHosts) { return 'official' }
    return 'direct'
}

function Write-ScoopMirrorAccelUsed {
    param([string]$Url)

    $label = Get-ScoopMirrorAccelLabelFromUrl -Url $Url
    if ($script:ScoopMirrorAccelLastShown -eq $label) { return }
    $script:ScoopMirrorAccelLastShown = $label
    Write-Host "Scoop source: $label" -ForegroundColor Cyan
}

function Write-ScoopMirrorAccelCacheUsed {
    if ($script:ScoopMirrorAccelLastShown -eq 'cache') { return }
    $script:ScoopMirrorAccelLastShown = 'cache'
    Write-Host 'Scoop source: cache' -ForegroundColor Cyan
}

function Get-ScoopMirrorAccelDirectHosts {
    param([string[]]$Urls)

    $cfg = Get-ScoopMirrorAccelConfig
    if (-not $cfg) { return @() }
    $hosts = New-Object System.Collections.Generic.List[string]
    foreach ($url in @($Urls)) {
        $bare = Strip-ScoopMirrorAccelPrefix -Url $url -Prefixes $cfg.Prefixes
        if (Test-ScoopMirrorAccelHost -Url $bare -Hosts $cfg.GithubHosts) { continue }
        try { $hostName = ([Uri]$bare).Host }
        catch { continue }
        if (-not [string]::IsNullOrWhiteSpace($hostName) -and -not $hosts.Contains($hostName)) {
            [void]$hosts.Add($hostName)
        }
    }
    return $hosts.ToArray()
}

function Write-ScoopMirrorAccelDirectNotice {
    param([string[]]$Hosts)
    if ($Hosts.Count -eq 0) { return }
    $script:ScoopMirrorAccelLastShown = 'direct'
    Write-Host "Scoop source: direct ($($Hosts -join ', '); GitHub mirror unavailable for this host)" -ForegroundColor Yellow
}

# aria2 / single-shot: pick a candidate by attempt index (0 = active first).
function ConvertTo-ScoopMirrorUrl {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }

    $cfg = Get-ScoopMirrorAccelConfig
    if (-not $cfg) { return $Url }

    $bare = Strip-ScoopMirrorAccelPrefix -Url $Url -Prefixes $cfg.Prefixes
    if (-not (Test-ScoopMirrorAccelHost -Url $bare -Hosts $cfg.GithubHosts)) {
        return $bare
    }

    $candidates = @(Get-ScoopMirrorAccelCandidates -Url $bare)
    if ($candidates.Count -eq 0) { return $bare }

    $idx = 0
    if ($null -ne $script:ScoopMirrorAria2Attempt) {
        $idx = [int]$script:ScoopMirrorAria2Attempt
    }
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $candidates.Count) { $idx = $candidates.Count - 1 }
    return $candidates[$idx]
}

if ($script:ScoopMirrorAccelWrapped) { return }
$script:ScoopMirrorAccelWrapped = $true
$script:ScoopMirrorAria2Attempt = 0

if (Get-Command handle_special_urls -ErrorAction SilentlyContinue) {
    $script:ScoopMirrorOrigHandleSpecialUrls = $function:handle_special_urls
    function handle_special_urls($url) {
        $url = & $script:ScoopMirrorOrigHandleSpecialUrls $url
        return (ConvertTo-ScoopMirrorUrl $url)
    }
}

# WebRequest path: active, other mirrors, then upstream.
if (Get-Command Start-Download -ErrorAction SilentlyContinue) {
    function Start-Download ($url, $to, $cookies) {
        # Match Scoop upstream quoting; parentheses are required by the PowerShell parser.
        $progress = [console]::isoutputredirected -eq $false -and
            ($Host.Name -ne 'Windows PowerShell ISE Host')

        try {
            if ($script:ScoopMirrorOrigHandleSpecialUrls) {
                $resolved = & $script:ScoopMirrorOrigHandleSpecialUrls $url
            }
            else {
                $resolved = $url
            }
        }
        catch {
            $e = $_.Exception
            if ($e.Response.StatusCode -eq 'Unauthorized') {
                warn 'Token might be misconfigured.'
            }
            if ($e.innerexception) { $e = $e.innerexception }
            throw $e
        }

        $candidates = Get-ScoopMirrorAccelCandidates -Url $resolved
        $lastError = $null
        foreach ($candidate in $candidates) {
            try {
                Invoke-Download $candidate $to $cookies $progress
                Write-ScoopMirrorAccelUsed -Url $candidate
                return
            }
            catch {
                $lastError = $_.Exception
                if ($lastError.InnerException) { $lastError = $lastError.InnerException }
                if (Test-Path -LiteralPath $to) {
                    Remove-Item -LiteralPath $to -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if ($lastError) { throw $lastError }
        throw "Download failed for $url"
    }
}

# aria2: retry with the next mirror candidate on failure.
if (Get-Command Invoke-CachedAria2Download -ErrorAction SilentlyContinue) {
    $script:ScoopMirrorOrigAria2Download = ${function:Invoke-CachedAria2Download}
    function Invoke-CachedAria2Download ($app, $version, $manifest, $architecture, $dir, $cookies = $null, $use_cache = $true, $check_hash = $true) {
        $urls = @(script:url $manifest $architecture)
        $allCached = $use_cache -and $urls.Count -gt 0
        if ($allCached) {
            foreach ($url in $urls) {
                if (-not (Test-Path -LiteralPath (cache_path $app $version $url))) {
                    $allCached = $false
                    break
                }
            }
        }
        $directHosts = @()
        if (-not $allCached) {
            $directHosts = @(Get-ScoopMirrorAccelDirectHosts -Urls $urls)
            Write-ScoopMirrorAccelDirectNotice -Hosts $directHosts
        }
        $maxAttempts = 1
        if ($urls.Count -gt 0) {
            $sample = Get-ScoopMirrorAccelCandidates -Url $urls[0]
            $maxAttempts = [Math]::Max(1, $sample.Count)
        }

        $lastError = $null
        for ($i = 0; $i -lt $maxAttempts; $i++) {
            $script:ScoopMirrorAria2Attempt = $i
            try {
                & $script:ScoopMirrorOrigAria2Download $app $version $manifest $architecture $dir $cookies $use_cache $check_hash
                if ($allCached) {
                    Write-ScoopMirrorAccelCacheUsed
                }
                elseif ($urls.Count -gt 0) {
                    Write-ScoopMirrorAccelUsed -Url (ConvertTo-ScoopMirrorUrl $urls[0])
                }
                $script:ScoopMirrorAria2Attempt = 0
                return
            }
            catch {
                $lastError = $_
                if ($i -lt $maxAttempts - 1) {
                    Write-Host "aria2 failed; trying the next mirror ($($i + 2)/$maxAttempts)..." -ForegroundColor Yellow
                }
            }
        }

        $script:ScoopMirrorAria2Attempt = 0
        if ($directHosts.Count -gt 0) {
            Write-Host "Direct aria2 download failed; configured GitHub mirrors cannot proxy $($directHosts -join ', ')." -ForegroundColor Yellow
        }
        if ($lastError) { throw $lastError.Exception }
        throw "aria2 download failed for $app"
    }
}
