# Scoop mirror CLI (scoop mirror).
# Deployed to $env:SCOOP\config\scoop-mirror\manage.ps1

param(
    [Parameter(Position = 0)]
    [string]$MirrorChoice = ''
)

$shared = Join-Path $PSScriptRoot 'shared.ps1'
if (-not (Test-Path -LiteralPath $shared)) {
    throw "Scoop mirror shared helper not found: $shared"
}
. $shared

function Resolve-ScoopMirrorMenuSelectScript {
    $candidates = @(
        (Join-Path $env:SCOOP 'config\scoop-mirror\cli.mjs'),
        (Join-Path $PSScriptRoot 'cli.mjs')
    )
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return $null
}

function Invoke-ScoopMirrorMenuSelect {
    param(
        $Config,
        [string]$Title = 'Choose a Scoop mirror'
    )

    $cliJs = Resolve-ScoopMirrorMenuSelectScript
    if (-not $cliJs) {
        throw 'Interactive mirror menu requires Node and scoop-mirror/cli.mjs (re-run vpr pm / sync)'
    }
    if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
        throw 'Interactive mirror menu requires Node.js on PATH'
    }

    $items = New-Object System.Collections.Generic.List[string]
    $activeId = Get-ScoopMirrorAccelId -Prefix $Config.ActivePrefix -Config $Config
    $ids = @(@($Config.Mirrors) | ForEach-Object { [string]$_.Id }) + @('official')
    $idWidth = ($ids | Measure-Object -Property Length -Maximum).Maximum
    foreach ($mirror in @($Config.Mirrors)) {
        $mark = if ($mirror.Prefix -eq $Config.ActivePrefix) { '* ' } else { '  ' }
        [void]$items.Add(('{0}) {1}{2}' -f $mirror.Id.PadRight($idWidth), $mark, $mirror.Prefix))
    }
    $officialMark = if ([string]::IsNullOrWhiteSpace($Config.ActivePrefix)) { '* ' } else { '  ' }
    [void]$items.Add(('{0}) {1}{2}' -f 'official'.PadRight($idWidth), $officialMark, 'https://github.com/ScoopInstaller/Scoop'))

    $outFile = [IO.Path]::GetTempFileName()
    $previousOut = $env:MENU_SELECT_OUT
    $previousInitial = $env:MENU_SELECT_INITIAL
    try {
        $env:MENU_SELECT_OUT = $outFile
        $env:MENU_SELECT_INITIAL = $activeId
        $menuArgs = @('menu', $Title) + @($items)
        & node.exe $cliJs @menuArgs
        if ($LASTEXITCODE -ne 0) { return '' }
        return ((Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + '').Trim()
    }
    finally {
        if ($null -eq $previousOut) { Remove-Item Env:MENU_SELECT_OUT -ErrorAction SilentlyContinue }
        else { $env:MENU_SELECT_OUT = $previousOut }
        if ($null -eq $previousInitial) { Remove-Item Env:MENU_SELECT_INITIAL -ErrorAction SilentlyContinue }
        else { $env:MENU_SELECT_INITIAL = $previousInitial }
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    }
}

function Switch-ScoopMirrorAccel {
    param(
        [string]$Choice,
        $Config
    )

    $activePrefix = Resolve-ScoopMirrorAccelChoice -Choice $Choice -Config $Config
    $upstreamRepo = Get-ScoopMirrorUpstreamRepo -Config $Config
    $repo = if ([string]::IsNullOrWhiteSpace($activePrefix)) { $upstreamRepo } else { $activePrefix + $upstreamRepo }

    & scoop config scoop_repo $repo
    if ($LASTEXITCODE -ne 0) { throw "Could not set Scoop repo to $repo" }
    Set-ScoopMirrorBucketRemotes -ActivePrefix $activePrefix -Config $Config

    $raw = Get-Content -LiteralPath $Config.ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $raw.PSObject.Properties['activePrefix']) {
        $raw | Add-Member -NotePropertyName activePrefix -NotePropertyValue $activePrefix
    }
    else {
        $raw.activePrefix = $activePrefix
    }
    $encoding = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($Config.ConfigPath, (($raw | ConvertTo-Json -Depth 8) + "`n"), $encoding)
    $script:ScoopMirrorAccelConfig = $null

    $id = Get-ScoopMirrorAccelId -Prefix $activePrefix -Config $Config
    Write-Host "Scoop mirror switched to $id" -ForegroundColor Cyan
    Write-ScoopMirrorStatus -Config (Get-ScoopMirrorAccelConfig)
}

function Invoke-ScoopMirrorManager {
    param([string]$Choice)
    if ([string]::IsNullOrWhiteSpace($env:SCOOP)) { throw 'SCOOP environment variable is not set' }

    $Choice = "$Choice".Trim()
    # Node cli.mjs is the switch source of truth; PS path below is no-Node fallback only.
    $cliJs = Resolve-ScoopMirrorMenuSelectScript
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($node -and $cliJs) {
        & $node.Source $cliJs 'switch' $Choice
        $script:ScoopMirrorCliCode = [int]$LASTEXITCODE
        return
    }

    $config = Get-ScoopMirrorAccelConfig
    if (-not $config) { throw "Scoop mirror config not found at $env:SCOOP\config\scoop-mirror\config.json" }

    if ($Choice -in @('-h', '--help', 'help')) {
        Write-Host 'Usage: scoop mirror [<name>|official|status]'
        Write-Host ''
        Write-Host '  (no args)        interactive select (↑↓ / Enter; Esc or Ctrl+C cancel; Enter on * exits; * = active)'
        Write-Host '  <name>|official  switch directly'
        Write-Host '  status           show active mirror'
        return
    }

    if ($Choice -eq 'status') {
        Write-ScoopMirrorStatus -Config $config
        return
    }

    if ([string]::IsNullOrWhiteSpace($Choice)) {
        $selected = Invoke-ScoopMirrorMenuSelect -Config $config
        if ([string]::IsNullOrWhiteSpace($selected)) {
            Write-Host 'Canceled' -ForegroundColor Yellow
            $script:ScoopMirrorCliCode = 130
            return
        }
        $activeId = Get-ScoopMirrorAccelId -Prefix $config.ActivePrefix -Config $config
        # Same as active: exit quietly (like Esc, but without "Canceled").
        if ($selected -eq $activeId) { return }
        $Choice = $selected
    }

    Switch-ScoopMirrorAccel -Choice $Choice -Config $config
}

$script:ScoopMirrorCliCode = 0
try {
    Invoke-ScoopMirrorManager -Choice $MirrorChoice
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    $script:ScoopMirrorCliCode = 1
}
$code = $script:ScoopMirrorCliCode
$global:LASTEXITCODE = $code
# `& manage.ps1` from an interactive profile must not `exit` the host session.
if ($env:SCOOP_SHELL_INPROCESS -eq '1') { return }
exit $code
