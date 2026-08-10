# Shared PowerShell helpers for Scoop install / apply / deploy.
$Script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path

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

$script:ScoopSpinActive = $false

function Test-ScoopQuietPm {
    return ($env:USE_QUIET_INSTALL -eq '1') -or ($env:USE_QUIET_PM -eq '1')
}

function Write-Info {
    param([string]$Message)
    if ($script:ScoopSpinActive) { return }
    Write-Host "  $Message"
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n◇ $Message" -ForegroundColor Magenta
}

function Write-Success {
    param([string]$Message)
    if ($script:ScoopSpinActive) { return }
    Write-Host "  ◆ $Message" -ForegroundColor Green
}

function Write-StepSuccess {
    param([string]$Message)
    Write-Host "◆ $Message" -ForegroundColor Green
}

function Write-Note {
    param([string]$Message)
    if ($script:ScoopSpinActive) { return }
    Write-Host "  ● $Message" -ForegroundColor Blue
}

function Write-Skip {
    param([string]$Message)
    if ($script:ScoopSpinActive) { return }
    Write-Host "  ○ $Message" -ForegroundColor DarkGray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ▲ $Message" -ForegroundColor Yellow
}

function Write-ErrorAndExit {
    param([string]$Message)
    Write-Host "■ $Message" -ForegroundColor Red
    exit 1
}

# Non-quiet status only; spinner ownership is enforced by Write-Info/Success/Note/Skip.
function Write-Detail {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('info', 'success', 'note', 'skip', 'done')]
        [string]$Kind = 'info'
    )
    if (Test-ScoopQuietPm) { return }
    switch ($Kind) {
        'success' { Write-Success $Message }
        'note' { Write-Note $Message }
        'skip' { Write-Skip $Message }
        'done' { Write-StepSuccess $Message }
        default { Write-Info $Message }
    }
}

function Test-CanSpin {
    if ($env:CI -eq 'true') { return $false }
    # Windows PowerShell (5.x) consoles can't render the spinner glyphs (→ '?') or process
    # the ANSI erase sequences (→ literal ESC[2K). Keep it a plain static line there.
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return $false }
    if (-not [Environment]::UserInteractive) { return $false }
    try {
        if ([Console]::IsErrorRedirected -and [Console]::IsOutputRedirected) { return $false }
    }
    catch { }
    return $true
}

function Write-SpinDone {
    param([scriptblock]$Done)
    if ($null -eq $Done) { return }
    $script:ScoopSpinActive = $false
    # Drop a leftover QuietHost stub so the done line always reaches the console.
    Remove-Item -Path function:\global:Write-Host -Force -ErrorAction SilentlyContinue
    Remove-Item -Path function:\Write-Host -Force -ErrorAction SilentlyContinue
    $doneText = [string](& $Done)
    if ([string]::IsNullOrWhiteSpace($doneText)) { return }
    Write-StepSuccess $doneText
}

function Invoke-Spin {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter(Mandatory)]
        [scriptblock]$Script,
        [string]$Indent = '  ',
        [scriptblock]$Done = $null
    )

    if (-not (Test-CanSpin)) {
        Write-Info $Message
        & $Script
        if ($null -eq $LASTEXITCODE) { $global:LASTEXITCODE = 0 }
        Write-SpinDone -Done $Done
        return
    }

    $frames = @('◒', '◐', '◓', '◑')
    $state = @{ Active = $true; Index = 0 }
    $timer = New-Object System.Timers.Timer 80
    $timer.AutoReset = $true
    $null = Register-ObjectEvent -InputObject $timer -EventName Elapsed -MessageData @{
        State = $state
        Frames = $frames
        Indent = $Indent
        Message = $Message
    } -Action {
        $s = $Event.MessageData.State
        if (-not $s.Active) { return }
        $c = $Event.MessageData.Frames[$s.Index % $Event.MessageData.Frames.Count]
        $s.Index++
        [Console]::Error.Write(("`r{0}{1}[34m{2}  {3}{1}[0m" -f $Event.MessageData.Indent, [char]27, $c, $Event.MessageData.Message))
    }
    try { [Console]::CursorVisible = $false } catch { }
    $timer.Start()
    $script:ScoopSpinActive = $true
    $exitCode = 0
    try {
        & $Script
        if ($null -ne $LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE }
        elseif (-not $?) { $exitCode = 1 }
    }
    finally {
        $script:ScoopSpinActive = $false
        $state.Active = $false
        $timer.Stop()
        Get-EventSubscriber -ErrorAction SilentlyContinue |
            Where-Object { $_.SourceObject -eq $timer } |
            ForEach-Object { Unregister-Event -SubscriptionId $_.SubscriptionId -ErrorAction SilentlyContinue }
        $timer.Dispose()
        try {
            [Console]::Error.Write("`r`e[2K")
            [Console]::CursorVisible = $true
        }
        catch { }
    }
    $global:LASTEXITCODE = $exitCode
    Write-SpinDone -Done $Done
}

# Scoop CLI often Write-Hosts status lines; mac install.sh swallows child stdout via spin.
# Temporarily hide Write-Host so one-click flows only show our Write-* helpers.
# Pass -Capture to keep lines in memory (e.g. write error.log on failure).
function Invoke-QuietHost {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Script,
        [System.Collections.IList]$Capture = $null
    )
    $script:QuietHostCapture = $Capture
    $previous = Get-Content -Path function:\Write-Host -ErrorAction SilentlyContinue
    function global:Write-Host {
        param(
            [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
            $Object,
            $ForegroundColor,
            $BackgroundColor,
            [switch]$NoNewline,
            $Separator
        )
        if ($null -eq $script:QuietHostCapture -or $null -eq $Object) { return }
        foreach ($item in @($Object)) {
            [void]$script:QuietHostCapture.Add([string]$item)
        }
    }
    try {
        $output = & $Script 2>&1
        if ($null -ne $script:QuietHostCapture -and $null -ne $output) {
            foreach ($line in @($output)) {
                [void]$script:QuietHostCapture.Add("$line")
            }
        }
    }
    finally {
        $script:QuietHostCapture = $null
        if ($null -ne $previous) {
            Set-Item -Path function:\global:Write-Host -Value $previous
        }
        else {
            Remove-Item -Path function:\global:Write-Host -Force -ErrorAction SilentlyContinue
        }
    }
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

# Scoop helpers root (XDG): ~/.config/scoop.
function Get-ScoopConfigDir {
    $xdg = [string]$env:XDG_CONFIG_HOME
    if (-not [string]::IsNullOrWhiteSpace($xdg)) {
        return (Join-Path $xdg.Trim() 'scoop')
    }
    $homeRoot = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    return (Join-Path $homeRoot '.config\scoop')
}
