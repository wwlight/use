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

    $ErrorActionPreference = 'Stop'
    $env:SCOOP = $scoopDir
    [Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')

    if (Test-Administrator) {
        iex "& {$(irm get.scoop.sh)} -RunAsAdmin"
    }
    else {
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    }

    $env:PATH = "$scoopDir\shims;$env:PATH"

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Info 'scoop 安装成功'
        Write-Info '正在安装 git...'
        scoop install git
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'git 安装失败'
        }
    }
    else {
        Write-Warn 'scoop 已安装，但当前 shell 未识别 scoop 命令，请重新打开终端'
    }
}
