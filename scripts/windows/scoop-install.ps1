param(
    [Parameter(Position = 0)]
    [string]$Mirror = ''
)

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')
. (Join-Path $PSScriptRoot 'scoop-accel.ps1')

Assert-TargetOs windows

while ($Mirror -eq '--') {
    if ($args.Count -gt 0) {
        $Mirror = [string]$args[0]
        $args = @($args | Select-Object -Skip 1)
    }
    else {
        $Mirror = ''
        break
    }
}
if ($Mirror -match '^--(.+)$') { $Mirror = $Matches[1] }

$manifest = Read-Manifest
$scoopDir = $manifest.scoopDir
$accel = Get-ScoopAccelConfig -Manifest $manifest

if ($Mirror -in @('-h', '--help', 'help')) {
    Show-ScoopMirrorUsage
    exit 0
}

$activePrefix = Resolve-ScoopMirrorSelection -Choice $Mirror
Write-Info "Selected mirror: $(Format-ScoopMirrorActiveLabel -ActivePrefix $activePrefix)"

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Info 'Scoop is not installed; installing automatically...'

    $softwareAppsDir = Get-ExpandedPath $manifest.softwareAppsDir
    if (-not (Test-Path $softwareAppsDir)) {
        New-Item -ItemType Directory -Path $softwareAppsDir -Force | Out-Null
    }

    $env:SCOOP = $scoopDir
    [Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')

    try {
        $ErrorActionPreference = 'Stop'
        Invoke-ScoopInstallScriptWithFallback -Accel $accel -PreferredPrefix $activePrefix
    }
    catch {
        Write-ErrorAndExit "Scoop installation failed: $($_.Exception.Message)"
    }

    $env:PATH = "$scoopDir\shims;$env:PATH"

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'Scoop is still unavailable in this session; open a new terminal and rerun the installer'
    }

    Write-Info 'Scoop installation complete'
}
else {
    Write-Info 'Scoop is already installed'
    if (-not $env:SCOOP) {
        $env:SCOOP = $scoopDir
    }
}

Enable-ScoopAccel -Manifest $manifest -ActivePrefix $activePrefix -SkipAria2

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Info 'Installing Git...'
    scoop install git
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit 'Git installation failed'
    }
}

Install-ScoopAria2Accel -Accel $accel
