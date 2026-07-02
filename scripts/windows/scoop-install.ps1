$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest
$scoopDir = $manifest.scoopDir
$vitePlusScript = Join-Path $ScriptDir 'common/vite-plus-install.ps1'

function Test-Administrator {
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Update-GitHubHosts {
    param([string]$HostsUrl)

    if ([string]::IsNullOrWhiteSpace($HostsUrl)) {
        Write-Warn '未配置 GitHub hosts 源，跳过 hosts 更新'
        return
    }

    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        Write-Warn '未检测到 SystemRoot，跳过 hosts 更新'
        return
    }

    if (-not (Test-Administrator)) {
        Write-Warn '当前 PowerShell 未以管理员身份运行，跳过 hosts 更新'
        Write-Warn '如 GitHub 无法连接，请以管理员身份重新运行本脚本'
        return
    }

    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $beginMarker = '# BEGIN use scoop-install github hosts'
    $endMarker = '# END use scoop-install github hosts'

    Write-Info "正在更新 GitHub hosts: $HostsUrl"
    try {
        $response = Invoke-WebRequest -Uri $HostsUrl -UseBasicParsing -TimeoutSec 20
        $hostsContent = $response.Content.Trim()
        if ([string]::IsNullOrWhiteSpace($hostsContent)) {
            Write-Warn '下载到的 GitHub hosts 内容为空，跳过更新'
            return
        }

        if (Test-Path $hostsPath) {
            Backup-File $hostsPath
            $currentContent = Get-Content $hostsPath -Raw -ErrorAction Stop
        }
        else {
            $currentContent = ''
        }

        $lineBreak = [Environment]::NewLine
        $managedBlock = ($beginMarker, $hostsContent, $endMarker) -join $lineBreak
        $pattern = "(?s)\r?\n?$([regex]::Escape($beginMarker)).*?$([regex]::Escape($endMarker))\r?\n?"

        if ($currentContent -match [regex]::Escape($beginMarker)) {
            $replacement = "$lineBreak$managedBlock$lineBreak".Replace('$', '$$')
            $updatedContent = [regex]::Replace($currentContent, $pattern, $replacement)
        }
        elseif ([string]::IsNullOrWhiteSpace($currentContent)) {
            $updatedContent = "$managedBlock$lineBreak"
        }
        else {
            $updatedContent = $currentContent.TrimEnd() + ($lineBreak * 2) + $managedBlock + $lineBreak
        }

        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($hostsPath, $updatedContent, $utf8NoBom)
        Write-Info "GitHub hosts 已更新: $hostsPath"
    }
    catch {
        Write-Warn "GitHub hosts 更新失败: $($_.Exception.Message)"
    }
}

Update-GitHubHosts $manifest.githubHostsUrl

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Info 'Scoop 已安装，跳过'
}
else {
    Write-Info 'Scoop 未安装，正在自动安装...'

    $softwareAppsDir = Get-ExpandedPath $manifest.softwareAppsDir
    if (-not (Test-Path $softwareAppsDir)) {
        New-Item -ItemType Directory -Path $softwareAppsDir -Force | Out-Null
    }

    $ErrorActionPreference = 'Stop'
    $env:SCOOP = $scoopDir
    [Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

    $env:PATH = "$scoopDir\shims;$env:PATH"

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Info 'Scoop 安装成功'
        Write-Info '正在安装 git...'
        scoop install git
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'git 安装失败'
        }
    }
    else {
        Write-Warn 'Scoop 已安装，但当前 shell 未识别 scoop 命令，请重新打开终端'
    }
}

& $vitePlusScript
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
