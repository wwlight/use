# Write scoop-mirror / scoop-services files under $SCOOP/config.

function Write-Utf8NoBomFile {
    param(
        [string]$Path,
        [string]$Content
    )
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Install-ScoopMirrorAccelFiles {
    param(
        $Accel,
        [string]$ActivePrefix,
        $Prefixes
    )

    $scoopRoot = $env:SCOOP
    if (-not $scoopRoot) { Write-ErrorAndExit 'SCOOP environment variable is not set' }

    $mirrorDir = Join-Path $scoopRoot 'config\scoop-mirror'
    if (-not (Test-Path $mirrorDir)) {
        New-Item -ItemType Directory -Path $mirrorDir -Force | Out-Null
    }
    $libDir = Join-Path $mirrorDir 'lib'
    if (-not (Test-Path $libDir)) {
        New-Item -ItemType Directory -Path $libDir -Force | Out-Null
    }

    if (-not $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes }

    $jsonPath = Join-Path $mirrorDir 'config.json'
    $mirrors = @(
        foreach ($item in @(Get-GithubAccelMirrors)) {
            [ordered]@{
                id     = [string]$item.id
                prefix = [string]$item.prefix
            }
        }
    )
    $payload = [ordered]@{
        mirrorPrefix = @($Prefixes)
        mirrors      = $mirrors
        activePrefix = $ActivePrefix
        githubHosts  = @($Accel.githubHosts)
        scoopRepo    = [string]$Accel.scoopRepo
    }
    Write-Utf8NoBomFile -Path $jsonPath -Content (($payload | ConvertTo-Json -Depth 5) + "`n")

    $mirrorSrc = Join-Path $PSScriptRoot 'mirror'
    $hookSrc = Join-Path $mirrorSrc 'hook.ps1'
    if (-not (Test-Path $hookSrc)) {
        Write-ErrorAndExit "scoop/mirror/hook.ps1 not found: $hookSrc"
    }
    Copy-FileDataOnly -SourceFile $hookSrc -DestinationFile (Join-Path $mirrorDir 'hook.ps1') -Encoding 'utf8Bom'

    $sharedSrc = Join-Path $mirrorSrc 'shared.ps1'
    if (-not (Test-Path -LiteralPath $sharedSrc)) {
        Write-ErrorAndExit "scoop/mirror/shared.ps1 not found: $sharedSrc"
    }
    Copy-FileDataOnly -SourceFile $sharedSrc -DestinationFile (Join-Path $mirrorDir 'shared.ps1') -Encoding 'utf8Bom'

    # Drop retired PS mirror CLI (shell uses cli.mjs directly).
    $obsoleteManage = Join-Path $mirrorDir 'manage.ps1'
    if (Test-Path -LiteralPath $obsoleteManage) {
        Remove-Item -LiteralPath $obsoleteManage -Force -ErrorAction SilentlyContinue
    }

    $cliSrc = Join-Path $mirrorSrc 'cli.mjs'
    if (-not (Test-Path -LiteralPath $cliSrc)) {
        Write-ErrorAndExit "scoop/mirror/cli.mjs not found: $cliSrc"
    }
    Copy-FileDataOnly -SourceFile $cliSrc -DestinationFile (Join-Path $mirrorDir 'cli.mjs')

    $sharedLib = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\lib'))
    foreach ($name in @('menu-select.mjs', 'tty-term.mjs')) {
        $menuSrc = Join-Path $sharedLib $name
        if (-not (Test-Path -LiteralPath $menuSrc)) {
            Write-ErrorAndExit "Shared menu helper not found: $menuSrc"
        }
        Copy-FileDataOnly -SourceFile $menuSrc -DestinationFile (Join-Path $libDir $name)
    }

    Write-Info "Synced scoop-mirror helpers to $mirrorDir"
}

function Install-ScoopServicesFiles {
    $scoopRoot = $env:SCOOP
    if (-not $scoopRoot) { Write-ErrorAndExit 'SCOOP environment variable is not set' }

    $configDir = Join-Path $scoopRoot 'config'
    if (-not (Test-Path -LiteralPath $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $servicesDir = Join-Path $configDir 'scoop-services'
    if (-not (Test-Path -LiteralPath $servicesDir)) {
        New-Item -ItemType Directory -Path $servicesDir -Force | Out-Null
    }

    $dest = Join-Path $servicesDir 'manage.ps1'
    $src = Join-Path $PSScriptRoot 'services\manage.ps1'
    if (-not (Test-Path -LiteralPath $src)) {
        Write-ErrorAndExit "scoop/services/manage.ps1 not found: $src"
    }
    Copy-FileDataOnly -SourceFile $src -DestinationFile $dest -Encoding 'utf8Bom'
    Write-Info "Synced scoop-services helper to $dest"

    $manifestSrc = Join-Path $Script:ProjectRoot 'configs\windows\scoop\services\manifest.json'
    $manifestDest = Join-Path $servicesDir 'manifest.json'
    if (Test-Path -LiteralPath $manifestSrc) {
        Copy-FileDataOnly -SourceFile $manifestSrc -DestinationFile $manifestDest
        Write-Info "Synced scoop-services manifest to $manifestDest"
    }

    $shellDest = Join-Path $configDir 'scoop.ps1'
    $shellSrc = Join-Path $Script:ProjectRoot 'configs\windows\scoop\scoop.ps1'
    if (-not (Test-Path -LiteralPath $shellSrc)) {
        Write-ErrorAndExit "configs/windows/scoop/scoop.ps1 not found: $shellSrc"
    }
    Copy-FileDataOnly -SourceFile $shellSrc -DestinationFile $shellDest -Encoding 'utf8Bom'
    Write-Info "Synced scoop shell extension to $shellDest"
}
