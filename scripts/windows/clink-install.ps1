$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

Assert-TargetOs windows

$manifest = Read-Manifest

Write-Step 'Step 1/4: Checking Scoop installation...'
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-ErrorAndExit 'Scoop is not installed; install Scoop first'
}
Write-Info 'Scoop is installed'

Write-Step 'Step 2/4: Checking Clink installation...'
if (-not (Get-Command clink -ErrorAction SilentlyContinue)) {
    Write-Warn 'Clink is not installed; installing through Scoop...'
    scoop install clink
    if ($LASTEXITCODE -ne 0) { Write-ErrorAndExit 'Clink installation failed' }
    Write-Info 'Clink installation complete'
}
else {
    Write-Info 'Clink is already installed; skipping'
}

$clinkPath = (scoop prefix clink).Trim()
if ([string]::IsNullOrWhiteSpace($clinkPath) -or -not (Test-Path $clinkPath)) {
    Write-ErrorAndExit 'Could not locate the Clink installation'
}

$scriptsPath = Join-Path $clinkPath 'scripts'
Write-Info 'Clink installation path:'
Write-Host $clinkPath

Write-Step 'Step 3/4: Processing plugins...'
foreach ($plugin in $manifest.clinkPlugins) {
    $targetPath = Join-Path $scriptsPath $plugin.name
    Sync-GitRepoPlugin -Repo $plugin.repo -TargetPath $targetPath -Name $plugin.name -Update
}

Write-Info 'Copying the starship.lua startup plugin...'
$starshipSrc = Join-Path $Script:ProjectRoot 'configs/windows/starship.lua'
Copy-Item $starshipSrc (Join-Path $scriptsPath 'starship.lua') -Force

Write-Info 'Registering Clink scripts...'
foreach ($path in @($scriptsPath) + @($manifest.clinkPlugins | ForEach-Object { Join-Path $scriptsPath $_.name })) {
    Write-Info "Registering: $path"
    clink installscripts $path
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Failed to register $path"
    }
    else {
        Write-Info "Registered $path"
    }
}

Write-Step 'Step 4/4: Enabling Clink autorun...'
clink set tips.enable false
if ($LASTEXITCODE -ne 0) {
    Write-Warn 'Failed to set tips.enable'
}
clink autorun install -- --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Warn 'Failed to enable Clink autorun'
}
else {
    Write-Info 'Clink autorun enabled'
}

Write-Info 'Configuration complete!'
