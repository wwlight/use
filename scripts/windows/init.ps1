param(
    [Parameter(Position = 0)]
    [string]$InstallProfile = ''
)

# 切换控制台为 UTF-8 代码页，确保中文正常显示
& chcp 65001 > $null

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest
$ManifestConfig = Join-Path $ScriptDir 'lib/manifest-config.mjs'

function Show-InitUsage {
    & node $ManifestConfig usage-init
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '无法生成用法说明' }
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
            Write-ErrorAndExit "未知参数: $Arg"
        }
        return $profileName
    }

    if (-not (Test-InteractivePrompt)) {
        Write-ErrorAndExit '非交互环境请传入参数（示例: vpr init -- lite）'
    }

    $menuLines = & node $ManifestConfig menu-profiles
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '无法读取安装档位' }
    $menuArgs = @('请选择 Scoop 安装范围') + @($menuLines | Where-Object { $_ })

    $menuScript = Join-Path $ScriptDir 'lib/menu-select.mjs'
    $choice = & node $menuScript @menuArgs
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($choice)) {
        Write-ErrorAndExit '非交互环境请传入参数（示例: vpr init -- lite）'
    }

    $choice = "$choice".Trim()
    & node $ManifestConfig has-profile $choice
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit "无效选择: $choice"
    }
    return $choice
}

function Setup-Directories {
    Write-NextStep '正在创建目录结构...'
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

    $label = & node $ManifestConfig profile-label $ScoopProfile
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit "未知 profile: $ScoopProfile" }
    Write-NextStep "正在安装/恢复 scoop 应用（${label}）..."

    $rel = & node $ManifestConfig profile-artifact windows $ScoopProfile
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rel)) {
        Write-ErrorAndExit "无法解析 profile 产物: $ScoopProfile"
    }
    $scoopBackup = Join-Path $Script:ProjectRoot "$rel".Trim()

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
    Write-NextStep '正在安装 zsh 及插件...'
    $zshScript = Join-Path $PSScriptRoot 'zsh-install.ps1'
    & $zshScript
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'zsh 安装失败' }

    $pluginScript = Join-Path $ScriptDir 'common/zsh-plugins-install.ps1'
    & $pluginScript
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'zsh 插件安装失败' }
}

function Sync-Configurations {
    param([string]$ScoopProfile)

    Write-NextStep '正在同步配置...'

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

Assert-TargetOs windows

$scoopProfile = Resolve-ScoopInstallProfile -Arg $InstallProfile

$InitStepCount = 4
Initialize-StepProgress $InitStepCount

Setup-Directories
Install-OrRestoreScoop -ScoopProfile $scoopProfile
Install-Zsh
Sync-Configurations -ScoopProfile $scoopProfile

Write-Info '所有操作完成！系统已准备就绪。'
