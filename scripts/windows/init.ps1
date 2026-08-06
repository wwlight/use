param(
    [Parameter(Position = 0)]
    [string]$InstallProfile = ''
)

# Switch the console to UTF-8.
& chcp 65001 > $null

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest
$ManifestConfig = Join-Path $ScriptDir 'lib/manifest-config.mjs'

function Show-InitUsage {
    & node $ManifestConfig usage-init
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Could not generate usage text' }
}

function Resolve-ScoopInstallProfile {
    param([string]$Arg)

    if ($Arg -in @('-h', '--help', 'help')) {
        Show-InitUsage
        exit 0
    }

    $profileName = $Arg
    if ($profileName -match '^--(.+)$') { $profileName = $Matches[1] }

    if ($profileName -ne '') {
        & node $ManifestConfig has-profile $profileName
        if ($LASTEXITCODE -ne 0) {
            Show-InitUsage
            Write-ErrorAndExit "Unknown argument: $Arg"
        }
        return $profileName
    }

    if (-not (Test-InteractivePrompt)) {
        Write-ErrorAndExit 'Pass an argument in non-interactive environments (example: vpr init -- lite)'
    }

    $menuLines = & node $ManifestConfig menu-profiles
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Could not read installation profile' }
    $menuArgs = @('Choose the Scoop installation profile') + @($menuLines | Where-Object { $_ })

    $menuScript = Join-Path $ScriptDir 'lib/menu-select.mjs'
    $outFile = [System.IO.Path]::GetTempFileName()
    try {
        $env:MENU_SELECT_OUT = $outFile
        # Do not capture stdout; preserve the TTY so the menu is visible in Cursor.
        & node $menuScript @menuArgs
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorAndExit 'Pass an argument in non-interactive environments (example: vpr init -- lite)'
        }
        $choice = (Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        $choice = "$choice".Trim()
    }
    finally {
        Remove-Item Env:MENU_SELECT_OUT -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    }
    if ([string]::IsNullOrWhiteSpace($choice)) {
        Write-ErrorAndExit 'Pass an argument in non-interactive environments (example: vpr init -- lite)'
    }
    & node $ManifestConfig has-profile $choice
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit "Invalid selection: $choice"
    }
    return $choice
}

function Setup-Directories {
    Write-NextStep 'Creating directory structure...'
    foreach ($dir in (Get-ManifestDirectories)) {
        $path = Get-ExpandedPath $dir
        try {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        catch {
            Write-Warn "Directory could not be created or already exists: $path"
        }
    }
}

function Install-OrRestoreScoop {
    param([string]$ScoopProfile)

    $label = & node $ManifestConfig profile-label $ScoopProfile
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit "Unknown profile: $ScoopProfile" }
    Write-NextStep "Installing/restoring Scoop apps (${label})..."

    $rel = & node $ManifestConfig profile-artifact windows $ScoopProfile
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rel)) {
        Write-ErrorAndExit "Could not resolve profile artifact: $ScoopProfile"
    }
    $scoopBackup = Join-Path $Script:ProjectRoot "$rel".Trim()

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Scoop is not installed. Run: vpr pm'
    }

    $gitInitiallyAvailable = [bool](Get-Command git.exe -ErrorAction SilentlyContinue)

    . (Join-Path $PSScriptRoot 'scoop\accel.ps1')
    # Reuse mirror from vpr pm; do not prompt again.
    $activePrefix = Get-ScoopMirrorActivePrefix
    Enable-ScoopAccel -Manifest $manifest -ActivePrefix $activePrefix

    if (Test-Path $scoopBackup) {
        Write-Info "Restoring dependencies from $(Split-Path $scoopBackup -Leaf)..."
        Assert-ScoopWorktreeClean
        $activePrefix = Get-ScoopMirrorActivePrefix
        $importFile = New-ScoopMirroredImportFile -BackupPath $scoopBackup -ActivePrefix $activePrefix
        try {
            if ($importFile -ne $scoopBackup) {
                Write-Info "Importing buckets via active mirror: $(Format-ScoopMirrorActiveLabel -ActivePrefix $activePrefix)"
            }
            scoop import $importFile
            if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Scoop app restore failed!' }
        }
        finally {
            if ($importFile -ne $scoopBackup -and (Test-Path -LiteralPath $importFile)) {
                Remove-Item -LiteralPath $importFile -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not $gitInitiallyAvailable) {
            # Git may have been installed by the import, so retry the hook/filter
            # setup that Enable-ScoopAccel had to defer.
            Install-ScoopDownloadHook
        }
    }
    else {
        Write-ErrorAndExit "Scoop backup file not found: $scoopBackup"
    }
}

function Install-Zsh {
    Write-NextStep 'Installing Zsh and plugins...'
    $zshScript = Join-Path $PSScriptRoot 'zsh-install.ps1'
    & $zshScript
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Zsh installation failed' }

    $pluginScript = Join-Path $ScriptDir 'common/zsh-plugins-install.ps1'
    & $pluginScript
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Zsh plugin installation failed' }
}

function Sync-Configurations {
    param([string]$ScoopProfile)

    Write-NextStep 'Syncing configuration...'

    $configScript = Join-Path $PSScriptRoot 'config-sync.ps1'
    $baseScript = Join-Path $ScriptDir 'common/git-setup.ps1'

    if (Test-Path $configScript) {
        $env:SYNC_SELECT_ALL = '1'
        $env:SYNC_PROFILE = $ScoopProfile
        & $configScript 2
        Remove-Item Env:SYNC_SELECT_ALL -ErrorAction SilentlyContinue
        Remove-Item Env:SYNC_PROFILE -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Configuration sync failed!' }
    }
    else {
        Write-ErrorAndExit "Configuration sync script not found: $configScript"
    }

    if (Test-Path $baseScript) {
        & $baseScript
        if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Base configuration initialization failed!' }
    }
    else {
        Write-Warn "Base configuration initialization script not found: $baseScript"
    }
}

Assert-TargetOs windows

$scoopProfile = Resolve-ScoopInstallProfile -Arg $InstallProfile

$InitStepCount = 4
Initialize-StepProgress $InitStepCount

Setup-Directories
Install-OrRestoreScoop -ScoopProfile $scoopProfile
Install-Zsh
Sync-Configurations -ScoopProfile $scoopProfile

Write-Info 'All operations complete. The system is ready.'
