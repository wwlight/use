# Scoop bootstrap install (fetch installer + rewrite GitHub URLs). Requires urls.ps1.

function Get-ScoopInstallerBootstrapUrls {
    # Official Scoop installer hardcodes these bootstrap URLs.
    return @(
        'https://github.com/ScoopInstaller/Scoop/archive/master.zip',
        'https://github.com/ScoopInstaller/Main/archive/master.zip',
        'https://github.com/ScoopInstaller/Scoop.git',
        'https://github.com/ScoopInstaller/Main.git'
    )
}

function Rewrite-ScoopInstallerGithubUrls {
    param(
        [string]$Script,
        [string]$Prefix,
        $AllPrefixes
    )

    if ([string]::IsNullOrWhiteSpace($Script) -or [string]::IsNullOrWhiteSpace($Prefix)) {
        return $Script
    }

    # Narrow rewrite: Scoop + Main bucket clone/zip only.
    $targets = @(Get-ScoopInstallerBootstrapUrls) | Sort-Object { $_.Length } -Descending
    $rewritten = 0
    foreach ($bare in $targets) {
        $mirrored = Join-ScoopMirrorUrl -Url $bare -Prefix $Prefix -AllPrefixes $AllPrefixes
        if ($mirrored -eq $bare) { continue }
        if ($Script.Contains($bare)) {
            $Script = $Script.Replace($bare, $mirrored)
            $rewritten++
        }
    }

    # A non-zero rewrite count already guarantees a mirrored Scoop/Main URL is present.
    if ($rewritten -eq 0) {
        throw 'Scoop installer bootstrap URLs were not rewritten; refusing to run against upstream GitHub'
    }

    return $Script
}

function Invoke-ScoopInstallScriptWithFallback {
    param(
        $Settings,
        [string]$PreferredPrefix = $null,
        # Prefer [ref] over return: installer Write-Output must never join into ActivePrefix.
        [Parameter(Mandatory)]
        [ref]$OutPrefix
    )

    $url = [string]$Settings.installScript
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-ErrorAndExit 'scoopAccel.installScript is empty'
    }

    $prefixes = @(Get-ScoopMirrorPrefixes)
    $attempts = @(Get-ScoopMirrorFetchAttempts -Url $url -Prefixes $prefixes -PreferredPrefix $PreferredPrefix)
    if ($attempts.Count -eq 0) {
        Write-ErrorAndExit 'No Scoop installer URL candidates'
    }

    $OutPrefix.Value = ''
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($attempt in $attempts) {
        $label = Format-ScoopMirrorActiveLabel -ActivePrefix $attempt.Prefix
        Write-Detail "Installing Scoop via $label ..."
        try {
            $script = [string](Invoke-RestMethod -Uri $attempt.Url -TimeoutSec 15)
            if ([string]::IsNullOrWhiteSpace($script)) {
                throw 'Empty installer response'
            }
            if ($script -notmatch 'function\s+Install-Scoop' -and $script -notmatch 'SCOOP_PACKAGE_GIT_REPO') {
                throw 'Response does not look like the Scoop installer'
            }

            # Mirror fetch alone is not enough: rewrite Scoop/Main clone+zip URLs too.
            if (-not [string]::IsNullOrWhiteSpace($attempt.Prefix)) {
                $script = Rewrite-ScoopInstallerGithubUrls -Script $script -Prefix $attempt.Prefix -AllPrefixes $prefixes
            }

            # Concatenate (do not interpolate) so installer $-variables stay intact.
            # Scoop Write-InstallInfo → Write-Output: discard (never join into ActivePrefix / host spam).
            $expression = if (Test-Administrator) {
                '& { ' + $script + ' } -RunAsAdmin'
            }
            else {
                $script
            }
            Invoke-QuietHost { Invoke-Expression $expression | Out-Null }

            # Persist the source that actually installed Scoop (may differ from selection after fallback).
            $successPrefix = Resolve-ScoopKnownMirrorPrefix -Prefix $attempt.Prefix -Prefixes $prefixes
            $successLabel = Format-ScoopMirrorActiveLabel -ActivePrefix $successPrefix
            Write-Detail "Scoop installed ($successLabel)" -Kind success
            $OutPrefix.Value = $successPrefix
            return
        }
        catch {
            $msg = $_.Exception.Message
            Write-Warn "Installer failed ($label): $msg"
            [void]$errors.Add("${label}: $msg")
        }
    }

    $detail = ($errors -join '; ')
    Write-ErrorAndExit "Scoop installation failed after trying all sources: $detail"
}
