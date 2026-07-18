$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

Assert-TargetOs windows

$manifest = Read-Manifest

$workDir = Join-Path $env:USERPROFILE 'Desktop/git-extras'

Write-Step '步骤1/5: 克隆 git-extras 仓库到桌面...'
git clone $manifest.gitExtras.repo $workDir
if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '克隆 git-extras 仓库失败' }

Write-Step '步骤2/5: 进入 git-extras 目录...'
Set-Location $workDir

Write-Step '步骤3/5: 检出最新版本...'
$latestTag = git describe --tags (git rev-list --tags --max-count=1)
git checkout $latestTag
if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '检出最新标签失败' }
Write-Info "已检出版本: $latestTag"

Write-Step '步骤4/5: 正在安装 git-extras...'
$gitPath = (scoop prefix git).Trim()
if ([string]::IsNullOrWhiteSpace($gitPath)) {
    Write-ErrorAndExit '无法获取 Git 路径'
}

if (Test-Path './install.cmd') {
    cmd /c "install.cmd `"$gitPath`""
    if ($LASTEXITCODE -ne 0) {
        Write-Warn '安装命令执行可能不完全成功，请手动检查'
    }
}
else {
    Write-Warn '未找到 install.cmd 文件'
}

Write-Step '步骤5/5: 验证安装...'
git extras --help | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-ErrorAndExit 'git extras 命令验证失败，可能安装未成功'
}
Write-Info '安装验证成功'

Write-Info '清理临时文件...'
Set-Location (Join-Path $env:USERPROFILE 'Desktop')
Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Info '🎉 git-extras 安装完成!'
