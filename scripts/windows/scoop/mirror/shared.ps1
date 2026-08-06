# Shared Scoop mirror helpers (config + download URL selection).

function Get-ScoopMirrorAccelConfig {
    if ($script:ScoopMirrorAccelConfig) { return $script:ScoopMirrorAccelConfig }

    $cfgPath = Join-Path $env:SCOOP 'config\scoop-mirror\config.json'
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
    throw "Unknown Scoop mirror '$Choice'. Run 'scoop mirror' to see available mirrors."
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
