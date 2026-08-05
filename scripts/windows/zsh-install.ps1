param()

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

Assert-TargetOs windows

$manifest = Read-Manifest

function Get-GitPath {
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Scoop is not installed; install Scoop first'
    }

    $gitPath = (scoop prefix git).Trim()
    if ([string]::IsNullOrWhiteSpace($gitPath) -or -not (Test-Path $gitPath)) {
        Write-ErrorAndExit 'Could not locate Git'
    }

    return $gitPath
}

function Get-ZshExePath {
    param([string]$GitPath)

    return Join-Path $GitPath 'usr\bin\zsh.exe'
}

function Test-ZshInstalled {
    param([string]$GitPath)

    return Test-Path (Get-ZshExePath $GitPath)
}

function Remove-PathSafe {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return
    }

    Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Install-ZshForGit {
    param(
        $ZshInstall,
        [string]$GitPath
    )

    $workDir = Get-ExpandedPath $ZshInstall.workDir
    $tempExtractDir = Join-Path $workDir $ZshInstall.tempExtractDir
    $cpErrorLog = Join-Path $workDir $ZshInstall.cpErrorLog
    $zipFile = Join-Path $workDir $ZshInstall.archiveName
    $tarFile = Join-Path $workDir ($ZshInstall.archiveName -replace '\.zst$')

    Write-Step 'Step 1/6: Downloading the Zsh archive...'
    & curl.exe --ssl-no-revoke -L $ZshInstall.downloadUrl -o $zipFile
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit 'Failed to download the Zsh archive'
    }
    Write-Info "Download complete: $zipFile"

    Write-Step 'Step 2/6: Locating the Git installation...'
    Write-Info "Git path: $GitPath"
    Write-Host ''

    Write-Step 'Step 3/6: Checking the 7z tool...'
    if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
        Remove-PathSafe $zipFile
        Write-ErrorAndExit '7z command not found; install 7-Zip'
    }
    Write-Info '7z is available'

    Write-Step 'Step 4/6: Extracting the .zst file...'
    Remove-PathSafe $tempExtractDir
    New-Item -ItemType Directory -Path $tempExtractDir -Force | Out-Null

    & 7z x "-o$workDir" $zipFile
    if ($LASTEXITCODE -ne 0) {
        Remove-PathSafe $zipFile
        Remove-PathSafe $tempExtractDir
        Write-ErrorAndExit 'Failed to extract the .zst file'
    }

    if (-not (Test-Path $tarFile)) {
        Remove-PathSafe $zipFile
        Remove-PathSafe $tempExtractDir
        Write-ErrorAndExit 'Extracted .tar file not found'
    }
    Write-Info '.zst extraction complete'

    Write-Step 'Step 5/6: Extracting the .tar file and moving files...'
    & 7z x "-o$tempExtractDir" $tarFile
    if ($LASTEXITCODE -ne 0) {
        Remove-PathSafe $zipFile
        Remove-PathSafe $tarFile
        Remove-PathSafe $tempExtractDir
        Write-ErrorAndExit 'Failed to extract the .tar file'
    }
    Write-Info '.tar extraction complete'

    try {
        Copy-Item -Path (Join-Path $tempExtractDir '*') -Destination $gitPath -Recurse -Force -ErrorAction Stop
        Write-Info 'Files moved'
        Remove-PathSafe $cpErrorLog
    }
    catch {
        $_ | Out-File -FilePath $cpErrorLog -Encoding utf8
        Remove-PathSafe $zipFile
        Remove-PathSafe $tarFile
        Remove-PathSafe $tempExtractDir
        Write-ErrorAndExit "Move failed; see details: $cpErrorLog"
    }

    Write-Step 'Step 6/6: Cleaning temporary files...'
    Remove-PathSafe $zipFile
    Remove-PathSafe $tarFile
    Remove-PathSafe $tempExtractDir

    Write-Info 'Zsh installation complete!'
}

$gitPath = Get-GitPath
$zshAlreadyInstalled = Test-ZshInstalled $gitPath

if (-not $zshAlreadyInstalled) {
    Install-ZshForGit -ZshInstall $manifest.zshInstall -GitPath $gitPath
}
else {
    Write-Info 'Zsh is already installed; skipping'
}
