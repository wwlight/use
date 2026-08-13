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
    'ghproxy-net',
    'ghfast'
)
$GithubAccelPrefixes = @(
    'https://gh-proxy.com/',
    'https://ghproxy.net/',
    'https://ghfast.top/'
)
# END GENERATED GITHUB ACCEL

function Write-Info     { Write-Host "  $args" }
function Write-Note     { Write-Host "  $([char]0x25CF) $args" -ForegroundColor Blue }
function Write-Skip     { Write-Host "  $([char]0x25CB) $args" -ForegroundColor DarkGray }
function Write-Step     { Write-Host "`n$([char]0x25C7) $args" -ForegroundColor Magenta }
function Write-Success  { Write-Host "  $([char]0x25C6) $args" -ForegroundColor Green }
function Write-StepSuccess { Write-Host "$([char]0x25C6) $args" -ForegroundColor Green }
function Write-Warn     { Write-Host "  $([char]0x25B2) $args" -ForegroundColor Yellow }

# Display paths under the user profile as ~/... (hide username); filesystem ops still use absolutes.
function Format-DisplayPath {
  param([Parameter(Mandatory)][string]$Path)
  # Do not use $home - PowerShell's automatic $HOME is read-only (case-insensitive).
  $homeRoot = (($env:USERPROFILE) -replace '\\', '/').TrimEnd('/')
  $normalized = $Path -replace '\\', '/'
  if ($normalized -eq $homeRoot) { return '~' }
  if ($normalized.StartsWith("$homeRoot/")) {
    return "~/$($normalized.Substring($homeRoot.Length + 1))"
  }
  return $normalized
}

# Bootstrap-only spinner (repo utils.ps1 is unavailable until fetch completes).
function Enable-VtProcessing {
  # Conhost / Windows Terminal need VT enabled explicitly on Windows PowerShell 5.x;
  # PowerShell Core enables it itself. No-op when calls are redirected (GetConsoleMode fails).
  if (-not ('UseSpin.Native' -as [type])) {
    Add-Type -Namespace UseSpin -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
  }
  try {
    $handle = [UseSpin.Native]::GetStdHandle(-11)
    $mode = [uint32]0
    if (-not [UseSpin.Native]::GetConsoleMode($handle, [ref]$mode)) { return $false }
    if ($mode -band 0x4) { return $true }
    return [UseSpin.Native]::SetConsoleMode($handle, ($mode -bor 0x4))
  }
  catch { return $false }
}

function Test-CanSpin {
  if ($env:CI -eq 'true') { return $false }
  if (-not [Environment]::UserInteractive) { return $false }
  try { if ([Console]::IsErrorRedirected -and [Console]::IsOutputRedirected) { return $false } } catch { }
  # Windows PowerShell 5.x renders 5.1's Unicode frames as '?' in legacy conhost, so it gets ASCII frames.
  # VT must still be on for the \r overwrite + ESC[2K erase to work there.
  if ($PSVersionTable.PSEdition -eq 'Desktop') { return (Enable-VtProcessing) }
  return $true
}

function Invoke-Spin {
  param(
    [Parameter(Mandatory)][string]$Message,
    [Parameter(Mandatory)][scriptblock]$Script,
    [string]$Indent = '  ',
    [object[]]$ArgumentList = @()
  )
  if (-not (Test-CanSpin)) {
    Write-Info $Message
    $result = & $Script @ArgumentList
    if ($null -eq $LASTEXITCODE) { $global:LASTEXITCODE = 0 }
    return $result
  }
  # Install.sh backgrounds curl; a job does the same on Windows. A synchronous
  # Invoke-WebRequest / native cmd blocks the Timer event pump, so the frames
  # paint here in the poll loop instead of relying on Register-ObjectEvent.
  # Distinct frames (|/-\) so rotation is obvious; the Unicode quarter-circles
  # (◒◐◓◑) look static at console font sizes and '?' on 5.x conhost without VT.
  $frames = @('|', '/', '-', '\')
  $job = $null
  try {
    $job = Start-Job -ScriptBlock $Script -ArgumentList $ArgumentList
  }
  catch {
    # Job host unavailable (rare); fall back to a synchronous run.
    [Console]::Error.Write("`n")
    $result = & $Script @ArgumentList
    if ($null -eq $LASTEXITCODE) { $global:LASTEXITCODE = 0 }
    return $result
  }
  $i = 0
  try { [Console]::CursorVisible = $false } catch { }
  try {
    while ($job.State -eq 'Running') {
      [Console]::Error.Write(("`r{0}{1}[34m{2} {3}{1}[0m" -f $Indent, [char]27, $frames[$i % $frames.Count], $Message))
      $i++
      Start-Sleep -Milliseconds 100
    }
  }
  finally {
    try { [Console]::Error.Write("`r`e[2K"); [Console]::CursorVisible = $true } catch { }
  }
  $output = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
  Remove-Job -Job $job -Force
  $global:LASTEXITCODE = 0
  return $output[$output.Count - 1]
}

# irm|iex runs in the current host. Throw and catch at the top level to avoid closing the session.
function Write-ErrorAndExit {
    Write-Host "$([char]0x25A0) $args" -ForegroundColor Red
    throw 'USE_FATAL'
}

function Complete-UseFatal {
    param($ErrorRecord)
    $fatalMessage = "$($ErrorRecord.Exception.Message)"
    if ($fatalMessage -eq 'USE_CANCELED') {
        $global:LASTEXITCODE = 0
        # Exit the process for -File; under iex, stop only the script and retain the exit code.
        if (-not [string]::IsNullOrEmpty($PSCommandPath)) {
            exit 0
        }
        return
    }
    if ($fatalMessage -ne 'USE_FATAL') {
        Write-Host "$([char]0x25A0) $fatalMessage" -ForegroundColor Red
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

# PS 5.1 renders Invoke-WebRequest progress per chunk; silent it keeps downloads from stalling.
$ProgressPreference = 'SilentlyContinue'
# Per-request timeout so a dead mirror fails fast instead of hanging ~100s.
$WebTimeoutSec = 15

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

# Match install.sh spin labels: show host only, never the full mirror URL.
function Get-UrlHostLabel {
  param([string]$Url)
  try {
    $hostName = ([Uri]$Url).Host
    if (-not [string]::IsNullOrWhiteSpace($hostName)) { return $hostName }
  }
  catch { }
  if ($Url -match '://([^/]+)') { return $Matches[1] }
  return 'source'
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
      $hostLabel = Get-UrlHostLabel $url
      $downloaded = Invoke-Spin "Downloading $hostLabel ..." {
        param($Uri, $Out, $TimeoutSec)
        try {
          Invoke-WebRequest -Uri $Uri -OutFile $Out -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
          return $true
        }
        catch { return $false }
      } -ArgumentList @($url, $zipFile, $WebTimeoutSec)
      if ($downloaded -ne $true) { continue }
      $extractRoot = Join-Path $tmp 'extract'
      if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
      }
      New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
      $unpacked = Invoke-Spin "Extracting $ZipExtractName ..." {
        param($Zip, $Dest)
        try {
          # PS 5.1 Expand-Archive garbles UTF-8 filenames; ZipFile+UTF8 works on both editions.
          Add-Type -AssemblyName System.IO.Compression.FileSystem
          [System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Dest, [System.Text.Encoding]::UTF8)
          return $true
        }
        catch { return $false }
      } -ArgumentList @($zipFile, $extractRoot)
      if ($unpacked -ne $true) { continue }
      $extracted = Join-Path $extractRoot $ZipExtractName
      if (-not (Test-Path -LiteralPath $extracted)) {
        continue
      }
      # Caller must not pass a cwd/locked Target; refresh without Git uses a new directory.
      if (Test-Path -LiteralPath $Target) {
        Remove-Item -LiteralPath $Target -Recurse -Force
      }
      if (Test-Path -LiteralPath $Target) {
        continue
      }
      Move-Item -LiteralPath $extracted -Destination $Target
      Write-StepSuccess "Extracted repository to $(Format-DisplayPath $Target)"
      return $true
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
      $script = [string](Invoke-RestMethod -Uri $url -TimeoutSec $WebTimeoutSec)
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
    Write-Info 'Node.js was not found.'
    if (-not (Test-UseInstallInteractive)) {
      Write-ErrorAndExit @'
Node.js is required. Install vite-plus (includes Node) or Node itself, then rerun:
  irm https://vite.plus/ps1 | iex
  # or: https://nodejs.org/
'@
    }

    Write-Host ''
    Write-Info 'Install Node.js via vite-plus? (https://vite.plus)'
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

function Invoke-UseCli {
  param([Parameter(Mandatory = $true)][string[]]$CliArgs)
  $cliJs = Join-Path $InstallDir 'src/cli.js'
  $argv = @($CliArgs | Where-Object { $_ -ne $null -and "$_" -ne '' -and "$_" -ne '--' })
  $node = Resolve-NodeExe
  # Direct invocation keeps node's stdout/stderr on the real console so its spinner
  # and menus still see a TTY; Start-Process turns the handles into pipes (isTTY=undefined).
  # Enable VT first so 5.x consoles render the CLI's ANSI erases cleanly.
  [void](Enable-VtProcessing)
  & $node $cliJs @argv
  if ($LASTEXITCODE -eq 130) { throw 'USE_CANCELED' }
  if ($LASTEXITCODE -ne 0) {
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
    $hostLabel = Get-UrlHostLabel $url
    $cloned = Invoke-Spin "Cloning $hostLabel ..." {
      param($Uri, $Dst)
      git clone --depth=1 $Uri $Dst 1>$null 2>$null
      return ($LASTEXITCODE -eq 0)
    } -ArgumentList @($url, $Target)
    if ($cloned -ne $true) { continue }
    Write-StepSuccess "Cloned repository to $(Format-DisplayPath $Target)"
    return $true
  }
  return $false
}

# Zip checkouts carry no .git, so the next install would skip the git-update branch
# and re-download into a new timestamped directory forever. Give the checkout a git
# origin when git exists: subsequent installs then update in place. Returns whether
# the directory is now a recognized git checkout of this repository.
function ConvertTo-UseGitRepository {
  param([string]$Target)
  if (-not (Test-GitAvailable)) { return $false }
  if (Test-Path -LiteralPath (Join-Path $Target '.git')) { return (Test-SameRemoteRepo -Dir $Target) }
  git -C $Target init 1>$null 2>$null
  if ($LASTEXITCODE -ne 0) { return $false }
  git -C $Target remote add origin $Repo 1>$null 2>$null
  if ($LASTEXITCODE -ne 0) { return $false }
  return (Test-SameRemoteRepo -Dir $Target)
}

function Fetch-UseRepository {
  param([string]$Target)

  if (Expand-UseZipRepository -Target $Target) {
    Unblock-UseScripts -Root $Target
    $null = ConvertTo-UseGitRepository -Target $Target
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

  $spin = Test-CanSpin
  $candidates = @(Get-GithubRepoCandidates)
  for ($idx = 0; $idx -lt $candidates.Count; $idx++) {
    $url = $candidates[$idx]
    git -C $Target remote set-url origin $url 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    $hostLabel = Get-UrlHostLabel $url
    if ($spin) {
      $synced = Invoke-Spin "Syncing $hostLabel ..." {
        param($Dst)
        git -C $Dst fetch origin main 1>$null 2>$null
        return ($LASTEXITCODE -eq 0)
      } -ArgumentList @($Target)
    }
    else {
      # Static console: mark each attempt and memo git's own error spam away.
      Write-Note "Syncing $hostLabel ..."
      git -C $Target fetch origin main 1>$null 2>$null
      $synced = ($LASTEXITCODE -eq 0)
    }
    if ($synced -ne $true) {
      if ($idx -lt $candidates.Count - 1) {
        Write-Skip "$hostLabel unavailable; trying the next mirror..."
      }
      continue
    }
    git -C $Target reset --hard origin/main 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Failed to reset local repository' }
    Write-StepSuccess 'Repository synced with origin/main'
    return
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

# Bound mirror stalls for every git op below: abort a transfer that stays under
# 1 B/s for 20s (git clone/fetch/reset) instead of hanging silently.
$env:GIT_HTTP_LOW_SPEED_LIMIT = '1'
$env:GIT_HTTP_LOW_SPEED_TIME = '15'

if (-not (Test-Path $InstallDir)) {
  Write-Step "Fetching repository to $(Format-DisplayPath $InstallDir)"
  Fetch-UseRepository $InstallDir
}
elseif (Test-SameRemoteRepo $InstallDir) {
  Write-Step "Updating repository at $(Format-DisplayPath $InstallDir)"
  Update-UseRepository $InstallDir
}
else {
  # Existing zip checkout without git: heal it into a git repo and update in place
  # instead of downloading a fresh sibling directory every run.
  if (ConvertTo-UseGitRepository -Target $InstallDir) {
    Write-Step "Updating repository at $(Format-DisplayPath $InstallDir)"
    try {
      Update-UseRepository $InstallDir
      Set-Location $InstallDir
    }
    catch {
      Write-Warn 'In-place git update failed; fetching a fresh copy...'
      $InstallDir = Get-NextTimestampedDir $InstallDir
      Write-Step "Fetching repository to $(Format-DisplayPath $InstallDir)"
      Fetch-UseRepository $InstallDir
    }
  }
  else {
    # Zip checkout may be the shell cwd (cannot delete). No Git -> always fetch a fresh sibling dir.
    $InstallDir = Get-NextTimestampedDir $InstallDir
    Write-Step "Fetching repository to $(Format-DisplayPath $InstallDir)"
    Fetch-UseRepository $InstallDir
  }
}

Set-Location $InstallDir

# curl|bash pipes stdin; menus still talk to /dev/tty when present.
$env:SYNC_INTERACTIVE = '1'
$env:USE_QUIET_INSTALL = '1'
try {
  $scoopInstallArgs = @()
  if (-not [string]::IsNullOrWhiteSpace($env:USE_ACCEL)) {
    $scoopInstallArgs = @("$($env:USE_ACCEL.Trim())")
  }
  $pmArgs = @('pm')
  if ($scoopInstallArgs.Count -gt 0) { $pmArgs += $scoopInstallArgs }
  Invoke-UseCli -CliArgs $pmArgs

  $env:SYNC_INTERACTIVE = '1'
  # pm already deployed helpers; runtime helpers are not part of config sync.
  $env:USE_INSTALLER = '1'
  if ($InstallProfile) {
    Invoke-UseCli -CliArgs @('init', $InstallProfile)
  } else {
    Invoke-UseCli -CliArgs @('init')
  }

  Write-Host ''
  Write-StepSuccess 'Installation complete. The system is ready.'
}
finally {
  Remove-Item Env:GIT_HTTP_LOW_SPEED_LIMIT -ErrorAction SilentlyContinue
  Remove-Item Env:GIT_HTTP_LOW_SPEED_TIME -ErrorAction SilentlyContinue
  Remove-Item Env:USE_INSTALLER -ErrorAction SilentlyContinue
  Remove-Item Env:USE_QUIET_INSTALL -ErrorAction SilentlyContinue
}

} catch {
    Complete-UseFatal $_
}
