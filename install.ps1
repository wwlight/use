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

function Write-Info     { Write-Host "$args" }
function Write-Step     { Write-Host "`n➤ $args" -ForegroundColor Magenta }
function Write-Success  { Write-Host "  ✔ $args" -ForegroundColor Green }
function Write-Warn     { Write-Host "⚠ $args" -ForegroundColor Yellow }

# irm|iex runs in the current host. Throw and catch at the top level to avoid closing the session.
function Write-ErrorAndExit {
    Write-Host "✗ $args" -ForegroundColor Red
    throw 'USE_FATAL'
}

function Complete-UseFatal {
    param($ErrorRecord)
    if ("$($ErrorRecord.Exception.Message)" -ne 'USE_FATAL') {
        Write-Host "✗ $($ErrorRecord.Exception.Message)" -ForegroundColor Red
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
        # Caller must not pass a cwd/locked Target; refresh without Git uses a new directory.
        if (Test-Path -LiteralPath $Target) {
          Remove-Item -LiteralPath $Target -Recurse -Force
        }
        if (Test-Path -LiteralPath $Target) {
          throw "Could not replace existing directory: $Target"
        }
        Move-Item -LiteralPath $extracted -Destination $Target
        Write-Info "Extracted repository to $Target"
        return $true
      }
      catch {
        Write-Warn "Zip fetch failed ($url): $($_.Exception.Message)"
      }
    }
    return $false
  }
  finally {
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
    Write-Warn 'Install Node.js via vite-plus? (https://vite.plus)'
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

function Resolve-NodeExe {
  # Prefer node.exe over node.ps1: PS 5.1's binder eats bare "--" when invoking .ps1 shims,
  # which can make node see argv[2]="--" instead of "init".
  foreach ($name in @('node.exe', 'node')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $cmd) { continue }
    $path = $cmd.Source
    if (-not $path) { $path = $cmd.Path }
    if (-not $path) { continue }
    if ($path -like '*.ps1') {
      $exe = [IO.Path]::ChangeExtension($path, '.exe')
      if (Test-Path -LiteralPath $exe) { return $exe }
      continue
    }
    return $path
  }
  return 'node'
}

function ConvertTo-ProcessArgumentString {
  param([string[]]$Parts)
  return (($Parts | ForEach-Object {
    $s = "$_"
    if ($s -notmatch '[\s"]') { $s }
    else { '"' + ($s -replace '"', '\"') + '"' }
  }) -join ' ')
}

function Invoke-UseCli {
  param([Parameter(Mandatory = $true)][string[]]$CliArgs)
  $cliJs = Join-Path $InstallDir 'src/cli.js'
  $argv = @($CliArgs | Where-Object { $_ -ne $null -and "$_" -ne '' -and "$_" -ne '--' })
  $node = Resolve-NodeExe
  $argLine = ConvertTo-ProcessArgumentString (@($cliJs) + $argv)
  # Start-Process + explicit exe avoids PS 5.1 call-operator / .ps1 shim mangling.
  $proc = Start-Process -FilePath $node -ArgumentList $argLine -WorkingDirectory $InstallDir -NoNewWindow -Wait -PassThru
  if ($proc.ExitCode -ne 0) {
    Write-ErrorAndExit "CLI failed: node src/cli.js $($argv -join ' ')"
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
  $ts = Get-Date -Format 'yyyyMMddHHmmss'
  $target = "$Base$ts"
  while (Test-Path $target) {
    Start-Sleep -Seconds 1
    $ts = Get-Date -Format 'yyyyMMddHHmmss'
    $target = "$Base$ts"
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
else {
  # Zip checkout may be the shell cwd (cannot delete). No Git → always fetch a fresh sibling dir.
  $InstallDir = Get-NextTimestampedDir $InstallDir
  Write-Info "Fetching repository to $InstallDir ..."
  Fetch-UseRepository $InstallDir
}

Set-Location $InstallDir

# curl|bash pipes stdin; menus still talk to /dev/tty when present.
$env:SYNC_INTERACTIVE = '1'
Write-Step 'Configuring package manager acceleration ...'

$scoopInstallArgs = @()
if (-not [string]::IsNullOrWhiteSpace($env:USE_ACCEL)) {
    $scoopInstallArgs = @("$($env:USE_ACCEL.Trim())")
}
$pmArgs = @('pm')
if ($scoopInstallArgs.Count -gt 0) { $pmArgs += $scoopInstallArgs }
Invoke-UseCli -CliArgs $pmArgs

$env:SYNC_INTERACTIVE = '1'
# pm already deployed helpers; init sync skips pmHelper pairs.
$env:SYNC_SKIP_PM_HELPERS = '1'
if ($InstallProfile) {
  Invoke-UseCli -CliArgs @('init', $InstallProfile)
} else {
  Invoke-UseCli -CliArgs @('init')
}
Remove-Item Env:SYNC_SKIP_PM_HELPERS -ErrorAction SilentlyContinue

Write-Success 'Installation complete!'

} catch {
    Complete-UseFatal $_
}
