param(
    [switch]$Update
)

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest -Scope common

Write-Info 'Installing Zsh plugins...'
$pluginsDirEntry = & node (Join-Path $ScriptDir 'lib/manifest-config.mjs') zsh-plugins-dir
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($pluginsDirEntry)) {
    Write-ErrorAndExit 'Could not read zshPluginsDir'
}
$pluginsDir = Get-ExpandedPath "$pluginsDirEntry".Trim()
if (-not (Test-Path $pluginsDir)) {
    New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
}

foreach ($plugin in $manifest.zshPlugins) {
    $targetPath = Join-Path $pluginsDir $plugin.name
    Sync-GitRepoPlugin -Repo $plugin.repo -TargetPath $targetPath -Name $plugin.name -Update:$Update
}

$global:LASTEXITCODE = 0
