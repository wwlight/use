$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-ErrorAndExit 'Git 未安装，跳过 Git 配置'
}

git config --global init.defaultBranch main
git config --global core.ignorecase false
git config --global safe.directory '*'
git config --global credential.helper store

$skipConfig = Read-Host '是否跳过 Git 用户名和邮箱配置？(y/n) [默认 n]'
if ([string]::IsNullOrWhiteSpace($skipConfig)) { $skipConfig = 'n' }

if ($skipConfig -ne 'y' -and $skipConfig -ne 'Y') {
    $username = Read-Host '请输入 Git 用户名'
    git config --global user.name $username

    $email = Read-Host '请输入 Git 邮箱'
    git config --global user.email $email
}
