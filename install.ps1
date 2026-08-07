param(
    [Parameter(Position = 0)]
    [string]$InstallProfile
)

if ([string]::IsNullOrWhiteSpace($InstallProfile)) {
    $InstallProfile = $env:USE_PROFILE
}

$Repo = 'https://github.com/wwlight/use.git'
$RepoZip = 'https://github.com/wwlight/use/archive/refs/heads/main.zip'
$ZipExtractName = 'use-main'
$InstallDir = "$env:USERPROFILE\Desktop\use"
# BEGIN GENERATED GITHUB ACCEL
$GithubAccelIds = @(
    'ghproxy',
    'ghfast'
)
$GithubAccelPrefixes = @(
    'https://gh-proxy.com/',
    'https://ghfast.top/'
)
# END GENERATED GITHUB ACCEL

function Write-Info  { Write-Host "[INFO] $args" -ForegroundColor Green }
function Write-Step  { Write-Host "[INFO] $args" -ForegroundColor Blue }
function Write-Warn  { Write-Host "[WARN] $args" -ForegroundColor Yellow }

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

function Test-GitAvailable {
  return [bool](Get-Command git -ErrorAction SilentlyContinue)
}

function Test-SameRemoteRepo {
  param([string]$Dir)
  $gitDir = Join-Path $Dir '.git'
  if (-not (Test-Path $gitDir)) { return $false }
  if (-not (Test-GitAvailable)) { return $false }
  $remote = git -C $Dir remote get-url origin 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) { return $false }
  return (Normalize-RepoUrl $remote) -eq (Normalize-RepoUrl $Repo)
}

# Resolve USE_ACCEL=<id> (set by mirrored one-liners) to a known prefix.
function Resolve-GithubAccelPrefix {
  $accel = $env:USE_ACCEL
  if ([string]::IsNullOrWhiteSpace($accel)) { return '' }
  for ($i = 0; $i -lt $GithubAccelIds.Count; $i++) {
    if ($GithubAccelIds[$i].Equals($accel, [StringComparison]::OrdinalIgnoreCase)) {
      return $GithubAccelPrefixes[$i]
    }
  }
  return ''
}

function Join-AccelUrl {
  param(
    [string]$Url,
    [string]$Prefix
  )
  $bare = Remove-GithubAccelPrefix $Url
  if ([string]::IsNullOrWhiteSpace($Prefix)) { return $bare }
  if (-not $Prefix.EndsWith('/')) { $Prefix += '/' }
  return ($Prefix + $bare)
}

function Get-GithubUrlCandidates {
  param([string]$Url)
  $preferred = Resolve-GithubAccelPrefix
  if (-not [string]::IsNullOrWhiteSpace($preferred)) {
    (Join-AccelUrl -Url $Url -Prefix $preferred)
  }
  foreach ($prefix in $GithubAccelPrefixes) {
    if (-not [string]::IsNullOrWhiteSpace($preferred) -and $prefix.Equals($preferred, [StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    (Join-AccelUrl -Url $Url -Prefix $prefix)
  }
  (Remove-GithubAccelPrefix $Url)
}

function Get-GithubRepoCandidates {
  Get-GithubUrlCandidates -Url $Repo
}

function Get-GithubZipCandidates {
  Get-GithubUrlCandidates -Url $RepoZip
}

function Expand-UseZipRepository {
  param([string]$Target)

  $parent = Split-Path $Target -Parent
  if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  $tmp = Join-Path $parent ("use-zip-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp -Force | Out-Null
  $zipFile = Join-Path $tmp 'use-main.zip'
  $staging = $null

  try {
    foreach ($url in (Get-GithubZipCandidates)) {
      Write-Info "Trying zip URL: $url"
      try {
        Invoke-WebRequest -Uri $url -OutFile $zipFile -UseBasicParsing
        $extractRoot = Join-Path $tmp 'extract'
        if (Test-Path -LiteralPath $extractRoot) {
          Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
        Expand-Archive -LiteralPath $zipFile -DestinationPath $extractRoot -Force
        $extracted = Join-Path $extractRoot $ZipExtractName
        if (-not (Test-Path -LiteralPath $extracted)) {
          throw "Expected folder missing: $ZipExtractName"
        }

        # Stage under a unique name first. Move-Item into an existing $Target directory
        # nests as $Target\use-main (and fails if that leftover already exists).
        $staging = Join-Path $parent ("use-new-" + [guid]::NewGuid().ToString('N'))
        if (Test-Path -LiteralPath $staging) {
          Remove-Item -LiteralPath $staging -Recurse -Force
        }
        Move-Item -LiteralPath $extracted -Destination $staging

        if (Test-Path -LiteralPath $Target) {
          Remove-Item -LiteralPath $Target -Recurse -Force
        }
        if (Test-Path -LiteralPath $Target) {
          throw "Could not replace existing directory: $Target"
        }
        Move-Item -LiteralPath $staging -Destination $Target
        $staging = $null
        Write-Info "Extracted repository to $Target"
        return $true
      }
      catch {
        Write-Warn "Zip fetch failed ($url): $($_.Exception.Message)"
        if ($staging -and (Test-Path -LiteralPath $staging)) {
          Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
          $staging = $null
        }
      }
    }
    return $false
  }
  finally {
    if ($staging -and (Test-Path -LiteralPath $staging)) {
      Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Unblock-UseScripts {
  param([string]$Root)
  Get-ChildItem -LiteralPath $Root -Recurse -Include *.ps1,*.psm1 -ErrorAction SilentlyContinue |
    Unblock-File -ErrorAction SilentlyContinue
}

function Test-NodeAvailable {
  return [bool](Get-Command node -ErrorAction SilentlyContinue)
}

function Test-UseInstallInteractive {
  if ($env:CI -eq 'true') { return $false }
  if (-not [Environment]::UserInteractive) { return $false }
  return $true
}

function Update-NodeShimPath {
  $vpBin = Join-Path $env:USERPROFILE '.vite-plus\bin'
  if (Test-Path -LiteralPath $vpBin) {
    $env:PATH = "$vpBin;$env:PATH"
  }
}

function Install-NodeViaVitePlus {
  Write-Info 'Installing Node.js via vite-plus...'
  $env:VP_NODE_MANAGER = 'yes'
  $scriptUrl = 'https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli/install.ps1'
  $errors = New-Object System.Collections.Generic.List[string]

  foreach ($url in (Get-GithubUrlCandidates -Url $scriptUrl)) {
    Write-Info "Trying vite-plus installer: $url"
    try {
      $script = [string](Invoke-RestMethod -Uri $url)
      if ($script -notmatch 'function\s+Setup-NodeManager') {
        throw 'Response does not look like the vite-plus installer'
      }
      Invoke-Expression $script
    }
    catch {
      Write-Warn "vite-plus installer failed ($url): $($_.Exception.Message)"
      [void]$errors.Add($_.Exception.Message)
      continue
    }

    Update-NodeShimPath
    if (Test-NodeAvailable) { return }
    # Installer ran; do not try another mirror (avoids reinstall loops).
    Write-ErrorAndExit 'vite-plus finished but node is unavailable in this session; open a new terminal and rerun'
  }

  Write-ErrorAndExit (
    'Failed to install Node.js via vite-plus. Install manually from https://vite.plus or https://nodejs.org/, then rerun. ' +
    ($errors -join '; ')
  )
}

function Ensure-NodeRuntime {
  Update-NodeShimPath
  if (-not (Test-NodeAvailable)) {
    Write-Warn 'Node.js was not found.'
    if (-not (Test-UseInstallInteractive)) {
      Write-ErrorAndExit @'
Node.js is required. Install vite-plus (includes Node) or Node itself, then rerun:
  irm https://vite.plus/ps1 | iex
  # or: https://nodejs.org/
'@
    }

    Write-Host ''
    Write-Host 'Install Node.js via vite-plus? (https://vite.plus)' -ForegroundColor Yellow
    Write-Host '  Y / Enter  install vite-plus (manages Node)'
    Write-Host '  N          cancel'
    $answer = Read-Host 'Proceed'
    if ($answer -match '^(n|no)$') {
      Write-ErrorAndExit 'Node.js is required. Install from https://vite.plus or https://nodejs.org/, then rerun.'
    }
    Install-NodeViaVitePlus
  }

  if (-not (Test-NodeAvailable)) {
    Write-ErrorAndExit 'Node.js is required but still unavailable'
  }
  $major = 0
  try { $major = [int]((node -p "process.versions.node.split('.')[0]").Trim()) } catch { }
  if ($major -lt 18) {
    Write-ErrorAndExit "Node.js >= 18 is required (found $(node -v))"
  }
  Write-Info "Using Node $(node -v)"
}

function Invoke-UseCli {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArgs)
  & node (Join-Path $InstallDir 'src/cli.js') @CliArgs
  if ($LASTEXITCODE -ne 0) {
    Write-ErrorAndExit "CLI failed: node src/cli.js $($CliArgs -join ' ')"
  }
}

function Copy-UseRepository {
  param([string]$Target)

  if (-not (Test-GitAvailable)) {
    return $false
  }

  foreach ($url in (Get-GithubRepoCandidates)) {
    Remove-Item $Target -Recurse -Force -ErrorAction SilentlyContinue
    Write-Info "Trying clone URL: $url"
    git clone --depth=1 $url $Target
    if ($LASTEXITCODE -eq 0) { return $true }
  }
  return $false
}

function Fetch-UseRepository {
  param([string]$Target)

  if (Expand-UseZipRepository -Target $Target) {
    Unblock-UseScripts -Root $Target
    return
  }

  Write-Warn 'Zip download failed; falling back to git clone...'
  if (Copy-UseRepository -Target $Target) {
    Unblock-UseScripts -Root $Target
    return
  }

  if (Test-Path -LiteralPath $Target) {
    Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-ErrorAndExit 'Failed to fetch repository (zip and git clone both failed). Try another USE_ACCEL mirror or check the network.'
}

function Update-UseRepository {
  param([string]$Target)

  if (-not (Test-GitAvailable)) {
    Write-ErrorAndExit 'Git is required to update the repository'
  }

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

Ensure-NodeRuntime

if (-not (Test-Path $InstallDir)) {
  Write-Info "Fetching repository to $InstallDir ..."
  Fetch-UseRepository $InstallDir
}
elseif (Test-SameRemoteRepo $InstallDir) {
  Write-Info "Existing repository found at $InstallDir; syncing with origin/main ..."
  Update-UseRepository $InstallDir
}
elseif (
  -not (Test-GitAvailable) -and
  -not (Test-Path -LiteralPath (Join-Path $InstallDir '.git')) -and
  (Test-Path -LiteralPath (Join-Path $InstallDir 'src\cli.js'))
) {
  Write-Info "Refreshing repository at $InstallDir (Git not available yet)..."
  Fetch-UseRepository $InstallDir
}
else {
  $InstallDir = Get-NextTimestampedDir $InstallDir
  Write-Info "Directory is in use; fetching to $InstallDir ..."
  Fetch-UseRepository $InstallDir
}

Set-Location $InstallDir

$initSteps = 4
$env:USE_STEP_CHAIN = '1'
$env:USE_STEP_CURRENT = '1'
$env:USE_STEP_TOTAL = "$([int]$env:USE_STEP_CURRENT + $initSteps)"
Write-Step "Step $($env:USE_STEP_CURRENT)/$($env:USE_STEP_TOTAL): Configuring package manager acceleration ..."

$scoopInstallArgs = @()
if (-not [string]::IsNullOrWhiteSpace($env:USE_ACCEL)) {
    $scoopInstallArgs = @("$($env:USE_ACCEL.Trim())")
}
$pmArgs = @('pm')
if ($scoopInstallArgs.Count -gt 0) { $pmArgs += $scoopInstallArgs }
Invoke-UseCli @pmArgs

$env:SYNC_INTERACTIVE = '1'

if ($InstallProfile) {
  Invoke-UseCli @('init', '--', $InstallProfile)
} else {
  Invoke-UseCli @('init')
}

Write-Info 'Installation complete!'

} catch {
    Complete-UseFatal $_
}
