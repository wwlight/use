$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

Assert-TargetOs windows

$manifest = Read-Manifest

function Update-GitHubHosts {
    param([string]$HostsUrl)

    if ([string]::IsNullOrWhiteSpace($HostsUrl)) {
        Write-Warn 'No GitHub hosts source configured; skipping hosts update'
        return
    }

    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        Write-Warn 'SystemRoot not detected; skipping hosts update'
        return
    }

    if (-not (Test-Administrator)) {
        Write-Warn 'Administrator privileges required; skipping hosts update'
        return
    }

    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $beginMarker = '# BEGIN use scoop-install github hosts'
    $endMarker = '# END use scoop-install github hosts'

    Write-Info "Updating GitHub hosts: $HostsUrl"
    try {
        $response = Invoke-WebRequest -Uri $HostsUrl -UseBasicParsing -TimeoutSec 20
        $hostsContent = $response.Content.Trim()
        if ([string]::IsNullOrWhiteSpace($hostsContent)) {
            Write-Warn 'Downloaded GitHub hosts content is empty; skipping update'
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
        Write-Info "GitHub hosts updated: $hostsPath"
    }
    catch {
        Write-Warn "GitHub hosts update failed: $($_.Exception.Message)"
    }
}

Update-GitHubHosts $manifest.githubHostsUrl
