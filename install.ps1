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
function Write-Step  { Write-Host "[INFO] $args" -ForegroundColor Blue }

# irm|iex 跑在当前 host：打印后 throw，由顶层 catch return，避免 exit 关掉会话、也避免未捕获堆栈
function Write-ErrorAndExit {
    Write-Host "[ERROR] $args" -ForegroundColor Red
    throw 'USE_FATAL'
}

function Complete-UseFatal {
    param($ErrorRecord)
    if ("$($ErrorRecord.Exception.Message)" -ne 'USE_FATAL') {
        Write-Host "[ERROR] $($ErrorRecord.Exception.Message)" -ForegroundColor Red
    }
    $global:LASTEXITCODE = 1
    # -File 调用时退出进程；iex 时仅终止脚本（仍带上退出码供调用方读取）
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) {
        exit 1
    }
}

# 返回值: macos / windows / linux / unknown
function Get-Os {
    if (($env:OS -eq 'Windows_NT') -or (($null -ne (Get-Variable IsWindows -ErrorAction SilentlyContinue)) -and $IsWindows)) {
        return 'windows'
    }
    if (($null -ne (Get-Variable IsMacOS -ErrorAction SilentlyContinue)) -and $IsMacOS) {
        return 'macos'
    }
    if (($null -ne (Get-Variable IsLinux -ErrorAction SilentlyContinue)) -and $IsLinux) {
        return 'linux'
    }

    $unameS = ''
    try { $unameS = (& uname -s 2>$null) } catch { }

    switch -Regex ($unameS) {
        '^Darwin$' { return 'macos' }
        '^(CYGWIN|MINGW|MSYS)' { return 'windows' }
        '^Linux$' { return 'linux' }
    }

    if ($env:OSTYPE -match '^(msys|cygwin)') { return 'windows' }
    if ($env:OSTYPE -match '^darwin') { return 'macos' }
    if ($env:OSTYPE -match '^linux') { return 'linux' }
    if ($env:WINDIR) { return 'windows' }

    return 'unknown'
}

if ($InstallProfile -match '^(-h|--help|help)$') {
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
    return
}

try {

$os = Get-Os
if ($os -ne 'windows') {
    Write-ErrorAndExit "检测到 $os。请改用: curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash"
}

# 切换控制台为 UTF-8 代码页，确保中文正常显示
& chcp 65001 > $null

switch -Regex ($InstallProfile) {
    '^(--)?lite$' { $InstallProfile = 'lite' }
    '^(--)?full$' { $InstallProfile = 'full' }
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
  Write-Info "检测到已有仓库 $InstallDir，正在同步到 origin/main ..."
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

$pwsh = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }

# 进度：入口完成第 1 步；init.ps1 内 LocalSteps=4，总数由其校正
$initSteps = 4
$env:USE_STEP_CHAIN = '1'
$env:USE_STEP_CURRENT = '1'
$env:USE_STEP_TOTAL = "$([int]$env:USE_STEP_CURRENT + $initSteps)"
Write-Step "步骤 $($env:USE_STEP_CURRENT)/$($env:USE_STEP_TOTAL): 安装包管理器 ..."

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Info 'scoop 已安装，跳过'
}
else {
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/windows/scoop-install.ps1
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '包管理器安装失败' }
}

$env:SYNC_INTERACTIVE = '1'

if ($InstallProfile) {
  & $pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1 $InstallProfile
} else {
  & $pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1
}
if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit '初始化失败' }

Write-Info '安装完成！'

} catch {
    Complete-UseFatal $_
}
