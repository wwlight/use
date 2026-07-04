$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$direction = Get-SyncDirection $args[0] `
    '示例: vpr sync 2' `
    '1) 备份本地配置 -> 仓库' `
    '2) 从仓库恢复配置 -> 本地'

Write-Output $direction
