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
# Keep aligned with manifests/windows.json defaults (clone has not happened yet).
$ScoopDir = if (-not [string]::IsNullOrWhiteSpace($env:SCOOP)) { $env:SCOOP } else { 'D:\SoftwareApps\Scoop' }
$SoftwareAppsDir = 'D:\SoftwareApps'
$ScoopInstallScript = 'https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1'
$ScoopRepo = 'https://github.com/ScoopInstaller/Scoop'
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

function Test-Administrator {
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -eq $currentIdentity) { return $false }
        $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
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

function Test-ScoopAvailable {
  return [bool](Get-Command scoop -ErrorAction SilentlyContinue)
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

function Format-AccelLabel {
  param([string]$Prefix)
  if ([string]::IsNullOrWhiteSpace($Prefix)) { return 'Upstream' }
  return $Prefix
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
        if (Test-Path -LiteralPath $Target) {
          Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction SilentlyContinue
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

function Ensure-NodeRuntime {
  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) {
    Write-ErrorAndExit 'Node.js >= 22 is required. Install Node, then rerun. (https://nodejs.org/)'
  }
  $major = 0
  try {
    $major = [int]((node -p "process.versions.node.split('.')[0]").Trim())
  }
  catch {
    $major = 0
  }
  if ($major -lt 22) {
    $ver = & node -v
    Write-ErrorAndExit "Node.js >= 22 is required (found $ver). Upgrade Node, then rerun."
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

function Get-ScoopBootstrapAttempts {
  $preferred = Resolve-GithubAccelPrefix
  $attempts = New-Object System.Collections.Generic.List[object]
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

  $prefixOrder = New-Object System.Collections.Generic.List[string]
  if (-not [string]::IsNullOrWhiteSpace($preferred)) {
    [void]$prefixOrder.Add($preferred)
  }
  foreach ($prefix in $GithubAccelPrefixes) {
    if (-not [string]::IsNullOrWhiteSpace($preferred) -and $prefix.Equals($preferred, [StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    [void]$prefixOrder.Add($prefix)
  }
  [void]$prefixOrder.Add('')

  foreach ($prefix in $prefixOrder) {
    $fetchUrl = Join-AccelUrl -Url $ScoopInstallScript -Prefix $prefix
    if (-not $seen.Add($fetchUrl)) { continue }
    [void]$attempts.Add([pscustomobject]@{
        Prefix = $prefix
        Url    = $fetchUrl
      })
  }
  return $attempts
}

function Get-ScoopInstallerBootstrapUrls {
  @(
    'https://github.com/ScoopInstaller/Scoop/archive/master.zip',
    'https://github.com/ScoopInstaller/Main/archive/master.zip',
    'https://github.com/ScoopInstaller/Scoop.git',
    'https://github.com/ScoopInstaller/Main.git'
  )
}

function Rewrite-ScoopInstallerGithubUrls {
  param(
    [string]$Script,
    [string]$Prefix
  )

  if ([string]::IsNullOrWhiteSpace($Script) -or [string]::IsNullOrWhiteSpace($Prefix)) {
    return $Script
  }

  $targets = @(Get-ScoopInstallerBootstrapUrls) | Sort-Object { $_.Length } -Descending
  $rewritten = 0
  foreach ($bare in $targets) {
    $mirrored = Join-AccelUrl -Url $bare -Prefix $Prefix
    if ($mirrored -eq $bare) { continue }
    if ($Script.Contains($bare)) {
      $Script = $Script.Replace($bare, $mirrored)
      $rewritten++
    }
  }

  if ($rewritten -eq 0) {
    throw 'Scoop installer bootstrap URLs were not rewritten; refusing to run against upstream GitHub'
  }

  $mirroredHit = $false
  foreach ($bare in $targets) {
    $mirrored = Join-AccelUrl -Url $bare -Prefix $Prefix
    if ($mirrored -ne $bare -and $Script.Contains($mirrored)) {
      $mirroredHit = $true
      break
    }
  }
  if (-not $mirroredHit) {
    throw 'Scoop installer rewrite produced no mirrored Scoop/Main URLs'
  }
  return $Script
}

function Update-ScoopShimPath {
  $env:PATH = "$ScoopDir\shims;$ScoopDir\apps\scoop\current\bin;$env:PATH"
}

function Install-ScoopBootstrap {
  if (Test-ScoopAvailable) {
    Write-Info 'Scoop is already installed'
    if (-not $env:SCOOP) { $env:SCOOP = $ScoopDir }
    Update-ScoopShimPath
    return (Resolve-GithubAccelPrefix)
  }

  Write-Info 'Scoop is not installed; installing before cloning the repository...'

  if (-not (Test-Path -LiteralPath $SoftwareAppsDir)) {
    New-Item -ItemType Directory -Path $SoftwareAppsDir -Force | Out-Null
  }

  $env:SCOOP = $ScoopDir
  [Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')

  $attempts = @(Get-ScoopBootstrapAttempts)
  $errors = New-Object System.Collections.Generic.List[string]
  $successPrefix = $null

  foreach ($attempt in $attempts) {
    $label = Format-AccelLabel -Prefix $attempt.Prefix
    Write-Info "Trying Scoop installer ($label): $($attempt.Url)"
    try {
      $script = [string](Invoke-RestMethod -Uri $attempt.Url)
      if ([string]::IsNullOrWhiteSpace($script)) {
        throw 'Empty installer response'
      }
      if ($script -notmatch 'function\s+Install-Scoop' -and $script -notmatch 'SCOOP_PACKAGE_GIT_REPO') {
        throw 'Response does not look like the Scoop installer'
      }

      if (-not [string]::IsNullOrWhiteSpace($attempt.Prefix)) {
        $script = Rewrite-ScoopInstallerGithubUrls -Script $script -Prefix $attempt.Prefix
      }

      # Concatenate (do not interpolate) so installer $-variables stay intact.
      if (Test-Administrator) {
        Invoke-Expression ('& { ' + $script + ' } -RunAsAdmin')
      }
      else {
        Invoke-Expression $script
      }

      $successPrefix = [string]$attempt.Prefix
      Write-Info "Scoop installer succeeded ($label)"
      break
    }
    catch {
      $msg = $_.Exception.Message
      Write-Warn "Scoop installer failed ($label): $msg"
      [void]$errors.Add("${label}: $msg")
    }
  }

  if ($null -eq $successPrefix -and $errors.Count -gt 0 -and -not (Test-ScoopAvailable)) {
    Write-ErrorAndExit ("Scoop installation failed after trying all sources: " + ($errors -join '; '))
  }

  Update-ScoopShimPath
  if (-not (Test-ScoopAvailable)) {
    Write-ErrorAndExit 'Scoop is still unavailable after bootstrap; open a new terminal and rerun'
  }

  # Help the first scoop install 7zip/git resolve the Scoop repo via the working mirror.
  if (-not [string]::IsNullOrWhiteSpace($successPrefix)) {
    $mirroredRepo = Join-AccelUrl -Url $ScoopRepo -Prefix $successPrefix
    scoop config scoop_repo $mirroredRepo 2>$null | Out-Null
  }

  return $successPrefix
}

function Install-ScoopBootstrapApps {
  Update-ScoopShimPath
  if (-not (Test-ScoopAvailable)) {
    Write-ErrorAndExit 'Scoop is required to install 7zip and git'
  }

  foreach ($app in @('7zip', 'git')) {
    $shim = Get-Command $app -ErrorAction SilentlyContinue
    if ($app -eq '7zip') {
      $shim = Get-Command '7z' -ErrorAction SilentlyContinue
    }
    if ($shim) {
      Write-Info "$app is already available; skipping"
      continue
    }

    Write-Info "Installing $app via Scoop..."
    scoop install $app
    if ($LASTEXITCODE -ne 0) {
      Write-ErrorAndExit "Failed to install $app via Scoop"
    }
    Update-ScoopShimPath
  }

  if (-not (Test-GitAvailable)) {
    Write-ErrorAndExit 'Git is still unavailable after scoop install git'
  }
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

# Scoop/Git must exist before clone/sync; not part of the numbered init step chain.
Write-Info 'Ensuring Scoop, 7zip, and Git...'
$null = Install-ScoopBootstrap
Install-ScoopBootstrapApps

if (-not (Test-Path $InstallDir)) {
  Write-Info "Fetching repository to $InstallDir ..."
  Fetch-UseRepository $InstallDir
}
elseif (Test-SameRemoteRepo $InstallDir) {
  Write-Info "Existing repository found at $InstallDir; syncing with origin/main ..."
  Update-UseRepository $InstallDir
}
else {
  $InstallDir = Get-NextTimestampedDir $InstallDir
  Write-Info "Directory is in use; fetching to $InstallDir ..."
  Fetch-UseRepository $InstallDir
}

Set-Location $InstallDir
Ensure-NodeRuntime

# The installer completes step 1; the total includes subsequent init steps.
$initSteps = 4
$env:USE_STEP_CHAIN = '1'
$env:USE_STEP_CURRENT = '1'
$env:USE_STEP_TOTAL = "$([int]$env:USE_STEP_CURRENT + $initSteps)"
Write-Step "Step $($env:USE_STEP_CURRENT)/$($env:USE_STEP_TOTAL): Configuring package manager acceleration ..."

# Scoop is already installed; this applies scoop-mirror / aria2 and keeps USE_ACCEL explicit.
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
