# Scoop mirror helper.
# Deployed to $env:SCOOP\config\scoop-mirror\hook.ps1 and sourced from download.ps1.
# Download hot path only; CLI lives in manage.ps1.
# Repair/preflight: node cli.mjs repair
# Fallback: powershell -NoProfile -File hook.ps1 -RepairHook
# Interactive: scoop mirror → manage.ps1

param(
    [switch]$RepairHook,
    [switch]$PrepareCommand,
    [switch]$GitFilterClean,
    [switch]$GitFilterSmudge
)

$script:ScoopMirrorRoot = if ($env:SCOOP) { Join-Path $env:SCOOP 'config\scoop-mirror' } else { $PSScriptRoot }
$script:ScoopMirrorHookBegin = [Text.Encoding]::UTF8.GetBytes('# >>> scoop-mirror')
$script:ScoopMirrorHookEnd = [Text.Encoding]::UTF8.GetBytes('# <<< scoop-mirror')
$script:ScoopMirrorHook = [Text.Encoding]::UTF8.GetBytes("`n# >>> scoop-mirror`n. `"`$env:SCOOP\config\scoop-mirror\hook.ps1`"`n# <<< scoop-mirror`n")
$script:ScoopMirrorLegacyHookBegin = [Text.Encoding]::UTF8.GetBytes('# >>> scoop-mirror-accel')
$script:ScoopMirrorLegacyHookEnd = [Text.Encoding]::UTF8.GetBytes('# <<< scoop-mirror-accel')

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
    $current = $Bytes
    foreach ($pair in @(
        @{ Begin = $script:ScoopMirrorLegacyHookBegin; End = $script:ScoopMirrorLegacyHookEnd },
        @{ Begin = $script:ScoopMirrorHookBegin; End = $script:ScoopMirrorHookEnd }
    )) {
        $begin = Find-ByteSequence -Bytes $current -Sequence $pair.Begin
        if ($begin -lt 0) { continue }
        $end = Find-ByteSequence -Bytes $current -Sequence $pair.End -Start $begin
        if ($end -lt 0) { throw 'Incomplete Scoop mirror acceleration markers' }

        $start = $begin
        if ($start -gt 0 -and $current[$start - 1] -eq 10) {
            $start--
            if ($start -gt 0 -and $current[$start - 1] -eq 13) { $start-- }
        }
        $end += $pair.End.Length
        if ($end -lt $current.Length -and $current[$end] -eq 13) { $end++ }
        if ($end -lt $current.Length -and $current[$end] -eq 10) { $end++ }

        $output = New-Object byte[] ($current.Length - ($end - $start))
        if ($start -gt 0) { [Array]::Copy($current, 0, $output, 0, $start) }
        if ($end -lt $current.Length) { [Array]::Copy($current, $end, $output, $start, $current.Length - $end) }
        $current = $output
    }
    return ,$current
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

function Get-ScoopMirrorAccelFilterCommand {
    param([string]$HelperPath)

    $cliJs = Join-Path (Split-Path -Parent $HelperPath) 'cli.mjs'
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($node -and (Test-Path -LiteralPath $cliJs)) {
        # Prefer Node: powershell.exe filter cold-starts often cost 5-15s per Git invoke.
        $nodePath = $node.Source.Replace('\', '/')
        $jsPath = $cliJs.Replace('\', '/')
        return [pscustomobject]@{
            Clean  = "`"$nodePath`" `"$jsPath`" clean"
            Smudge = "`"$nodePath`" `"$jsPath`" smudge"
        }
    }

    # Fallback when Node is unavailable.
    $filterPath = $HelperPath.Replace('\', '/').Replace("'", "'\''")
    $filterBase = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$filterPath'"
    return [pscustomobject]@{
        Clean  = "$filterBase -GitFilterClean"
        Smudge = "$filterBase -GitFilterSmudge"
    }
}

function Test-ScoopMirrorCurrentHookMarkers {
    param([byte[]]$Bytes)

    $searchFrom = 0
    while ($true) {
        $begin = Find-ByteSequence -Bytes $Bytes -Sequence $script:ScoopMirrorHookBegin -Start $searchFrom
        if ($begin -lt 0) { return $false }
        $afterBegin = $begin + $script:ScoopMirrorHookBegin.Length
        # Reject legacy `# >>> scoop-mirror-accel` (prefix of current begin marker).
        if ($afterBegin -lt $Bytes.Length -and $Bytes[$afterBegin] -ne 10 -and $Bytes[$afterBegin] -ne 13) {
            $searchFrom = $afterBegin
            continue
        }

        $end = Find-ByteSequence -Bytes $Bytes -Sequence $script:ScoopMirrorHookEnd -Start $afterBegin
        if ($end -lt 0) { return $false }
        $afterEnd = $end + $script:ScoopMirrorHookEnd.Length
        if ($afterEnd -lt $Bytes.Length -and $Bytes[$afterEnd] -ne 10 -and $Bytes[$afterEnd] -ne 13) {
            $searchFrom = $afterBegin
            continue
        }

        $sliceLen = ($end + $script:ScoopMirrorHookEnd.Length) - $begin
        $slice = [Text.Encoding]::UTF8.GetString($Bytes, $begin, $sliceLen)
        return ($slice -match 'scoop-mirror[/\\]hook\.ps1')
    }
}

function Test-ScoopMirrorRepairHealthy {
    param(
        [string]$ScoopRepo,
        [string]$Download,
        [string]$Clean,
        [string]$Smudge
    )

    if (-not (Test-Path -LiteralPath $Download)) { return $false }
    $bytes = [IO.File]::ReadAllBytes($Download)
    if (-not (Test-ScoopMirrorCurrentHookMarkers -Bytes $bytes)) { return $false }

    $cleanCfg = "$(& git.exe -C $ScoopRepo config --local --get filter.scoop-mirror.clean 2>$null)".Trim()
    if ($LASTEXITCODE -ne 0 -or $cleanCfg -cne $Clean) { return $false }
    $smudgeCfg = "$(& git.exe -C $ScoopRepo config --local --get filter.scoop-mirror.smudge 2>$null)".Trim()
    if ($LASTEXITCODE -ne 0 -or $smudgeCfg -cne $Smudge) { return $false }
    $required = "$(& git.exe -C $ScoopRepo config --local --get filter.scoop-mirror.required 2>$null)".Trim()
    if ($LASTEXITCODE -ne 0 -or $required -cne 'true') { return $false }

    $attributes = Join-Path $ScoopRepo '.git\info\attributes'
    if (-not (Test-Path -LiteralPath $attributes)) { return $false }
    $attrOk = $false
    foreach ($line in @(Get-Content -LiteralPath $attributes -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*lib/download\.ps1\s+.*filter=scoop-mirror\b' -and $line -notmatch 'filter=scoop-mirror-accel\b') {
            $attrOk = $true
            break
        }
    }
    if (-not $attrOk) { return $false }

    $dirty = @(& git.exe -C $ScoopRepo status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0) { return $false }
    return ($dirty.Count -eq 0)
}

function Initialize-ScoopMirrorAccelFilter {
    if ([string]::IsNullOrWhiteSpace($env:SCOOP)) { throw 'SCOOP environment variable is not set' }

    $helper = Join-Path $env:SCOOP 'config\scoop-mirror\hook.ps1'
    $cliJs = Join-Path $env:SCOOP 'config\scoop-mirror\cli.mjs'
    if (-not (Test-Path -LiteralPath $helper)) { throw "Scoop mirror hook not found: $helper" }

    # Prefer the Node repair path: avoids powershell.exe cold starts (often 5-15s each).
    # Node repair owns the fast-path + full rewrite; PS below is no-Node fallback only.
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($node -and (Test-Path -LiteralPath $cliJs)) {
        $output = & $node.Source $cliJs repair 2>&1
        if ($LASTEXITCODE -ne 0) {
            $detail = ($output | Out-String).Trim()
            if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'scoop-mirror cli repair failed' }
            throw $detail
        }
        return
    }

    $scoopRepo = Join-Path $env:SCOOP 'apps\scoop\current'
    $download = Join-Path $scoopRepo 'lib\download.ps1'
    if (-not (Test-Path -LiteralPath (Join-Path $scoopRepo '.git'))) { throw "Scoop Git repository not found: $scoopRepo" }
    if (-not (Test-Path -LiteralPath $download)) { throw "Scoop download.ps1 not found: $download" }

    $filter = Get-ScoopMirrorAccelFilterCommand -HelperPath $helper
    if (Test-ScoopMirrorRepairHealthy -ScoopRepo $scoopRepo -Download $download -Clean $filter.Clean -Smudge $filter.Smudge) {
        return
    }

    & git.exe -C $scoopRepo config --local filter.scoop-mirror.clean $filter.Clean
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure the Scoop mirror clean filter' }
    & git.exe -C $scoopRepo config --local filter.scoop-mirror.smudge $filter.Smudge
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure the Scoop mirror smudge filter' }
    & git.exe -C $scoopRepo config --local filter.scoop-mirror.required true
    if ($LASTEXITCODE -ne 0) { throw 'Could not require the Scoop mirror Git filter' }

    $attributes = Join-Path $scoopRepo '.git\info\attributes'
    $attributeLine = 'lib/download.ps1 filter=scoop-mirror -text'
    $attributeContent = if (Test-Path -LiteralPath $attributes) {
        @((Get-Content -LiteralPath $attributes -Encoding UTF8) | Where-Object { $_ -notmatch '^\s*lib/download\.ps1\s+.*filter=scoop-mirror(-accel)?' })
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
        $global:LASTEXITCODE = 0
        if ($env:SCOOP_SHELL_INPROCESS -eq '1') { return }
        exit 0
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        $global:LASTEXITCODE = 1
        if ($env:SCOOP_SHELL_INPROCESS -eq '1') { return }
        exit 1
    }
}

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
