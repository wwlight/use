$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

Assert-TargetOs windows

$manifest = Read-Manifest
$scoopDir = $manifest.scoopDir

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Info 'scoop 已安装，跳过'
}
else {
    Write-Info 'scoop 未安装，正在自动安装...'

    $softwareAppsDir = Get-ExpandedPath $manifest.softwareAppsDir
    if (-not (Test-Path $softwareAppsDir)) {
        New-Item -ItemType Directory -Path $softwareAppsDir -Force | Out-Null
    }

    $env:SCOOP = $scoopDir
    [Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')

    try {
        $ErrorActionPreference = 'Stop'
        if (Test-Administrator) {
            iex "& {$(irm get.scoop.sh)} -RunAsAdmin"
        }
        else {
            Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        }
    }
    catch {
        Write-ErrorAndExit "scoop 安装失败: $($_.Exception.Message)"
    }

    $env:PATH = "$scoopDir\shims;$env:PATH"

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'scoop 安装后当前会话仍无法识别命令，请新开终端后重新运行安装'
    }

    Write-Info 'scoop 安装成功'
    Write-Info '正在安装 git...'
    scoop install git
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit 'git 安装失败'
    }
}
