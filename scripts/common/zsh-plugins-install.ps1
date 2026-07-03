$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest -Scope common

Write-Info '正在安装 zsh 插件...'
$pluginsDir = Get-ExpandedPath '~/.zsh/plugins'
if (-not (Test-Path $pluginsDir)) {
    New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
}

foreach ($plugin in $manifest.zshPlugins) {
    $targetPath = Join-Path $pluginsDir $plugin.name
    if (-not (Test-Path $targetPath -PathType Container)) {
        Write-Info "正在下载插件: $($plugin.name)..."
        try {
            git clone $plugin.repo $targetPath
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "$($plugin.name) 下载失败，跳过此插件"
                continue
            }
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
