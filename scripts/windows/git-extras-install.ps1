$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

Assert-TargetOs windows

$manifest = Read-Manifest

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) "use-git-extras-$([Guid]::NewGuid().ToString('N'))"

Write-Step 'Step 1/5: Cloning the git-extras repository to a temporary directory...'
Install-GitRepoClone -Repo $manifest.gitExtras.repo -TargetPath $workDir -Name 'git-extras'
if (-not (Test-Path (Join-Path $workDir '.git'))) {
    Write-ErrorAndExit 'Failed to clone the git-extras repository'
}

Write-Step 'Step 2/5: Entering the git-extras directory...'
Set-Location $workDir

Write-Step 'Step 3/5: Checking out the latest version...'
$latestCommit = git rev-list --tags --max-count=1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($latestCommit)) {
    Write-ErrorAndExit 'Could not resolve the latest tag commit'
}
$latestTag = git describe --tags $latestCommit
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($latestTag)) {
    Write-ErrorAndExit 'Could not resolve the latest tag'
}
git checkout $latestTag
if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Failed to check out the latest tag' }
Write-Info "Checked out version: $latestTag"

Write-Step 'Step 4/5: Installing git-extras...'
$gitPath = (scoop prefix git).Trim()
if ([string]::IsNullOrWhiteSpace($gitPath)) {
    Write-ErrorAndExit 'Could not locate Git'
}

if (Test-Path './install.cmd') {
    cmd /c "install.cmd `"$gitPath`""
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'The install command may not have completed successfully; check manually'
    }
}
else {
    Write-Warn 'install.cmd not found'
}

Write-Step 'Step 5/5: Verifying installation...'
git extras --help | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-ErrorAndExit 'git extras command verification failed; installation may be incomplete'
}
Write-Info 'Installation verified'

Write-Info 'Cleaning temporary files...'
Set-Location ([System.IO.Path]::GetTempPath())
Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Info 'git-extras installation complete!'
