# Windows-heavy Scoop bootstrap (install / hooks / git / aria2).
param(
    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$ActivePrefix,

    [ValidateSet('install', 'finish', 'all')]
    [string]$Phase = 'all'
)

. (Join-Path $PSScriptRoot 'utils.ps1')
. (Join-Path $PSScriptRoot 'apply.ps1')

Assert-TargetOs windows

$manifest = Read-Manifest
$settings = Get-ScoopMirrorSettings -Manifest $manifest
$prefixes = Get-ScoopMirrorPrefixes
$ActivePrefix = Resolve-ScoopKnownMirrorPrefix -Prefix $ActivePrefix -Prefixes $prefixes
$hostLabel = Format-ScoopMirrorHostLabel -ActivePrefix $ActivePrefix
$quiet = Test-ScoopQuietPm

function Install-ScoopIfMissing {
    param(
        $Manifest,
        $Settings,
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
        Invoke-ScoopInstallScriptWithFallback -Settings $Settings -PreferredPrefix $SelectedPrefix -OutPrefix ([ref]$installedPrefix)
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

    Write-Detail 'Scoop installation complete' -Kind done
}

function Complete-ScoopMirrorSetup {
    param(
        $Manifest,
        [string]$ActivePrefix,
        $Settings
    )
    # Requires ~/.config/scoop helpers already deployed.
    Enable-ScoopMirror -Manifest $Manifest -ActivePrefix $ActivePrefix
    $formalReady = Test-ScoopFormalRepairReady
    Install-ScoopDownloadHook
    Install-ScoopBootstrapApps
    Ensure-ScoopGitRepositories -ActivePrefix $ActivePrefix -Settings $Settings
    if (-not $formalReady) {
        Install-ScoopDownloadHook
    }
    Set-ScoopBucketMirrors -ActivePrefix $ActivePrefix
    Install-ScoopAria2 -Settings $Settings
}

$activeRef = [ref]$ActivePrefix
$hostRef = [ref]$hostLabel

if ($Phase -in @('install', 'all')) {
    # Phase=all: finish still needs ~/.config/scoop from a prior deploy (install → deploy → finish).
    if ($quiet -and $Phase -eq 'all') {
        Write-Step 'Configuring Scoop mirror'
        Write-StepSuccess "Setting up Scoop ($hostLabel) ..."
        # Keep inner Write-* helpers suppressed while the phase runs (was Invoke-Spin's job).
        $script:ScoopSpinActive = $true
        try {
            Install-ScoopIfMissing -Manifest $manifest -Settings $settings -SelectedPrefix $ActivePrefix -ActivePrefix $activeRef -HostLabel $hostRef
            Complete-ScoopMirrorSetup -Manifest $manifest -ActivePrefix $activeRef.Value -Settings $settings
        }
        finally {
            $script:ScoopSpinActive = $false
        }
        $ActivePrefix = $activeRef.Value
        if (-not [string]::IsNullOrWhiteSpace($env:USE_SCOOP_BOOTSTRAP_OUT)) {
            Set-Content -LiteralPath $env:USE_SCOOP_BOOTSTRAP_OUT -Value ("USE_SCOOP_ACTIVE_PREFIX=$ActivePrefix") -Encoding utf8
        }
        exit 0
    }

    Install-ScoopIfMissing -Manifest $manifest -Settings $settings -SelectedPrefix $ActivePrefix -ActivePrefix $activeRef -HostLabel $hostRef
    $ActivePrefix = $activeRef.Value
    $hostLabel = $hostRef.Value
}

if ($Phase -in @('finish', 'all')) {
    Complete-ScoopMirrorSetup -Manifest $manifest -ActivePrefix $ActivePrefix -Settings $settings
}

# Effective prefix for Node after install fallback (avoid stdout pollution).
if (-not [string]::IsNullOrWhiteSpace($env:USE_SCOOP_BOOTSTRAP_OUT)) {
    Set-Content -LiteralPath $env:USE_SCOOP_BOOTSTRAP_OUT -Value ("USE_SCOOP_ACTIVE_PREFIX=$ActivePrefix") -Encoding utf8
}
