# Import Scoop backup using the active mirror for bucket Sources.
$ScriptDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')
. (Join-Path $PSScriptRoot 'accel.ps1')

Assert-TargetOs windows

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-ErrorAndExit 'Scoop is not installed. Run: vpr pm'
}

$manifest = Read-Manifest
$scoopBackupRel = [string]$manifest.scoopBackup
if ([string]::IsNullOrWhiteSpace($scoopBackupRel)) {
    $scoopBackupRel = 'configs/windows/scoop/backup.json'
}
$scoopBackup = Join-Path $Script:ProjectRoot $scoopBackupRel
if (-not (Test-Path -LiteralPath $scoopBackup)) {
    Write-ErrorAndExit "Scoop backup file not found: $scoopBackup"
}

if (-not $env:SCOOP) {
    $env:SCOOP = [string]$manifest.scoopDir
}

$activePrefix = Get-ScoopMirrorActivePrefix
$importFile = New-ScoopMirroredImportFile -BackupPath $scoopBackup -ActivePrefix $activePrefix
try {
    if ($importFile -ne $scoopBackup) {
        Write-Info "Importing buckets via active mirror: $(Format-ScoopMirrorActiveLabel -ActivePrefix $activePrefix)"
    }
    else {
        Write-Info "Importing from $(Split-Path $scoopBackup -Leaf)..."
    }
    scoop import $importFile
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Scoop app restore failed!' }
}
finally {
    if ($importFile -ne $scoopBackup -and (Test-Path -LiteralPath $importFile)) {
        Remove-Item -LiteralPath $importFile -Force -ErrorAction SilentlyContinue
    }
}
