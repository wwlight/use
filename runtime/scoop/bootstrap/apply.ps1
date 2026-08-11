# Apply Scoop mirror / aria2 after install. Requires utils.ps1.

. (Join-Path $PSScriptRoot 'urls.ps1')
. (Join-Path $PSScriptRoot 'install.ps1')
. (Join-Path $PSScriptRoot 'git-convert.ps1')

# Opt-out: USE_SCOOP_ARIA2=0. Default follows manifest scoopAccel.aria2.
function Install-ScoopAria2 {
    param($Settings)

    $flag = "$env:USE_SCOOP_ARIA2".Trim().ToLowerInvariant()
    if ($flag -in @('0', 'false', 'no', 'off')) {
        Write-Detail 'Skipping aria2 (USE_SCOOP_ARIA2=0)' -Kind skip
        return
    }

    $aria = $Settings.aria2
    if (-not $aria) { return }

    if (-not (Get-Command aria2c -ErrorAction SilentlyContinue)) {
        Write-Detail 'Installing aria2...'
        Assert-ScoopWorktreeClean
        Invoke-QuietHost { scoop install aria2 }
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'aria2 installation failed; retry later. If the mirror does not support segmented downloads, run: scoop config aria2-enabled false'
            return
        }
    }

    Write-Detail 'Configuring aria2 multithreaded downloads...'
    Invoke-QuietHost {
        scoop config aria2-enabled $(if ($aria.enabled) { 'true' } else { 'false' }) *>$null
        scoop config aria2-warning-enabled $(if ($aria.warningEnabled) { 'true' } else { 'false' }) *>$null
        if ($null -ne $aria.retryWait) { scoop config aria2-retry-wait $aria.retryWait *>$null }
        if ($null -ne $aria.split) { scoop config aria2-split $aria.split *>$null }
        if ($null -ne $aria.maxConnectionPerServer) {
            scoop config aria2-max-connection-per-server $aria.maxConnectionPerServer *>$null
        }
        if ($null -ne $aria.minSplitSize) { scoop config aria2-min-split-size $aria.minSplitSize *>$null }
        if ($null -ne $aria.options) {
            if ([string]::IsNullOrWhiteSpace([string]$aria.options)) {
                scoop config rm aria2-options *>$null
            }
            else {
                scoop config aria2-options $aria.options *>$null
            }
        }
    }
    Write-Detail 'aria2 configuration complete' -Kind done
}

# Set scoop_repo for the ActivePrefix.
function Enable-ScoopMirror {
    param(
        $Manifest,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ActivePrefix
    )

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Scoop is not installed; mirror cannot be configured'
    }

    if (-not $env:SCOOP) {
        $env:SCOOP = (Read-Manifest).scoopDir
    }

    $settings = Get-ScoopMirrorSettings -Manifest $Manifest
    $prefixes = Get-ScoopMirrorPrefixes
    $ActivePrefix = Resolve-ScoopKnownMirrorPrefix -Prefix $ActivePrefix -Prefixes $prefixes

    $activeLabel = Format-ScoopMirrorActiveLabel -ActivePrefix $ActivePrefix
    $quiet = Test-ScoopQuietPm

    # Opt-in soft probe: USE_SCOOP_MIRROR_PROBE=1. Hook already falls back on download.
    $probeFlag = "$env:USE_SCOOP_MIRROR_PROBE".Trim().ToLowerInvariant()
    if (
        -not [string]::IsNullOrWhiteSpace($ActivePrefix) -and
        $probeFlag -in @('1', 'true', 'yes', 'on')
    ) {
        $probeTarget = [string]$settings.installScript
        if ([string]::IsNullOrWhiteSpace($probeTarget)) { $probeTarget = [string]$settings.scoopRepo }
        $probeUrl = Join-ScoopMirrorUrl -Url $probeTarget -Prefix $ActivePrefix -AllPrefixes $prefixes
        if (-not (Test-ScoopUrlReachable -Url $probeUrl)) {
            Write-Warn 'Selected mirror probe failed; downloads will fall back automatically'
        }
    }

    $apply = {
        $scoopRepo = Get-ScoopRepoTargetUrl -ActivePrefix $ActivePrefix -Settings $settings -Prefixes $prefixes
        Set-ScoopRepoConfig -Url $scoopRepo
    }
    if ($quiet) {
        # One-click wraps the full setup in a single spinner; avoid nested spin here.
        & $apply
    }
    else {
        Invoke-Spin "Applying Scoop mirror ($activeLabel) ..." $apply
        Write-StepSuccess "Scoop mirror ready ($activeLabel)"
    }
}
