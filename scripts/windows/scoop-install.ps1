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
    Show-ScoopMirrorUsage -Accel $accel
    exit 0
}

$activePrefix = Resolve-ScoopMirrorSelection -Accel $accel -Choice $Mirror
Write-Info "已选择加速代理: $(Format-ScoopMirrorActiveLabel -ActivePrefix $activePrefix)"

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Info 'scoop 未安装，正在自动安装...'

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
        Write-ErrorAndExit "scoop 安装失败: $($_.Exception.Message)"
    }

    $env:PATH = "$scoopDir\shims;$env:PATH"

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'scoop 安装后当前会话仍无法识别命令，请新开终端后重新运行安装'
    }

    Write-Info 'scoop 安装成功'
}
else {
    Write-Info 'scoop 已安装'
    if (-not $env:SCOOP) {
        $env:SCOOP = $scoopDir
    }
}

Enable-ScoopAccel -Manifest $manifest -ActivePrefix $activePrefix -SkipAria2

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Info '正在安装 git...'
    scoop install git
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit 'git 安装失败'
    }
}

Install-ScoopAria2Accel -Accel $accel
