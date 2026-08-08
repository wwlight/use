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
    $importLabel = if (Test-ScoopQuietPm) {
        'Importing Scoop packages...'
    }
    elseif ($importFile -ne $scoopBackup) {
        "Importing buckets via active mirror: $(Format-ScoopMirrorActiveLabel -ActivePrefix $activePrefix)"
    }
    else {
        "Importing from $(Split-Path $scoopBackup -Leaf)..."
    }
    $capture = [System.Collections.Generic.List[string]]::new()
    Invoke-Spin $importLabel {
        Invoke-QuietHost -Capture $capture { scoop import $importFile }
    }
    if ($LASTEXITCODE -ne 0) {
        $logPath = Join-Path $Script:ProjectRoot 'error.log'
        $header = @(
            "scoop import failed: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')"
            "backup: $scoopBackup"
            "import: $importFile"
            ''
        )
        ($header + @($capture)) | Set-Content -LiteralPath $logPath -Encoding utf8
        Write-ErrorAndExit "Scoop app restore failed! See: $logPath"
    }
}
finally {
    if ($importFile -ne $scoopBackup -and (Test-Path -LiteralPath $importFile)) {
        Remove-Item -LiteralPath $importFile -Force -ErrorAction SilentlyContinue
    }
}
