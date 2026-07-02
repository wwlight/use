$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest -Scope common

if (Get-Command vp -ErrorAction SilentlyContinue) {
    Write-Info 'vite.plus 已安装，跳过'
    exit 0
}

Write-Info '正在安装 vite.plus...'
$ErrorActionPreference = 'Stop'
irm $manifest.vitePlus.installUrlPs1 | iex
Write-Info 'vite.plus 安装成功'
