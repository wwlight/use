# Zip Scoop → git conversion, download hook, bucket remotes. Requires urls.ps1.

function Get-ScoopLibDownloadPath {
    $scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { (Read-Manifest).scoopDir }
    $download = Join-Path $scoopRoot 'apps\scoop\current\lib\download.ps1'
    if (-not (Test-Path $download)) {
        Write-ErrorAndExit "Scoop download.ps1 not found: $download"
    }
    return $download
}

function Invoke-ScoopMirrorAccelFilterInit {
    param(
        [string]$FailureMessage
    )

    $cliJs = Join-Path (Get-ScoopConfigDir) 'mirror\cli.js'
    if (-not (Test-Path -LiteralPath $cliJs)) {
        Write-ErrorAndExit "mirror/cli.js not found: $cliJs"
    }

    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-ErrorAndExit 'Node.js is required for scoop mirror repair'
    }

    $output = & $node.Source $cliJs repair 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $FailureMessage }
        else { $detail = "${FailureMessage}: $detail" }
        Write-ErrorAndExit $detail
    }
}

function Test-ScoopCoreGitRepo {
    if ([string]::IsNullOrWhiteSpace($env:SCOOP)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $env:SCOOP 'apps\scoop\current\.git'))
}

function Test-ScoopFormalRepairReady {
    return [bool](Get-Command git.exe -ErrorAction SilentlyContinue) -and (Test-ScoopCoreGitRepo)
}

function Update-ScoopSessionPath {
    if ([string]::IsNullOrWhiteSpace($env:SCOOP)) { return }
    $env:PATH = "$env:SCOOP\shims;$env:SCOOP\apps\scoop\current\bin;$env:PATH"
}

# Append one dot-source line; keep original bytes/BOM/encoding untouched (scoop update discards this file).
function Install-ScoopDownloadHookTemporary {
    $hookHelper = Join-Path (Get-ScoopConfigDir) 'mirror\hook.ps1'
    if (-not (Test-Path -LiteralPath $hookHelper)) {
        Write-ErrorAndExit "mirror/hook.ps1 not found: $hookHelper (deploy mirror files first)"
    }

    $download = Get-ScoopLibDownloadPath
    $bytes = [System.IO.File]::ReadAllBytes($download)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    # Scoop's download.ps1 is UTF-8; marker / path check is enough for idempotent append.
    if ($text.Contains('mirror\hook.ps1') -or $text.Contains('mirror/hook.ps1')) {
        return
    }

    $useCrlf = $false
    for ($i = 0; $i -lt ($bytes.Length - 1); $i++) {
        if ($bytes[$i] -eq 13 -and $bytes[$i + 1] -eq 10) {
            $useCrlf = $true
            break
        }
    }
    $nl = if ($useCrlf) { "`r`n" } else { "`n" }
    $prefix = ''
    if ($bytes.Length -eq 0 -or $bytes[$bytes.Length - 1] -ne 10) {
        $prefix = $nl
    }
    $hookBlock = @(
        '$__scoopCfg = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME ''scoop'' } else { Join-Path $env:USERPROFILE ''.config\scoop'' }'
        '. (Join-Path $__scoopCfg ''mirror\hook.ps1'')'
    ) -join $nl
    $append = [System.Text.Encoding]::UTF8.GetBytes($prefix + $hookBlock + $nl)
    $out = New-Object byte[] ($bytes.Length + $append.Length)
    [System.Buffer]::BlockCopy($bytes, 0, $out, 0, $bytes.Length)
    [System.Buffer]::BlockCopy($append, 0, $out, $bytes.Length, $append.Length)
    [System.IO.File]::WriteAllBytes($download, $out)
}

function Install-ScoopDownloadHook {
    if (-not (Test-ScoopFormalRepairReady)) {
        Install-ScoopDownloadHookTemporary
        return
    }

    Invoke-ScoopMirrorAccelFilterInit -FailureMessage 'Could not install the Scoop download acceleration hook'
    Write-Detail 'Scoop mirror hook and clean-worktree filter are ready' -Kind done
}

function Install-ScoopBootstrapApps {
    param(
        [string[]]$Apps = @('7zip', 'git')
    )

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Scoop is required to install bootstrap apps'
    }

    foreach ($app in $Apps) {
        $commandName = if ($app -eq '7zip') { '7z' } else { $app }
        if (Get-Command $commandName -ErrorAction SilentlyContinue) {
            Write-Detail "$app is already available; skipping" -Kind skip
            continue
        }

        Write-Detail "Installing $app via Scoop..."
        # --no-update-scoop: Scoop's pre-install update needs Git and aborts on a zip bootstrap.
        Assert-ScoopWorktreeClean
        Invoke-QuietHost { scoop install --no-update-scoop $app }
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorAndExit "Failed to install $app via Scoop"
        }
        Update-ScoopSessionPath
        Write-Detail "$app installed via Scoop" -Kind success
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Git is still unavailable after scoop install git'
    }
}

function Get-ScoopKnownMainBucketUrl {
    $bucketsJson = Join-Path $env:SCOOP 'apps\scoop\current\buckets.json'
    if (Test-Path -LiteralPath $bucketsJson) {
        try {
            $data = Get-Content -LiteralPath $bucketsJson -Raw -Encoding UTF8 | ConvertFrom-Json
            $url = [string]$data.main
            if (-not [string]::IsNullOrWhiteSpace($url)) { return $url.Trim() }
        }
        catch { }
    }
    return 'https://github.com/ScoopInstaller/Main'
}

# Convert zip main → git via mirrored URL BEFORE scoop update.
# scoop update otherwise rm's main and re-adds from official GitHub (no scoop_repo).
function Ensure-ScoopMainBucketGit {
    param(
        [string]$ActivePrefix = '',
        $Prefixes
    )

    $mainRoot = Join-Path $env:SCOOP 'buckets\main'
    $mainGit = Join-Path $mainRoot '.git'
    if (Test-Path -LiteralPath $mainGit) {
        return
    }

    if ($null -eq $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes }
    $ActivePrefix = Resolve-ScoopKnownMirrorPrefix -Prefix $ActivePrefix -Prefixes $Prefixes -Quiet
    $bare = Get-ScoopKnownMainBucketUrl
    $url = Join-ScoopMirrorUrl -Url $bare -Prefix $ActivePrefix -AllPrefixes $Prefixes
    $label = Format-ScoopMirrorActiveLabel -ActivePrefix $ActivePrefix
    Write-Detail "Ensuring main bucket as git repo via $label ..."

    if (Test-Path -LiteralPath $mainRoot) {
        Invoke-QuietHost { scoop bucket rm main *>$null }
        if (Test-Path -LiteralPath $mainRoot) {
            Remove-Item -LiteralPath $mainRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $mainRoot) {
        Write-ErrorAndExit "Could not remove zip main bucket at $mainRoot"
    }

    Invoke-QuietHost { scoop bucket add main $url }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $mainGit)) {
        Write-ErrorAndExit (
            "Failed to add main bucket via $label ($url). " +
            'Check network/mirror, then rerun: vpr pm'
        )
    }
    Write-Detail "main bucket now a git repo ($label)" -Kind success
}

function Get-ScoopCoreBranch {
    $branch = ''
    try {
        $raw = scoop config scoop_branch 2>$null
        if ($null -ne $raw) {
            $branch = ([string](@($raw) | Select-Object -Last 1)).Trim()
        }
    }
    catch { }
    if ([string]::IsNullOrWhiteSpace($branch)) { return 'master' }
    return $branch
}

# Finish zip Scoop → git when scoop update cloned to apps\scoop\new but could not rename
# (Windows: current is often locked by the running scoop/pwsh session).
function Complete-ScoopCoreGitConversion {
    param([string]$RepoUrl)

    $scoopApps = Join-Path $env:SCOOP 'apps\scoop'
    $current = Join-Path $scoopApps 'current'
    $newDir = Join-Path $scoopApps 'new'
    $oldDir = Join-Path $scoopApps 'old'
    $currentGit = Join-Path $current '.git'
    if (Test-Path -LiteralPath $currentGit) { return $true }

    $newScoop = Join-Path $newDir 'bin\scoop.ps1'
    if (-not (Test-Path -LiteralPath $newScoop)) {
        if ([string]::IsNullOrWhiteSpace($RepoUrl)) { return $false }
        if (Test-Path -LiteralPath $newDir) {
            Remove-Item -LiteralPath $newDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        $branch = Get-ScoopCoreBranch
        Write-Detail "Cloning Scoop core ($branch) ..."
        git clone -q --branch $branch --single-branch $RepoUrl $newDir 1>$null 2>$null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $newScoop)) {
            if (Test-Path -LiteralPath $newDir) {
                Remove-Item -LiteralPath $newDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            return $false
        }
    }

    for ($i = 0; $i -lt 3; $i++) {
        try {
            if (Test-Path -LiteralPath $oldDir) {
                Remove-Item -LiteralPath $oldDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            Rename-Item -LiteralPath $current -NewName 'old' -ErrorAction Stop
            Rename-Item -LiteralPath $newDir -NewName 'current' -ErrorAction Stop
            Remove-Item -LiteralPath $oldDir -Recurse -Force -ErrorAction SilentlyContinue
            Update-ScoopSessionPath
            return (Test-Path -LiteralPath (Join-Path $scoopApps 'current\.git'))
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    # Folder still locked: adopt .git into current without renaming the directory.
    $newGit = Join-Path $newDir '.git'
    if (-not (Test-Path -LiteralPath $newGit)) { return $false }

    Write-Warn 'Scoop folder in use; adopting git metadata into current install (no directory rename)'
    if (Test-Path -LiteralPath $currentGit) {
        Remove-Item -LiteralPath $currentGit -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath $newGit -Destination $currentGit -Recurse -Force
    git -C $current reset --hard HEAD 2>$null | Out-Null
    Remove-Item -LiteralPath $newDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $oldDir) {
        Remove-Item -LiteralPath $oldDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Update-ScoopSessionPath
    return (Test-Path -LiteralPath $currentGit)
}

function Ensure-ScoopGitRepositories {
    param(
        [string]$ActivePrefix = '',
        $Settings
    )

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Git is required to convert Scoop into a git repository'
    }
    if (-not $env:SCOOP) {
        Write-ErrorAndExit 'SCOOP environment variable is not set'
    }

    $scoopGit = Join-Path $env:SCOOP 'apps\scoop\current\.git'
    $mainGit = Join-Path $env:SCOOP 'buckets\main\.git'
    if ((Test-Path -LiteralPath $scoopGit) -and (Test-Path -LiteralPath $mainGit)) {
        Write-Detail 'Scoop and main bucket are already git repositories'
        return
    }

    if (-not $Settings) { $Settings = Get-ScoopMirrorSettings }
    if ([string]::IsNullOrWhiteSpace($ActivePrefix)) {
        $ActivePrefix = Get-ScoopMirrorActivePrefix
    }
    $prefixes = Get-ScoopMirrorPrefixes
    $ActivePrefix = Resolve-ScoopKnownMirrorPrefix -Prefix $ActivePrefix -Prefixes $prefixes

    $expectedRepo = Get-ScoopRepoTargetUrl -ActivePrefix $ActivePrefix -Settings $Settings -Prefixes $prefixes
    Repair-ScoopRepoConfig -ExpectedUrl $expectedRepo

    # Must run before scoop update so it does not wipe zip main and clone official GitHub.
    Ensure-ScoopMainBucketGit -ActivePrefix $ActivePrefix -Prefixes $prefixes

    if (-not (Test-Path -LiteralPath $scoopGit)) {
        Write-Detail 'Running scoop update to convert Scoop into a git repository...'
        Invoke-QuietHost { scoop update }
        Update-ScoopSessionPath
    }

    if (-not (Test-Path -LiteralPath $scoopGit)) {
        Write-Detail 'Completing Scoop core git conversion after folder-in-use / partial update...'
        if (-not (Complete-ScoopCoreGitConversion -RepoUrl $expectedRepo)) {
            Write-ErrorAndExit (
                'Scoop is still missing .git after scoop update. ' +
                "If apps\scoop\new exists, close other Scoop shells and rename current→old, new→current; then rerun."
            )
        }
    }
    Write-Detail 'Scoop core is now a git repository' -Kind success

    if (-not (Test-Path -LiteralPath $mainGit)) {
        Write-ErrorAndExit 'main bucket is still missing .git after mirrored add + scoop update'
    }
}

function Assert-ScoopWorktreeClean {
    if (-not (Test-ScoopFormalRepairReady)) { return }
    Invoke-ScoopMirrorAccelFilterInit -FailureMessage 'Scoop package operation aborted because its tracked worktree is not clean'
}

function Set-ScoopBucketMirrors {
    param(
        [string]$ActivePrefix,
        $Prefixes
    )

    if (-not (Test-ScoopFormalRepairReady)) {
        return
    }

    if (-not $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes }
    $bucketsRoot = Join-Path $env:SCOOP 'buckets'
    if (-not (Test-Path $bucketsRoot)) { return }

    Get-ChildItem $bucketsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $gitDir = Join-Path $_.FullName '.git'
        if (-not (Test-Path $gitDir)) { return }
        $origin = git -C $_.FullName remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) { return }
        $mirrored = ConvertTo-MirrorUrl -Url $origin.Trim() -Prefix $ActivePrefix -AllPrefixes $Prefixes
        if ($mirrored -ne $origin.Trim()) {
            git -C $_.FullName remote set-url origin $mirrored 2>$null | Out-Null
        }
    }
}
