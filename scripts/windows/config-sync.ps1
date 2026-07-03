param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$SyncArgs
)

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$directionArg = Resolve-SyncDirectionArg $SyncArgs
Invoke-ManifestSync -Scope windows -DirectionArg $directionArg
