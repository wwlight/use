$Repo = 'https://github.com/wwlight/use.git'
$InstallDir = "$env:USERPROFILE\Desktop\use"

function Write-Info  { Write-Host "[INFO] $args" -ForegroundColor Green }
function Write-Error { Write-Host "[ERROR] $args" -ForegroundColor Red; exit 1 }

# ---------- clone / update repo ----------
if (Test-Path "$InstallDir\.git") {
  Write-Info '仓库已存在，正在更新...'
  git -C $InstallDir pull --ff-only
} else {
  Write-Info "正在克隆仓库到 $InstallDir ..."
  git clone --depth=1 $Repo $InstallDir
}

Set-Location $InstallDir

# ---------- run original scripts ----------
Write-Info '步骤 1/2: 安装包管理器 ...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/scoop-install.ps1

Write-Info '步骤 2/2: 系统初始化 ...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1

Write-Info '安装完成！'
