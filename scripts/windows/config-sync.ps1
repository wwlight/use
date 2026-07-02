param([string]$Direction)

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

Invoke-ManifestSync -Scope windows -Arg $Direction -BackupLocal @('~/.zshrc')
