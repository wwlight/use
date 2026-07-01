$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest
$scoopDir = $manifest.scoopDir

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Info 'Scoop 已安装，跳过'
    exit 0
}

Write-Info 'Scoop 未安装，正在自动安装...'

$softwareAppsDir = Get-ExpandedPath $manifest.softwareAppsDir
if (-not (Test-Path $softwareAppsDir)) {
    New-Item -ItemType Directory -Path $softwareAppsDir -Force | Out-Null
}

$ErrorActionPreference = 'Stop'
$env:SCOOP = $scoopDir
[Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

$env:PATH = "$scoopDir\shims;$env:PATH"

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Info 'Scoop 安装成功'
}
else {
    Write-Warn 'Scoop 已安装，但当前 shell 未识别 scoop 命令，请重新打开终端'
}
