param(
    [Parameter(Position = 0)]
    [string]$InstallProfile
)

if ([string]::IsNullOrWhiteSpace($InstallProfile)) {
    $InstallProfile = $env:USE_PROFILE
}

$Repo = 'https://github.com/wwlight/use.git'
$InstallDir = "$env:USERPROFILE\Desktop\use"
# BEGIN GENERATED GITHUB ACCEL
$GithubAccelPrefixes = @(
    'https://ghfast.top/',
    'https://gh-proxy.com/'
)
# END GENERATED GITHUB ACCEL

function Write-Info  { Write-Host "[INFO] $args" -ForegroundColor Green }
function Write-Step  { Write-Host "[INFO] $args" -ForegroundColor Blue }

# irm|iex runs in the current host. Throw and catch at the top level to avoid closing the session.
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
    # Exit the process for -File; under iex, stop only the script and retain the exit code.
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) {
        exit 1
    }
}

# Returns macos, windows, linux, or unknown.
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
Usage: install.ps1 [lite|full]

  lite  Lite setup
  full  Full setup
  (omit to choose interactively during initialization)

Examples:
  irm <url> | iex
  $env:USE_PROFILE='lite'; irm <url> | iex
  $env:USE_PROFILE='full'; irm <url> | iex
'@
    return
}

try {

$os = Get-Os
if ($os -ne 'windows') {
    Write-ErrorAndExit "$os detected. Use: curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash"
}

# Switch the console to UTF-8.
& chcp 65001 > $null

switch -Regex ($InstallProfile) {
    '^(--)?lite$' { $InstallProfile = 'lite' }
    '^(--)?full$' { $InstallProfile = 'full' }
    '^$' { }
    default { Write-ErrorAndExit "Unknown argument: $InstallProfile (use lite or full)" }
}

# Normalize Git remotes for repository comparison.
function Remove-GithubAccelPrefix {
  param([string]$Url)
  foreach ($prefix in $GithubAccelPrefixes) {
    if ($Url.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
      return $Url.Substring($prefix.Length)
    }
  }
  return $Url
}

function Normalize-RepoUrl {
  param([string]$Url)
  $u = Remove-GithubAccelPrefix $Url
  while ($u.EndsWith('/')) { $u = $u.TrimEnd('/') }
  if ($u.EndsWith('.git')) { $u = $u.Substring(0, $u.Length - 4) }
  foreach ($prefix in @('https://', 'http://', 'ssh://git@', 'git@')) {
    if ($u.StartsWith($prefix)) {
      $u = $u.Substring($prefix.Length)
      break
    }
  }
  return ($u -replace ':', '/')
}

function Test-SameRemoteRepo {
  param([string]$Dir)
  $gitDir = Join-Path $Dir '.git'
  if (-not (Test-Path $gitDir)) { return $false }
  $remote = git -C $Dir remote get-url origin 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) { return $false }
  return (Normalize-RepoUrl $remote) -eq (Normalize-RepoUrl $Repo)
}

function Get-GithubRepoCandidates {
  foreach ($prefix in $GithubAccelPrefixes) {
    "$prefix$Repo"
  }
  $Repo
}

function Copy-UseRepository {
  param([string]$Target)

  foreach ($url in (Get-GithubRepoCandidates)) {
    Remove-Item $Target -Recurse -Force -ErrorAction SilentlyContinue
    Write-Info "Trying clone URL: $url"
    git clone --depth=1 $url $Target
    if ($LASTEXITCODE -eq 0) { return }
  }
  Write-ErrorAndExit 'Failed to clone repository'
}

function Update-UseRepository {
  param([string]$Target)

  foreach ($url in (Get-GithubRepoCandidates)) {
    git -C $Target remote set-url origin $url
    if ($LASTEXITCODE -ne 0) { continue }
    Write-Info "Trying sync URL: $url"
    git -C $Target fetch origin main
    if ($LASTEXITCODE -eq 0) {
      git -C $Target reset --hard origin/main
      if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Failed to reset local repository' }
      return
    }
  }
  Write-ErrorAndExit 'Failed to fetch remote repository'
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
  Write-Info "Cloning repository to $InstallDir ..."
  Copy-UseRepository $InstallDir
}
elseif (Test-SameRemoteRepo $InstallDir) {
  Write-Info "Existing repository found at $InstallDir; syncing with origin/main ..."
  Update-UseRepository $InstallDir
}
else {
  $InstallDir = Get-NextTimestampedDir $InstallDir
  Write-Info "Directory is in use; cloning to $InstallDir ..."
  Copy-UseRepository $InstallDir
}

Set-Location $InstallDir

$pwsh = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }

# The installer completes step 1; the total includes subsequent init steps.
$initSteps = 4
$env:USE_STEP_CHAIN = '1'
$env:USE_STEP_CURRENT = '1'
$env:USE_STEP_TOTAL = "$([int]$env:USE_STEP_CURRENT + $initSteps)"
Write-Step "Step $($env:USE_STEP_CURRENT)/$($env:USE_STEP_TOTAL): Installing package manager ..."

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Info 'scoop is already installed; skipping'
}
else {
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/windows/scoop-install.ps1
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Package manager installation failed' }
}

$env:SYNC_INTERACTIVE = '1'

if ($InstallProfile) {
  & $pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1 $InstallProfile
} else {
  & $pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1
}
if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Initialization failed' }

Write-Info 'Installation complete!'

} catch {
    Complete-UseFatal $_
}
