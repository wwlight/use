$Script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

# Shared PowerShell helpers for Scoop install / accel / deploy.
# Sync / git-plugin / brew paths live in the Node CLI (src/).

function Test-Administrator {
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -eq $currentIdentity) { return $false }
        $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-InteractivePrompt {
    if ($env:SYNC_INTERACTIVE -eq '1') {
        return $true
    }

    if (-not [Environment]::UserInteractive) {
        return $false
    }

    try {
        if (-not [Console]::IsInputRedirected) {
            return $true
        }
    }
    catch {
        return $false
    }

    # Do not open CONIN$ here: Node dispatch or redirected stdin may block.
    # Callers enable interaction with SYNC_INTERACTIVE=1.
    return $false
}

function Get-GithubAccelMirrors {
    if ($null -ne $script:GithubAccelMirrors) {
        return $script:GithubAccelMirrors
    }

    $cfg = (Read-Manifest -Scope common).githubAccel
    if (-not $cfg) {
        Write-ErrorAndExit 'common manifest is missing githubAccel'
    }

    $mirrors = @()
    foreach ($item in @($cfg.mirrors)) {
        if ($null -eq $item) { continue }
        $id = [string]$item.id
        $p = [string]$item.prefix
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not $p.EndsWith('/')) { $p += '/' }
        $mirrors += [pscustomobject]@{ id = $id; prefix = $p }
    }

    if ($mirrors.Count -eq 0) {
        Write-ErrorAndExit 'common githubAccel.mirrors is empty; configure at least one mirror'
    }

    $script:GithubAccelMirrors = $mirrors
    return $script:GithubAccelMirrors
}

function Get-GithubAccelPrefixes {
    if ($null -ne $script:GithubAccelPrefixes) {
        return $script:GithubAccelPrefixes
    }

    $prefixes = @(
        foreach ($item in (Get-GithubAccelMirrors)) {
            [string]$item.prefix
        }
    )
    $script:GithubAccelPrefixes = $prefixes
    return $script:GithubAccelPrefixes
}

function Get-GithubAccelSelectionMap {
    $map = [ordered]@{}
    foreach ($item in (Get-GithubAccelMirrors)) {
        $id = [string]$item.id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if (-not $map.Contains($id)) { $map[$id] = [string]$item.prefix }
    }
    $map['official'] = ''
    return $map
}

function Write-Info {
    param([string]$Message)
    Write-Host "$Message"
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✔ $Message" -ForegroundColor Green
}

function Write-Note {
    param([string]$Message)
    Write-Host "  ✔ $Message" -ForegroundColor Blue
}

function Write-Warn {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-ErrorAndExit {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
    exit 1
}

function Get-Os {
    if (($env:OS -eq 'Windows_NT') -or (($null -ne (Get-Variable IsWindows -ErrorAction SilentlyContinue)) -and $IsWindows)) {
        return 'windows'
    }
    if (($null -ne (Get-Variable IsMacOS -ErrorAction SilentlyContinue)) -and $IsMacOS) {
        return 'macos'
    }
    if (($null -ne (Get-Variable IsLinux -ErrorAction SilentlyContinue)) -and $IsLinux) {
        return 'linux'
    }

    $unameS = ''
    try { $unameS = (& uname -s 2>$null) } catch { }

    switch -Regex ($unameS) {
        '^Darwin$' { return 'macos' }
        '^(CYGWIN|MINGW|MSYS)' { return 'windows' }
        '^Linux$' { return 'linux' }
    }

    if ($env:OSTYPE -match '^(msys|cygwin)') { return 'windows' }
    if ($env:OSTYPE -match '^darwin') { return 'macos' }
    if ($env:OSTYPE -match '^linux') { return 'linux' }
    if ($env:WINDIR) { return 'windows' }

    return 'unknown'
}

function Assert-TargetOs {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('macos', 'windows', 'linux')]
        [string]$Expected
    )

    $current = Get-Os
    if ($current -ne $Expected) {
        Write-ErrorAndExit "This script supports only $Expected; detected $current"
    }
}

function Read-Manifest {
    param([string]$Scope = 'windows')

    $manifestPath = Join-Path $Script:ProjectRoot "manifests/$Scope.json"
    if (-not (Test-Path $manifestPath)) {
        Write-ErrorAndExit "Manifest not found: $manifestPath"
    }
    Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-ExpandedPath {
    param([string]$Path)
    if ($Path -match '^~(/|\\|$)') {
        $Path = $Path -replace '^~', $env:USERPROFILE
    }
    return $Path -replace '/', '\'
}

function Copy-FileDataOnly {
    param(
        [string]$SourceFile,
        [string]$DestinationFile,
        [string]$Encoding = ''
    )

    $source = Get-ExpandedPath $SourceFile
    $destination = Get-ExpandedPath $DestinationFile
    $destinationDir = Split-Path $destination -Parent

    if (-not (Test-Path $source)) {
        throw "Source file not found: $source"
    }

    if (-not (Test-Path $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    if ($Encoding -eq 'utf8Bom') {
        $content = [System.IO.File]::ReadAllText($source, [System.Text.Encoding]::UTF8)
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($destination, $content, $utf8Bom)
        return
    }

    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($robocopy) {
        $sourceDir = Split-Path $source -Parent
        $sourceName = Split-Path $source -Leaf
        $destinationName = Split-Path $destination -Leaf
        $robocopyPath = $robocopy.Source
        $copyDir = $destinationDir
        $tempDir = $null

        if ($sourceName -ne $destinationName) {
            $tempDir = Join-Path $destinationDir ".copy-data-only-$([Guid]::NewGuid().ToString('N'))"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $copyDir = $tempDir
        }

        try {
            & $robocopyPath $sourceDir $copyDir $sourceName /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NC /NS | Out-Null
            $exitCode = $LASTEXITCODE
            if ($exitCode -ge 8) {
                throw "robocopy failed with exit code $exitCode"
            }

            if ($tempDir) {
                Move-Item (Join-Path $tempDir $sourceName) $destination -Force -ErrorAction Stop
            }
        }
        finally {
            if ($tempDir -and (Test-Path $tempDir)) {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not (Test-Path $destination)) {
            throw "Destination missing after copy: $destination"
        }
    }
    else {
        Copy-Item $source $destination -Force -ErrorAction Stop
    }
}
