param([string]$Direction)

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest -Scope common
$direction = Get-SyncDirection $Direction `
    '示例: npm run common:sync -- 2 或 vpr common:sync 2' `
    '1) 从本地目录拷贝到 common 目录' `
    '2) 从 common 目录拷贝到本地目录'

Invoke-ManifestSync -Manifest $manifest -Direction $direction

Write-Host '操作完成！'
