# Scoop download hook: rewrite URLs and aria2 retries for the active mirror.
# Repair / git filter live in cli.mjs (Node).

$shared = Join-Path $PSScriptRoot 'shared.ps1'
if (-not (Test-Path -LiteralPath $shared)) {
    throw "Scoop mirror shared helper not found: $shared"
}
. $shared

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

if (Get-Command Start-Download -ErrorAction SilentlyContinue) {
    function Start-Download ($url, $to, $cookies) {
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
