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
    Write-Info '步骤2/5: 正在安装/恢复 Scoop 应用...'
    $scoopBackup = Join-Path $Script:ProjectRoot $manifest.scoopBackup

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Scoop 未安装！请先运行: npm run win:scoop / vpr win:scoop'
    }

    if (Test-Path $scoopBackup) {
        scoop import $scoopBackup
        if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Scoop 应用恢复失败！' }
    }
    else {
        Write-ErrorAndExit "找不到 Scoop 备份文件: $scoopBackup"
    }
}

function Install-ZshPlugins {
    Write-Info '步骤3/5: 正在安装 zsh 插件...'
    $pluginsDir = Get-ExpandedPath '~/.zsh/plugins'

    foreach ($plugin in $manifest.zshPlugins) {
        $targetPath = Join-Path $pluginsDir $plugin.name
        if (-not (Test-Path $targetPath)) {
            Write-Info "正在下载插件: $($plugin.name)..."
            try {
                git clone $plugin.repo $targetPath
                Write-Info "$($plugin.name) 下载完成"
            }
            catch {
                Write-Warn "$($plugin.name) 下载失败，跳过此插件"
            }
        }
        else {
            Write-Info "插件 $($plugin.name) 已存在，跳过下载"
        }
    }
}

function Install-VitePlus {
    Write-Info '步骤4/5: 正在安装 vite.plus...'

    if (-not (Get-Command vp -ErrorAction SilentlyContinue)) {
        $ErrorActionPreference = 'Stop'
        irm https://vite.plus/ps1 | iex
        Write-Info 'vite.plus 安装成功'
    }
}

function Sync-Configurations {
    Write-Info '步骤5/5: 正在同步配置...'

    $configScript = Join-Path $PSScriptRoot 'config-sync.ps1'
    $commonScript = Join-Path $ScriptDir 'common/config-sync.ps1'
    $baseScript = Join-Path $ScriptDir 'common/git-setup.ps1'

    if (Test-Path $configScript) {
        & $configScript 2
        if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '同步配置失败！' }
    }
    else {
        Write-ErrorAndExit "找不到配置同步脚本: $configScript"
    }

    if (Test-Path $commonScript) {
        & $commonScript 2
        if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '同步公共配置失败！' }
    }
    else {
        Write-Warn "找不到公共同步脚本: $commonScript"
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
Install-ZshPlugins
Install-VitePlus
Sync-Configurations

Write-Info '🎉 所有操作完成！系统已准备就绪。'
