param(
    [Parameter(Position = 0)]
    [string]$Mirror = ''
)

. (Join-Path $PSScriptRoot 'utils.ps1')
. (Join-Path $PSScriptRoot 'accel.ps1')

Assert-TargetOs windows

while ($Mirror -eq '--') {
    if ($args.Count -gt 0) {
        $Mirror = [string]$args[0]
        $args = @($args | Select-Object -Skip 1)
    }
    else {
        $Mirror = ''
        break
    }
}
if ($Mirror -match '^--(.+)$') { $Mirror = $Matches[1] }

$manifest = Read-Manifest
$scoopDir = $manifest.scoopDir
$accel = Get-ScoopAccelConfig -Manifest $manifest

if ($Mirror -in @('-h', '--help', 'help')) {
    Show-ScoopMirrorUsage
    exit 0
}

$selectedPrefix = Resolve-ScoopMirrorSelection -Choice $Mirror
Write-Info "Selected mirror: $(Format-ScoopMirrorActiveLabel -ActivePrefix $selectedPrefix)"
$activePrefix = $selectedPrefix

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Info 'Scoop is not installed; installing automatically...'

    $softwareAppsDir = Get-ExpandedPath $manifest.softwareAppsDir
    if (-not (Test-Path $softwareAppsDir)) {
        New-Item -ItemType Directory -Path $softwareAppsDir -Force | Out-Null
    }

    $env:SCOOP = $scoopDir
    [Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')

    try {
        $ErrorActionPreference = 'Stop'
        # Use the mirror that actually installed Scoop (preferred → fallback → official).
        # OutPrefix avoids installer Write-Output joining into ActivePrefix/scoop_repo.
        $installedPrefix = ''
        Invoke-ScoopInstallScriptWithFallback -Accel $accel -PreferredPrefix $selectedPrefix -OutPrefix ([ref]$installedPrefix)
        $activePrefix = Resolve-ScoopKnownMirrorPrefix -Prefix $installedPrefix
        # Keep binary operators at end of line — PowerShell does not continue across bare newlines.
        $mirrorChanged = [string]$activePrefix -ne [string]$selectedPrefix -and -not (
            [string]::IsNullOrWhiteSpace($activePrefix) -and
            [string]::IsNullOrWhiteSpace($selectedPrefix)
        )
        if ($mirrorChanged) {
            Write-Warn (
                "Selected mirror was $(Format-ScoopMirrorActiveLabel -ActivePrefix $selectedPrefix); " +
                "active mirror is $(Format-ScoopMirrorActiveLabel -ActivePrefix $activePrefix) after install fallback"
            )
        }
    }
    catch {
        Write-ErrorAndExit "Scoop installation failed: $($_.Exception.Message)"
    }

    Update-ScoopSessionPath

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Scoop is still unavailable in this session; open a new terminal and rerun the installer'
    }

    Write-Success 'Scoop installation complete'
}
else {
    Write-Note 'Scoop is already installed'
    if (-not $env:SCOOP) {
        $env:SCOOP = $scoopDir
    }
}

# Deploy scoop-mirror files + scoop_repo only.
Enable-ScoopAccel -Manifest $manifest -ActivePrefix $activePrefix

# Zip Scoop / no Git → temporary download hook for 7zip/git; formal repair after scoop update.
$formalReady = Test-ScoopFormalRepairReady
Install-ScoopDownloadHook
Install-ScoopBootstrapApps
Ensure-ScoopGitRepositories -ActivePrefix $activePrefix -Accel $accel
if (-not $formalReady) {
    Install-ScoopDownloadHook
}

Set-ScoopBucketMirrors -ActivePrefix $activePrefix
Install-ScoopAria2Accel -Accel $accel
