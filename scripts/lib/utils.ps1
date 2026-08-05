$Script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

# --- Windows-specific helpers ---
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

function Test-InteractivePrompt {
    if ($env:SYNC_INTERACTIVE -eq '1') {
        return $true
    }

    if (-not [Environment]::UserInteractive) {
        return $false
    }

    try {
        if (-not [Console]::IsInputRedirected) {
            return $true
        }
    }
    catch {
        return $false
    }

    # Do not open CONIN$ here: Node/Zsh dispatch or redirected stdin may block.
    # Callers enable interaction with SYNC_INTERACTIVE=1.
    return $false
}

# Normalize Git remotes for repository comparison.
function Normalize-RepoUrl {
    param([string]$Url)
    $u = Strip-GithubAccelPrefix -Url $Url
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

function Get-GithubAccelMirrors {
    if ($null -ne $script:GithubAccelMirrors) {
        return $script:GithubAccelMirrors
    }

    $cfg = (Read-Manifest -Scope common).githubAccel
    if (-not $cfg) {
        Write-ErrorAndExit 'common manifest is missing githubAccel'
    }

    $mirrors = @()
    foreach ($item in @($cfg.mirrors)) {
        if ($null -eq $item) { continue }
        $id = [string]$item.id
        $p = [string]$item.prefix
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not $p.EndsWith('/')) { $p += '/' }
        $mirrors += [pscustomobject]@{ id = $id; prefix = $p }
    }

    if ($mirrors.Count -eq 0) {
        Write-ErrorAndExit 'common githubAccel.mirrors is empty; configure at least one mirror'
    }

    $script:GithubAccelMirrors = $mirrors
    return $script:GithubAccelMirrors
}

function Get-GithubAccelPrefixes {
    if ($null -ne $script:GithubAccelPrefixes) {
        return $script:GithubAccelPrefixes
    }

    $prefixes = @(
        foreach ($item in (Get-GithubAccelMirrors)) {
            [string]$item.prefix
        }
    )
    $script:GithubAccelPrefixes = $prefixes
    return $script:GithubAccelPrefixes
}

function Get-GithubAccelSelectionMap {
    $map = [ordered]@{}
    foreach ($item in (Get-GithubAccelMirrors)) {
        $id = [string]$item.id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if (-not $map.Contains($id)) { $map[$id] = [string]$item.prefix }
    }
    $map['official'] = ''
    return $map
}

function Get-GithubAccelDefaultPrefix {
    if ($null -ne $script:GithubAccelDefaultPrefix) {
        return $script:GithubAccelDefaultPrefix
    }

    $cfg = (Read-Manifest -Scope common).githubAccel
    $defaultId = [string]$cfg.default
    $prefix = ''
    foreach ($item in (Get-GithubAccelMirrors)) {
        if ($defaultId -and ([string]$item.id -eq $defaultId)) {
            $prefix = [string]$item.prefix
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        $prefix = [string](Get-GithubAccelMirrors)[0].prefix
    }

    $script:GithubAccelDefaultPrefix = $prefix
    return $script:GithubAccelDefaultPrefix
}

function Strip-GithubAccelPrefix {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }
    foreach ($p in @(Get-GithubAccelPrefixes)) {
        if ($p -and $Url.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) {
            return $Url.Substring($p.Length)
        }
    }
    return $Url
}

function Test-GithubHttpUrl {
    param([string]$Url)
    $bare = Strip-GithubAccelPrefix -Url $Url
    return $bare -match '^https://(github\.com|raw\.githubusercontent\.com)/'
}

function ConvertTo-GithubAccelUrl {
    param([string]$Url)
    if (-not (Test-GithubHttpUrl -Url $Url)) { return $Url }
    $bare = Strip-GithubAccelPrefix -Url $Url
    $prefix = Get-GithubAccelDefaultPrefix
    if ([string]::IsNullOrWhiteSpace($prefix)) { return $bare }
    return ($prefix + $bare)
}

function Get-GithubAccelUrlCandidates {
    param([string]$Url)
    if (-not (Test-GithubHttpUrl -Url $Url)) {
        return @($Url)
    }

    $bare = Strip-GithubAccelPrefix -Url $Url
    $candidates = @()
    $default = Get-GithubAccelDefaultPrefix
    if ($default) { $candidates += ($default + $bare) }
    foreach ($p in (Get-GithubAccelPrefixes)) {
        if (-not $p) { continue }
        $candidate = $p + $bare
        if ($candidates -notcontains $candidate) { $candidates += $candidate }
    }
    if ($candidates -notcontains $bare) { $candidates += $bare }
    return $candidates
}

function Test-SameRemoteRepo {
    param(
        [string]$Dir,
        [string]$ExpectedRepo
    )
    $gitDir = Join-Path $Dir '.git'
    if (-not (Test-Path $gitDir)) { return $false }
    $remote = git -C $Dir remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) { return $false }
    return (Normalize-RepoUrl $remote) -eq (Normalize-RepoUrl $ExpectedRepo)
}

# --- Output helpers ---
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Step {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

# Global step counter shared across child processes.
#   USE_STEP_CHAIN=1  Continue progress started by the installer.
#   USE_STEP_TOTAL    Total steps.
#   USE_STEP_CURRENT  Completed steps.
function Test-UseStepUInt {
    param([string]$Value)
    return ($Value -match '^\d+$')
}

# Usage: Write-NextStep 'Creating directory structure...'
function Write-NextStep {
    param([string]$Message)

    $current = 0
    if (Test-UseStepUInt $env:USE_STEP_CURRENT) { $current = [int]$env:USE_STEP_CURRENT }
    $current++
    $env:USE_STEP_CURRENT = "$current"

    $total = 0
    if ((Test-UseStepUInt $env:USE_STEP_TOTAL) -and ([int]$env:USE_STEP_TOTAL -gt 0)) {
        $total = [int]$env:USE_STEP_TOTAL
    }

    if ($total -gt 0) {
        Write-Step "Step ${current}/${total}: $Message"
    }
    else {
        Write-Step $Message
    }
}

# Usage: Initialize-StepProgress 4
# Without USE_STEP_CHAIN=1, reset to this script's step count.
# With chaining, total = completed + this script's steps.
function Initialize-StepProgress {
    param([int]$LocalSteps)

    if ($env:USE_STEP_CHAIN -eq '1') {
        $current = 0
        if (Test-UseStepUInt $env:USE_STEP_CURRENT) { $current = [int]$env:USE_STEP_CURRENT }
        $env:USE_STEP_CURRENT = "$current"
        $env:USE_STEP_TOTAL = "$($current + $LocalSteps)"
        return
    }

    $env:USE_STEP_TOTAL = "$LocalSteps"
    $env:USE_STEP_CURRENT = '0'
}

function Write-Backup {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-SyncProgressHint {
    param(
        [string]$Direction,
        [int]$Total
    )

    if ($Total -le 0) { return }
    if ($env:SYNC_FROM_DISPATCH -eq '1') { return }

    if ($Direction -eq '1') {
        Write-Step "Backing up $Total files to the repository..."
    }
    else {
        Write-Step "Restoring $Total files locally..."
    }
    [Console]::Out.Flush()
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

# Install or update a Git-based plugin.
# Clone missing directories.
# With -Update, update matching remotes or reinstall mismatches.
# Without -Update, skip existing directories.
function Update-GitRepoToLatest {
    param([string]$Dir)

    git -C $Dir fetch --prune origin
    if ($LASTEXITCODE -ne 0) { return $false }

    $branch = (git -C $Dir rev-parse --abbrev-ref HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) { return $false }

    if ($branch -eq 'HEAD') {
        $originHead = (git -C $Dir symbolic-ref -q --short refs/remotes/origin/HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($originHead)) { return $false }
        $branch = ($originHead.Trim() -replace '^origin/', '')
        if ([string]::IsNullOrWhiteSpace($branch)) { return $false }
    }

    git -C $Dir reset --hard "origin/$branch"
    return ($LASTEXITCODE -eq 0)
}

function Install-GitRepoClone {
    param(
        [string]$Repo,
        [string]$TargetPath,
        [string]$Name
    )

    Write-Info "Downloading plugin: $Name..."
    $candidates = @(Get-GithubAccelUrlCandidates -Url $Repo)
    $ok = $false
    foreach ($url in $candidates) {
        if (Test-Path $TargetPath) {
            Remove-Item $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        git clone $url $TargetPath
        if ($LASTEXITCODE -eq 0) {
            $ok = $true
            if ($url -ne $Repo -and $url -ne (Strip-GithubAccelPrefix -Url $Repo)) {
                Write-Info "$Name cloned through a mirror"
            }
            break
        }
    }
    if (-not $ok) {
        Write-Warn "Failed to download $Name; skipping"
        return
    }
    Write-Info "$Name download complete"
}

function Sync-GitRepoPlugin {
    param(
        [string]$Repo,
        [string]$TargetPath,
        [string]$Name,
        [switch]$Update
    )

    if (-not (Test-Path $TargetPath -PathType Container)) {
        Install-GitRepoClone -Repo $Repo -TargetPath $TargetPath -Name $Name
        return
    }

    if (-not $Update) {
        Write-Info "Plugin $Name already exists; skipping"
        return
    }

    if (Test-SameRemoteRepo -Dir $TargetPath -ExpectedRepo $Repo) {
        Write-Info "Plugin $Name is linked to the remote repository; updating..."
        $accelUrl = ConvertTo-GithubAccelUrl -Url $Repo
        $current = (git -C $TargetPath remote get-url origin 2>$null)
        if ($accelUrl -and $current -and ($current.Trim() -ne $accelUrl)) {
            git -C $TargetPath remote set-url origin $accelUrl 2>$null
        }
        if (Update-GitRepoToLatest -Dir $TargetPath) {
            Write-Info "$Name is up to date"
        }
        else {
            # Retry with the upstream remote if the mirror fails.
            $bare = Strip-GithubAccelPrefix -Url $Repo
            git -C $TargetPath remote set-url origin $bare 2>$null
            if (Update-GitRepoToLatest -Dir $TargetPath) {
                Write-Info "$Name is up to date (upstream)"
            }
            else {
                Write-Warn "Failed to update $Name; skipping"
            }
        }
        return
    }

    Write-Info "Plugin $Name is not the expected repository; reinstalling..."
    Remove-Item $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
    Install-GitRepoClone -Repo $Repo -TargetPath $TargetPath -Name $Name
}

function Write-ErrorAndExit {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

# --- OS detection ---
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

# Expected value: macos, windows, or linux.
function Assert-TargetOs {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('macos', 'windows', 'linux')]
        [string]$Expected
    )

    $current = Get-Os
    if ($current -ne $Expected) {
        Write-ErrorAndExit "This script supports only $Expected; detected $current"
    }
}

# --- Manifest access ---
function Get-ManifestDirectories {
    param([string]$Scope = 'windows')

    $dirs = @()
    $seen = @{}
    foreach ($s in (Get-SyncScopes $Scope)) {
        $m = Read-Manifest -Scope $s
        foreach ($d in @($m.directories)) {
            if ($d -and -not $seen.ContainsKey($d)) {
                $seen[$d] = $true
                $dirs += $d
            }
        }
    }
    return $dirs
}

function Read-Manifest {
    param([string]$Scope = 'windows')

    $manifestPath = Join-Path $Script:ProjectRoot "scripts/$Scope/_manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Write-ErrorAndExit "Manifest not found: $manifestPath"
    }
    Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-SyncScopes {
    param([string]$Scope)

    $scopes = @($Scope)
    if ($Scope -eq 'macos' -or $Scope -eq 'windows') {
        $scopes += 'common'
    }
    return $scopes
}

function Write-SyncSelectError {
    if ($LASTEXITCODE -eq 130) {
        Write-ErrorAndExit 'File selection canceled'
    }
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit 'File selection failed; retry or run through vpr sync'
    }
}

# --- Path expansion (~ to $HOME) ---
function Get-ExpandedPath {
    param([string]$Path)
    if ($Path -match '^~(/|\\|$)') {
        $Path = $Path -replace '^~', $env:USERPROFILE
    }
    return $Path -replace '/', '\'
}

function Format-LocalDisplay {
    param([string]$Path)

    $normalized = $Path -replace '\\', '/'
    $userHome = ($env:USERPROFILE -replace '\\', '/').TrimEnd('/')

    if ($normalized -eq $userHome) {
        return '~'
    }
    if ($normalized -like "$userHome/*") {
        return "~/$($normalized.Substring($userHome.Length + 1))"
    }

    return $normalized
}

# --- File copy without Zone.Identifier or other ADS ---
function Copy-FileDataOnly {
    param(
        [string]$SourceFile,
        [string]$DestinationFile,
        [string]$Encoding = ''
    )

    $source = Get-ExpandedPath $SourceFile
    $destination = Get-ExpandedPath $DestinationFile
    $destinationDir = Split-Path $destination -Parent

    if (-not (Test-Path $source)) {
        throw "Source file not found: $source"
    }

    if (-not (Test-Path $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    if ($Encoding -eq 'utf8Bom') {
        $content = [System.IO.File]::ReadAllText($source, [System.Text.Encoding]::UTF8)
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($destination, $content, $utf8Bom)
        return
    }

    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($robocopy) {
        $sourceDir = Split-Path $source -Parent
        $sourceName = Split-Path $source -Leaf
        $destinationName = Split-Path $destination -Leaf
        $robocopyPath = $robocopy.Source
        $copyDir = $destinationDir
        $tempDir = $null

        if ($sourceName -ne $destinationName) {
            $tempDir = Join-Path $destinationDir ".copy-data-only-$([Guid]::NewGuid().ToString('N'))"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $copyDir = $tempDir
        }

        try {
            & $robocopyPath $sourceDir $copyDir $sourceName /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NC /NS | Out-Null
            $exitCode = $LASTEXITCODE
            if ($exitCode -ge 8) {
                throw "robocopy failed with exit code $exitCode"
            }

            if ($tempDir) {
                Move-Item (Join-Path $tempDir $sourceName) $destination -Force -ErrorAction Stop
            }
        }
        finally {
            if ($tempDir -and (Test-Path $tempDir)) {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not (Test-Path $destination)) {
            throw "Destination missing after copy: $destination"
        }
    }
    else {
        Copy-Item $source $destination -Force -ErrorAction Stop
    }
}

# --- Backups with custom paths and dated sequence numbers ---
function Backup-File {
    param(
        [string]$TargetFile,
        [string]$BackupDir = (Split-Path -Parent $TargetFile)
    )

    $target = Get-ExpandedPath $TargetFile
    if (-not (Test-Path $target)) {
        return $null
    }

    $backupRoot = Get-ExpandedPath $BackupDir
    if (-not (Test-Path $backupRoot)) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    }

    $fileName = Split-Path $target -Leaf
    $dateStr = Get-Date -Format 'yyyyMMdd'
    $backupBase = Join-Path $backupRoot "$fileName.bak.$dateStr"
    $nextNum = 0
    while (Test-Path "$backupBase.$nextNum") { $nextNum++ }

    $backupFile = "$backupBase.$nextNum"
    try {
        Copy-FileDataOnly $target $backupFile
        return "$fileName.bak.$dateStr.$nextNum"
    }
    catch {
        Write-Warn "Backup failed: $fileName"
        return $null
    }
}

# --- Parse config-sync direction ---
function Resolve-SyncDirectionArg {
    param([string[]]$RawArgs)

    $directionArg = $null
    foreach ($a in $RawArgs) {
        if ($a -eq '--') { continue }
        if ($a -eq '1' -or $a -eq '2') {
            return $a
        }
        if (-not [string]::IsNullOrWhiteSpace($a)) {
            return $a
        }
    }

    return $null
}

function Format-RepoDisplay {
    param([string]$Repo)

    if ($Repo.StartsWith('./')) {
        return $Repo
    }
    return "./$Repo"
}

function Resolve-SyncDirection {
    param(
        [string]$DirectionArg,
        [string]$Example = 'Example: vpr sync 2'
    )

    if ($DirectionArg -eq '1' -or $DirectionArg -eq '2') {
        return $DirectionArg
    }

    if (Test-SyncDispatchMode) {
        Write-ErrorAndExit "Sync direction missing`n$Example"
    }

    if (-not [string]::IsNullOrWhiteSpace($DirectionArg)) {
        Write-ErrorAndExit "Invalid sync direction; use 1 or 2`n$Example"
    }

    $dirScript = Join-Path $PSScriptRoot 'sync-direction.mjs'
    $hint = (& node $dirScript --hint 2>$null)
    if ([string]::IsNullOrWhiteSpace($hint)) {
        $hint = '1=back up config to repository, 2=restore config locally'
    }

    if (-not (Test-InteractivePrompt)) {
        Write-ErrorAndExit "Pass a direction in non-interactive environments: $hint`n$Example"
    }

    $choice = & node $dirScript
    $choice = "$choice".Trim()
    if ($LASTEXITCODE -ne 0 -or ($choice -ne '1' -and $choice -ne '2')) {
        Write-ErrorAndExit "Pass a direction in non-interactive environments: $hint`n$Example"
    }
    return $choice
}

function Test-SyncDispatchMode {
    return $env:SYNC_FROM_DISPATCH -eq '1'
}

function Test-SkipSyncSelect {
    if ($env:SYNC_SELECT_ALL -eq '1') {
        return $true
    }
    return -not (Test-InteractivePrompt)
}

function Read-SyncItemsFromPairsFile {
    param([string]$PairsFile)

    $selected = @()
    foreach ($line in [System.IO.File]::ReadAllLines($PairsFile)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line.Split("`t")
        $encoding = ''
        if ($parts.Count -gt 3) { $encoding = $parts[3] }
        $selected += [PSCustomObject]@{
            local    = $parts[0]
            repo     = $parts[1]
            backup   = ($parts[2] -eq '1')
            encoding = $encoding
        }
    }
    return $selected
}

function Get-SyncItemsFiltered {
    param(
        [string[]]$Scopes,
        [string]$Direction
    )

    if ($env:SYNC_FILTERED_PAIRS -and (Test-Path $env:SYNC_FILTERED_PAIRS)) {
        try {
            $selected = Read-SyncItemsFromPairsFile $env:SYNC_FILTERED_PAIRS
            if ($selected.Count -eq 0) {
                Write-ErrorAndExit 'No configuration items to sync'
            }
            return $selected
        }
        finally {
            Remove-Item $env:SYNC_FILTERED_PAIRS -Force -ErrorAction SilentlyContinue
            Remove-Item Env:SYNC_FILTERED_PAIRS -ErrorAction SilentlyContinue
        }
    }

    $items = @()
    foreach ($s in $Scopes) {
        $manifest = Read-Manifest -Scope $s
        foreach ($item in $manifest.sync.toRepo) {
            if ($env:SYNC_PROFILE -eq 'lite' -and $item.PSObject.Properties['lite'] -and $item.lite -eq $false) {
                continue
            }
            if ($Direction -eq '1' -and $item.PSObject.Properties['restoreOnly'] -and $item.restoreOnly -eq $true) {
                continue
            }
            $items += [PSCustomObject]@{
                local    = $item.local
                repo     = $item.repo
                backup   = [bool]$item.backup
                encoding = [string]$item.encoding
            }
        }
    }

    if (Test-SyncDispatchMode) {
        if (Test-SkipSyncSelect) {
            return $items
        }
        Write-ErrorAndExit 'Selected-file list missing; run through vpr sync'
    }

    if (Test-SkipSyncSelect) {
        return $items
    }

    $pairsFile = [System.IO.Path]::GetTempFileName()
    $filteredFile = [System.IO.Path]::GetTempFileName()
    try {
        $lines = foreach ($item in $items) {
            $backupFlag = if ($item.backup) { '1' } else { '0' }
            "$($item.local)`t$($item.repo)`t$backupFlag`t$($item.encoding)"
        }
        [System.IO.File]::WriteAllLines($pairsFile, $lines)

        if (Test-InteractivePrompt) {
            $env:SYNC_INTERACTIVE = '1'
        }

        $scriptPath = Join-Path $PSScriptRoot 'sync-select.mjs'
        & node $scriptPath $Direction $pairsFile $filteredFile
        Write-SyncSelectError

        $selected = Read-SyncItemsFromPairsFile $filteredFile
        if ($selected.Count -eq 0) {
            Write-ErrorAndExit 'No configuration items to sync'
        }
        return $selected
    }
    finally {
        Remove-Item Env:SYNC_INTERACTIVE -ErrorAction SilentlyContinue
        Remove-Item $pairsFile, $filteredFile -Force -ErrorAction SilentlyContinue
    }
}

# --- Configuration sync entry point ---
function Invoke-ManifestSync {
    param(
        [string]$Scope,
        [string]$DirectionArg
    )

    $scopes = Get-SyncScopes $Scope

    $example = 'Example: vpr sync 2'
    $direction = Resolve-SyncDirection -DirectionArg $DirectionArg -Example $example
    $items = Get-SyncItemsFiltered -Scopes $scopes -Direction $direction
    $total = $items.Count

    Write-SyncProgressHint -Direction $direction -Total $total

    switch ($direction) {
        '1' {
            $i = 0
            foreach ($item in $items) {
                $i++
                $local = Get-ExpandedPath $item.local
                $repo = Join-Path $Script:ProjectRoot $item.repo
                $repoDir = Split-Path $repo -Parent
                if (-not (Test-Path $repoDir)) {
                    New-Item -ItemType Directory -Path $repoDir -Force | Out-Null
                }
                try {
                    Copy-FileDataOnly $local $repo
                } catch {
                    Write-ErrorAndExit $_.Exception.Message
                }
                Write-Backup "[$i/$total] Backed up $(Format-RepoDisplay $item.repo)"
            }
            Write-Info 'Configuration backed up to the repository'
        }
        '2' {
            $i = 0
            foreach ($item in $items) {
                $i++
                $local = Get-ExpandedPath $item.local
                $repo = Join-Path $Script:ProjectRoot $item.repo
                if ($item.backup) {
                    $bakName = Backup-File $item.local '~/.backup'
                    if ($bakName) {
                        Write-Backup "[$i/$total] Backed up $(Format-LocalDisplay $item.local) -> ~/.backup/$bakName"
                    }
                }
                $localDir = Split-Path $local -Parent
                if (-not (Test-Path $localDir)) {
                    New-Item -ItemType Directory -Path $localDir -Force | Out-Null
                }
                try {
                    Copy-FileDataOnly $repo $local -Encoding $item.encoding
                } catch {
                    Write-ErrorAndExit $_.Exception.Message
                }
                Write-Backup "[$i/$total] Restored $(Format-LocalDisplay $item.local)"
            }
            Write-Info 'Configuration restored locally'
        }
        default {
            Write-ErrorAndExit 'Invalid selection'
        }
    }
}
