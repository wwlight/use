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

$quiet = Test-ScoopQuietPm
$selectedPrefix = Resolve-ScoopMirrorSelection -Choice $Mirror
$activePrefix = $selectedPrefix
$hostLabel = Format-ScoopMirrorHostLabel -ActivePrefix $selectedPrefix

function Install-ScoopIfMissing {
    param(
        $Manifest,
        $Accel,
        [string]$SelectedPrefix,
        [ref]$ActivePrefix,
        [ref]$HostLabel
    )

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Detail 'Scoop is already installed' -Kind note
        if (-not $env:SCOOP) {
            $env:SCOOP = [string]$Manifest.scoopDir
        }
        return
    }

    Write-Detail 'Scoop is not installed; installing automatically...'

    $softwareAppsDir = Get-ExpandedPath $Manifest.softwareAppsDir
    if (-not (Test-Path $softwareAppsDir)) {
        New-Item -ItemType Directory -Path $softwareAppsDir -Force | Out-Null
    }

    $env:SCOOP = [string]$Manifest.scoopDir
    [Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')

    try {
        $ErrorActionPreference = 'Stop'
        $installedPrefix = ''
        Invoke-ScoopInstallScriptWithFallback -Accel $Accel -PreferredPrefix $SelectedPrefix -OutPrefix ([ref]$installedPrefix)
        $ActivePrefix.Value = Resolve-ScoopKnownMirrorPrefix -Prefix $installedPrefix
        $HostLabel.Value = Format-ScoopMirrorHostLabel -ActivePrefix $ActivePrefix.Value
        $mirrorChanged = [string]$ActivePrefix.Value -ne [string]$SelectedPrefix -and -not (
            [string]::IsNullOrWhiteSpace($ActivePrefix.Value) -and
            [string]::IsNullOrWhiteSpace($SelectedPrefix)
        )
        if ($mirrorChanged) {
            Write-Warn (
                "Selected mirror was $(Format-ScoopMirrorActiveLabel -ActivePrefix $SelectedPrefix); " +
                "active mirror is $(Format-ScoopMirrorActiveLabel -ActivePrefix $ActivePrefix.Value) after install fallback"
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

    Write-Detail 'Scoop installation complete' -Kind success
}

function Complete-ScoopAccelSetup {
    param(
        $Manifest,
        [string]$ActivePrefix,
        $Accel
    )
    Enable-ScoopAccel -Manifest $Manifest -ActivePrefix $ActivePrefix
    $formalReady = Test-ScoopFormalRepairReady
    Install-ScoopDownloadHook
    Install-ScoopBootstrapApps
    Ensure-ScoopGitRepositories -ActivePrefix $ActivePrefix -Accel $Accel
    if (-not $formalReady) {
        Install-ScoopDownloadHook
    }
    Set-ScoopBucketMirrors -ActivePrefix $ActivePrefix
    Install-ScoopAria2Accel -Accel $Accel
}

if ($quiet) {
    Write-Step 'Configuring Scoop acceleration'
    Invoke-Spin "Setting up Scoop ($hostLabel) ..." {
        Install-ScoopIfMissing -Manifest $manifest -Accel $accel -SelectedPrefix $selectedPrefix -ActivePrefix ([ref]$activePrefix) -HostLabel ([ref]$hostLabel)
        Complete-ScoopAccelSetup -Manifest $manifest -ActivePrefix $activePrefix -Accel $accel
    } -Done { "Scoop ready ($hostLabel)" }
}
else {
    Write-Info "Selected mirror: $(Format-ScoopMirrorActiveLabel -ActivePrefix $selectedPrefix)"
    Install-ScoopIfMissing -Manifest $manifest -Accel $accel -SelectedPrefix $selectedPrefix -ActivePrefix ([ref]$activePrefix) -HostLabel ([ref]$hostLabel)
    Complete-ScoopAccelSetup -Manifest $manifest -ActivePrefix $activePrefix -Accel $accel
}
