# Scoop mirror URL + scoop_repo helpers. Requires utils.ps1.

function Get-ScoopMirrorSettings {
    param($Manifest)
    if (-not $Manifest) { $Manifest = Read-Manifest }
    $settings = $Manifest.scoopAccel
    if (-not $settings) {
        Write-ErrorAndExit 'windows manifest is missing scoopAccel'
    }
    return $settings
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
        $Settings,
        $Prefixes
    )
    if (-not $Settings) { $Settings = Get-ScoopMirrorSettings }
    if ($null -eq $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes }
    $prefix = Resolve-ScoopKnownMirrorPrefix -Prefix $ActivePrefix -Prefixes $Prefixes -Quiet
    $bare = [string]$Settings.scoopRepo
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
    # scoop config Write-Hosts the value; hide host noise and discard streams.
    Invoke-QuietHost { scoop config scoop_repo $Url *>$null }
}

# Self-heal polluted scoop_repo before scoop update.
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
        Write-Detail 'Updating scoop_repo to match active mirror'
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

# Opt-in soft probe (USE_SCOOP_MIRROR_PROBE=1). Downloads already fall back via hook.
function Test-ScoopUrlReachable {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$TimeoutSec = 8
    )
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method = 'HEAD'
        $req.Timeout = $TimeoutSec * 1000
        $req.AllowAutoRedirect = $true
        $resp = $req.GetResponse()
        $resp.Close()
        return $true
    }
    catch {
        try {
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method = 'GET'
            $req.Timeout = $TimeoutSec * 1000
            $req.AllowAutoRedirect = $true
            $resp = $req.GetResponse()
            $resp.Close()
            return $true
        }
        catch {
            return $false
        }
    }
}

function Format-ScoopMirrorActiveLabel {
    param([string]$ActivePrefix)
    if ([string]::IsNullOrWhiteSpace($ActivePrefix)) { return 'Upstream' }
    return $ActivePrefix
}

function Format-ScoopMirrorHostLabel {
    param([string]$ActivePrefix)
    if ([string]::IsNullOrWhiteSpace($ActivePrefix)) { return 'Upstream' }
    try {
        $hostName = ([Uri]$ActivePrefix).Host
        if (-not [string]::IsNullOrWhiteSpace($hostName)) { return $hostName }
    }
    catch { }
    return $ActivePrefix.TrimEnd('/')
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
        $GithubHosts = @((Get-ScoopMirrorSettings).githubHosts)
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

function Get-ScoopMirrorActivePrefix {
    $cfgPath = Join-Path (Get-ScoopConfigDir) 'mirror\state.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return '' }
    try {
        $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return [string]$cfg.activePrefix
    }
    catch {
        return ''
    }
}
