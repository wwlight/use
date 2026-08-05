param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$SyncArgs
)

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

Assert-TargetOs windows

$directionArg = Resolve-SyncDirectionArg $SyncArgs
$direction = Resolve-SyncDirection -DirectionArg $directionArg
Invoke-ManifestSync -Scope windows -DirectionArg $direction

if ($direction -eq '2') {
    . (Join-Path $PSScriptRoot 'scoop-accel.ps1')
    Install-ScoopMirrorAccelScript -Manifest (Read-Manifest)
}

$global:LASTEXITCODE = 0
