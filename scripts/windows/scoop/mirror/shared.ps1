# Shared Scoop mirror helpers for the download hook (config + URL selection).

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
