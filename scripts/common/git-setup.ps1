$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest -Scope common

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warn 'Git is not installed; skipping Git configuration'
    return
}

git config --global init.defaultBranch $manifest.git.defaultBranch
git config --global core.ignorecase $($manifest.git.ignorecase.ToString().ToLower())
git config --global --replace-all safe.directory $manifest.git.safeDirectory
git config --global credential.helper $manifest.git.credentialHelper

$userName = git config --global --get user.name 2>$null
$userEmail = git config --global --get user.email 2>$null

if ($userName -and $userEmail) {
    Write-Info 'Git username and email are already configured; skipping'
}
elseif (-not (Test-InteractivePrompt)) {
    Write-Info 'Non-interactive environment; skipping Git username and email configuration'
}
else {
    $skipConfig = Read-Host 'Skip Git username and email configuration? (y/n) [default: n]'
    if ([string]::IsNullOrWhiteSpace($skipConfig)) { $skipConfig = 'n' }

    if ($skipConfig -ne 'y' -and $skipConfig -ne 'Y') {
        $username = Read-Host 'Enter Git username'
        if ([string]::IsNullOrWhiteSpace($username)) {
            Write-ErrorAndExit 'Git username was not provided'
        }
        git config --global user.name $username

        $email = Read-Host 'Enter Git email'
        if ([string]::IsNullOrWhiteSpace($email)) {
            Write-ErrorAndExit 'Git email was not provided'
        }
        git config --global user.email $email
    }
}
