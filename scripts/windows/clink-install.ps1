$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

Assert-TargetOs windows

$manifest = Read-Manifest

Write-Step '步骤1/4: 检查 scoop 安装...'
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-ErrorAndExit '未检测到 scoop 安装，请先安装 scoop'
}
Write-Info 'scoop 已安装'

Write-Step '步骤2/4: 检查 clink 安装...'
if (-not (Get-Command clink -ErrorAction SilentlyContinue)) {
    Write-Warn '未检测到 clink，正在通过 scoop 安装...'
    scoop install clink
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'clink 安装失败' }
    Write-Info 'clink 安装成功'
}
else {
    Write-Info 'clink 已安装，跳过'
}

$clinkPath = (scoop prefix clink).Trim()
if ([string]::IsNullOrWhiteSpace($clinkPath) -or -not (Test-Path $clinkPath)) {
    Write-ErrorAndExit '获取 clink 安装路径失败'
}

$scriptsPath = Join-Path $clinkPath 'scripts'
Write-Info 'Clink 安装路径:'
Write-Host $clinkPath

Write-Step '步骤3/4: 处理插件...'
foreach ($plugin in $manifest.clinkPlugins) {
    $targetPath = Join-Path $scriptsPath $plugin.name
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
        Write-Info "插件 $($plugin.name) 已存在，跳过"
    }
}

Write-Info '复制 starship.lua 启动插件...'
$starshipSrc = Join-Path $Script:ProjectRoot 'configs/windows/starship.lua'
Copy-Item $starshipSrc (Join-Path $scriptsPath 'starship.lua') -Force -Verbose

Write-Info "注册插件: $scriptsPath..."
clink installscripts $scriptsPath
if ($LASTEXITCODE -ne 0) {
    Write-Warn "$scriptsPath 注册失败"
}
else {
    Write-Info "$scriptsPath 注册成功"
}

Write-Step '步骤4/4: 启用 clink 自动运行...'
clink set tips.enable false
clink autorun install -- --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Warn 'clink 自动运行启用失败'
}
Write-Info 'clink 自动运行已启用'

Write-Info '🎉 所有配置已完成！'
