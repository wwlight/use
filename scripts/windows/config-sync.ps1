param([string]$Direction)

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest
$direction = Get-SyncDirection $Direction `
    '示例: npm run win:sync -- 2 或 vpr win:sync 2' `
    '1) 从本地目录拷贝到 windows 目录' `
    '2) 从 windows 目录拷贝到本地目录'

Invoke-ManifestSync -Manifest $manifest -Direction $direction -BackupLocal '~/.zshrc'

Write-Host '操作完成！'
