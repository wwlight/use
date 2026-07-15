param(
    [Parameter(Position = 0)]
    [string]$InstallProfile
)

if ([string]::IsNullOrWhiteSpace($InstallProfile)) {
    $InstallProfile = $env:USE_PROFILE
}

$Repo = 'https://github.com/wwlight/use.git'
$InstallDir = "$env:USERPROFILE\Desktop\use"

function Write-Info  { Write-Host "[INFO] $args" -ForegroundColor Green }
function Write-Step  { Write-Host "[INFO] $args" -ForegroundColor Magenta }
function Write-ErrorAndExit { Write-Host "[ERROR] $args" -ForegroundColor Red; exit 1 }

switch -Regex ($InstallProfile) {
    '^(--)?lite$' { $InstallProfile = 'lite' }
    '^(--)?full$' { $InstallProfile = 'full' }
    '^(-h|--help|help)$' {
        Write-Host @'
用法: install.ps1 [lite|full]

  lite  尝鲜版
  full  完整版
  （省略则初始化时交互选择）

示例:
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  irm <url> | iex
  $env:USE_PROFILE='lite'; irm <url> | iex
'@
        exit 0
    }
    '^$' { }
    default { Write-ErrorAndExit "未知参数: $InstallProfile（使用 lite / full）" }
}

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
Write-Step '步骤 1/2: 安装包管理器 ...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/scoop-install.ps1

Write-Step '步骤 2/2: 系统初始化 ...'
if ($InstallProfile) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1 $InstallProfile
} else {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1
}

Write-Info '安装完成！'
