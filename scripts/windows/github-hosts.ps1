$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

Assert-TargetOs windows

$manifest = Read-Manifest

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
        Write-Warn '请以管理员身份运行，跳过 hosts 更新'
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
