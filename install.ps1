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

function Normalize-RepoUrl {
  param([string]$Url)
  $u = $Url.TrimEnd('/')
  if ($u.EndsWith('.git')) { $u = $u.Substring(0, $u.Length - 4) }
  foreach ($prefix in @('https://', 'http://', 'ssh://git@', 'git@')) {
    if ($u.StartsWith($prefix)) {
      $u = $u.Substring($prefix.Length)
      break
    }
  }
  $u = $u -replace ':', '/'
  return $u
}

function Test-SameRemoteRepo {
  param([string]$Dir)
  $gitDir = Join-Path $Dir '.git'
  if (-not (Test-Path $gitDir)) { return $false }
  $remote = git -C $Dir remote get-url origin 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) { return $false }
  return (Normalize-RepoUrl $remote) -eq (Normalize-RepoUrl $Repo)
}

function Get-NextTimestampedDir {
  param([string]$Base)
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $target = "$Base-$ts"
  while (Test-Path $target) {
    Start-Sleep -Seconds 1
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $target = "$Base-$ts"
  }
  return $target
}

if (-not (Test-Path $InstallDir)) {
  Write-Info "正在克隆仓库到 $InstallDir ..."
  git clone --depth=1 $Repo $InstallDir
  if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '克隆仓库失败' }
}
elseif (Test-SameRemoteRepo $InstallDir) {
  Write-Info "检测到已有仓库 $InstallDir，正在强制同步到 origin/main ..."
  git -C $InstallDir fetch origin main
  if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '拉取远程失败' }
  git -C $InstallDir reset --hard origin/main
  if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '重置本地失败' }
}
else {
  $InstallDir = Get-NextTimestampedDir $InstallDir
  Write-Info "目录已占用，正在克隆到 $InstallDir ..."
  git clone --depth=1 $Repo $InstallDir
  if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '克隆仓库失败' }
}

Set-Location $InstallDir

Write-Step '步骤 1/2: 安装包管理器 ...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/scoop-install.ps1

Write-Step '步骤 2/2: 系统初始化 ...'
if ($InstallProfile) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1 $InstallProfile
} else {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1
}

Write-Info '安装完成！'
