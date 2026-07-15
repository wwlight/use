$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest -Scope common

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warn 'git 未安装，跳过 git 配置'
    return
}

git config --global init.defaultBranch $manifest.git.defaultBranch
git config --global core.ignorecase $($manifest.git.ignorecase.ToString().ToLower())
git config --global --replace-all safe.directory $manifest.git.safeDirectory
git config --global credential.helper $manifest.git.credentialHelper

$userName = git config --global --get user.name 2>$null
$userEmail = git config --global --get user.email 2>$null

if ($userName -and $userEmail) {
    Write-Info 'git 用户名和邮箱已配置，跳过'
}
elseif (-not (Test-InteractivePrompt)) {
    Write-Info '非交互环境，跳过 git 用户名和邮箱配置'
}
else {
    $skipConfig = Read-Host '是否跳过 git 用户名和邮箱配置？(y/n) [默认 n]'
    if ([string]::IsNullOrWhiteSpace($skipConfig)) { $skipConfig = 'n' }

    if ($skipConfig -ne 'y' -and $skipConfig -ne 'Y') {
        $username = Read-Host '请输入 Git 用户名'
        git config --global user.name $username

        $email = Read-Host '请输入 Git 邮箱'
        git config --global user.email $email
    }
}
