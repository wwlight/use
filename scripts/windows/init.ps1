$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest

function Setup-Directories {
    Write-Info '步骤1/5: 正在创建目录结构...'
    foreach ($dir in $manifest.directories) {
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
    Write-Info '步骤2/5: 正在安装/恢复 scoop 应用...'
    $scoopBackup = Join-Path $Script:ProjectRoot $manifest.scoopBackup

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'scoop 未安装！请先运行: vpr pm'
    }

    if (Test-Path $scoopBackup) {
        scoop import $scoopBackup
        if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'scoop 应用恢复失败！' }
    }
    else {
        Write-ErrorAndExit "找不到 scoop 备份文件: $scoopBackup"
    }
}

function Install-Zsh {
    Write-Info '步骤3/5: 正在安装 zsh 及插件...'
    $zshScript = Join-Path $PSScriptRoot 'zsh-install.ps1'
    & $zshScript
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'zsh 安装失败' }
}

function Install-VitePlus {
    Write-Info '步骤4/5: 正在安装 vite.plus...'
    $vitePlusScript = Join-Path $ScriptDir 'common/vite-plus-install.ps1'
    & $vitePlusScript
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'vite.plus 安装失败' }
}

function Sync-Configurations {
    Write-Info '步骤5/5: 正在同步配置...'

    $configScript = Join-Path $PSScriptRoot 'config-sync.ps1'
    $baseScript = Join-Path $ScriptDir 'common/git-setup.ps1'

    if (Test-Path $configScript) {
        & $configScript 2
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

Setup-Directories
Install-OrRestoreScoop
Install-Zsh
Install-VitePlus
Sync-Configurations

Write-Info '🎉 所有操作完成！系统已准备就绪。'
