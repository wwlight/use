param(
    [Parameter(Position = 0)]
    [string]$InstallProfile = ''
)

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest

function Show-InitUsage {
    Write-Host @'
用法: init.ps1 [lite|full]

  lite  尝鲜版
  full  完整版

示例:
  vpr init
  vpr init -- lite
  vpr init -- full
'@
}

function Resolve-ScoopInstallProfile {
    param([string]$Arg)

    switch ($Arg) {
        { $_ -in @('full', '--full') } { return 'full' }
        { $_ -in @('lite', '--lite') } { return 'lite' }
        { $_ -in @('-h', '--help', 'help') } {
            Show-InitUsage
            exit 0
        }
        '' { }
        default {
            Show-InitUsage
            Write-ErrorAndExit "未知参数: $Arg"
        }
    }

    Write-Host '请选择 Scoop 安装范围:'
    Write-Host '1) 尝鲜版'
    Write-Host '2) 完整版'

    if (-not (Test-InteractivePrompt)) {
        Write-ErrorAndExit '非交互环境请传入参数: lite 或 full（示例: vpr init -- lite）'
    }

    $choice = Read-Host
    switch ($choice) {
        { $_ -in @('1', 'lite') } { return 'lite' }
        { $_ -in @('2', 'full') } { return 'full' }
        default { Write-ErrorAndExit "无效选择: $choice（请使用 1/lite 或 2/full）" }
    }
}

function Setup-Directories {
    Write-Step '步骤1/4: 正在创建目录结构...'
    foreach ($dir in (Get-ManifestDirectories)) {
        $path = Get-ExpandedPath $dir
        try {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        catch {
            Write-Warn "目录创建失败或已存在: $path"
        }
    }
}

function Install-OrRestoreScoop {
    param([string]$ScoopProfile)

    $label = if ($ScoopProfile -eq 'lite') { '尝鲜版' } else { '完整版' }
    Write-Step "步骤2/4: 正在安装/恢复 scoop 应用（${label}）..."
    $backupKey = if ($ScoopProfile -eq 'lite') { 'scoopBackupLite' } else { 'scoopBackup' }
    $scoopBackup = Join-Path $Script:ProjectRoot $manifest.$backupKey

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'scoop 未安装！请先运行: vpr pm'
    }

    if (Test-Path $scoopBackup) {
        Write-Info "正在从 $(Split-Path $scoopBackup -Leaf) 恢复依赖..."
        scoop import $scoopBackup
        if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'scoop 应用恢复失败！' }
    }
    else {
        Write-ErrorAndExit "找不到 scoop 备份文件: $scoopBackup"
    }
}

function Install-Zsh {
    Write-Step '步骤3/4: 正在安装 zsh 及插件...'
    $zshScript = Join-Path $PSScriptRoot 'zsh-install.ps1'
    & $zshScript
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'zsh 安装失败' }
}

function Sync-Configurations {
    param([string]$ScoopProfile)

    Write-Step '步骤4/4: 正在同步配置...'

    $configScript = Join-Path $PSScriptRoot 'config-sync.ps1'
    $baseScript = Join-Path $ScriptDir 'common/git-setup.ps1'

    if (Test-Path $configScript) {
        $env:SYNC_SELECT_ALL = '1'
        $env:SYNC_PROFILE = $ScoopProfile
        & $configScript 2
        Remove-Item Env:SYNC_SELECT_ALL -ErrorAction SilentlyContinue
        Remove-Item Env:SYNC_PROFILE -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '同步配置失败！' }
    }
    else {
        Write-ErrorAndExit "找不到配置同步脚本: $configScript"
    }

    if (Test-Path $baseScript) {
        & $baseScript
        if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '基础配置初始化失败！' }
    }
    else {
        Write-Warn "找不到基础配置初始化脚本: $baseScript"
    }
}

Write-Info '===== Windows 系统配置脚本 ====='

$scoopProfile = Resolve-ScoopInstallProfile -Arg $InstallProfile

Setup-Directories
Install-OrRestoreScoop -ScoopProfile $scoopProfile
Install-Zsh
Sync-Configurations -ScoopProfile $scoopProfile

Write-Info '🎉 所有操作完成！系统已准备就绪。'
