# Scoop download URL mirror helper.
# Deployed to $env:SCOOP\config\mirror-accel.ps1 and sourced from download.ps1.
# Order: activePrefix -> other prefixes -> official.
# Repair hook only: powershell -NoProfile -File mirror-accel.ps1 -RepairHook

param([switch]$RepairHook)

# Re-inject download.ps1 hook after scoop self-update replaces apps\scoop\current.
function Repair-ScoopMirrorAccelHook {
    if ([string]::IsNullOrWhiteSpace($env:SCOOP)) { return $false }

    $helper = Join-Path $env:SCOOP 'config\mirror-accel.ps1'
    $download = Join-Path $env:SCOOP 'apps\scoop\current\lib\download.ps1'
    if (-not (Test-Path -LiteralPath $helper)) { return $false }
    if (-not (Test-Path -LiteralPath $download)) { return $false }

    $markerBegin = '# >>> scoop-mirror-accel'
    $markerEnd = '# <<< scoop-mirror-accel'
    $content = Get-Content -LiteralPath $download -Raw -Encoding UTF8
    if ($null -eq $content) { $content = '' }
    if ($content.Contains($markerBegin)) { return $false }

    $hook = "`n$markerBegin`n. `"`$env:SCOOP\config\mirror-accel.ps1`"`n$markerEnd`n"
    if (-not $content.EndsWith("`n")) { $content += "`n" }
    $utf8 = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($download, ($content + $hook), $utf8)
    Write-Host 'Restored Scoop download mirror hook' -ForegroundColor Cyan
    return $true
}

if ($RepairHook) {
    [void](Repair-ScoopMirrorAccelHook)
    return
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
        ActivePrefix = $active
        GithubHosts  = @($cfg.githubHosts)
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

    # Prefer active prefix, then other mirrors, then official.
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
    if (-not $cfg) { return 'official' }
    foreach ($p in $cfg.Prefixes) {
        if ($Url.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { return $p }
    }
    return 'official'
}

function Write-ScoopMirrorAccelUsed {
    param([string]$Url)

    $label = Get-ScoopMirrorAccelLabelFromUrl -Url $Url
    if ($script:ScoopMirrorAccelLastShown -eq $label) { return }
    $script:ScoopMirrorAccelLastShown = $label
    Write-Host "Scoop mirror: $label" -ForegroundColor Cyan
}

# aria2 / single-shot: pick candidate by attempt index (0 = active first)
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

# WebRequest path: active -> other mirrors -> official
if (Get-Command Start-Download -ErrorAction SilentlyContinue) {
    function Start-Download ($url, $to, $cookies) {
        # Match Scoop upstream quoting; parentheses required for PS parser.
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
                warn "Token might be misconfigured."
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

# aria2: retry with next mirror candidate on failure
if (Get-Command Invoke-CachedAria2Download -ErrorAction SilentlyContinue) {
    $script:ScoopMirrorOrigAria2Download = ${function:Invoke-CachedAria2Download}
    function Invoke-CachedAria2Download ($app, $version, $manifest, $architecture, $dir, $cookies = $null, $use_cache = $true, $check_hash = $true) {
        $urls = @(script:url $manifest $architecture)
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
                if ($urls.Count -gt 0) {
                    Write-ScoopMirrorAccelUsed -Url (ConvertTo-ScoopMirrorUrl $urls[0])
                }
                $script:ScoopMirrorAria2Attempt = 0
                return
            }
            catch {
                $lastError = $_
                if ($i -lt $maxAttempts - 1) {
                    Write-Host "aria2 failed, retry with next mirror ($($i + 2)/$maxAttempts)..." -ForegroundColor Yellow
                }
            }
        }

        $script:ScoopMirrorAria2Attempt = 0
        if ($lastError) { throw $lastError.Exception }
        throw "aria2 download failed for $app"
    }
}
