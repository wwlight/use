# Import Scoop backup using the active mirror for bucket Sources.
# Usage: import-backup.ps1 [lite|full|/path/to/backup.json]
param(
    [Parameter(Position = 0)]
    [string]$ProfileOrPath = ''
)

. (Join-Path $PSScriptRoot 'utils.ps1')
. (Join-Path $PSScriptRoot 'accel.ps1')

Assert-TargetOs windows

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-ErrorAndExit 'Scoop is not installed. Run: vpr pm'
}

$manifest = Read-Manifest

$scoopBackupRel = $null
if (-not [string]::IsNullOrWhiteSpace($ProfileOrPath)) {
    if (Test-Path -LiteralPath $ProfileOrPath) {
        $scoopBackup = (Resolve-Path -LiteralPath $ProfileOrPath).Path
    }
    else {
        $profileName = $ProfileOrPath
        if ($profileName -match '^--(.+)$') { $profileName = $Matches[1] }
        $artifactKey = [string]$manifest.profileArtifacts.$profileName
        if ([string]::IsNullOrWhiteSpace($artifactKey)) {
            Write-ErrorAndExit "Could not resolve profile artifact: $profileName"
        }
        $scoopBackupRel = [string]$manifest.$artifactKey
        if ([string]::IsNullOrWhiteSpace($scoopBackupRel)) {
            Write-ErrorAndExit "Could not resolve profile artifact: $profileName"
        }
        $scoopBackup = Join-Path $Script:ProjectRoot "$scoopBackupRel".Trim()
    }
}
else {
    $scoopBackupRel = [string]$manifest.scoopBackup
    if ([string]::IsNullOrWhiteSpace($scoopBackupRel)) {
        $scoopBackupRel = 'configs/windows/scoop/backup.json'
    }
    $scoopBackup = Join-Path $Script:ProjectRoot $scoopBackupRel
}

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
    Invoke-QuietHost { scoop import $importFile }
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Scoop app restore failed!' }
}
finally {
    if ($importFile -ne $scoopBackup -and (Test-Path -LiteralPath $importFile)) {
        Remove-Item -LiteralPath $importFile -Force -ErrorAction SilentlyContinue
    }
}
