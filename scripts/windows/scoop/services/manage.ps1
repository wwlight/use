# Scoop services (WinSW). Deployed to $env:SCOOP\config\scoop-services\manage.ps1.
param(
    [switch]$PrepareUninstall,
    [switch]$PrepareUpdate,
    [switch]$RestartChanged,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

if (-not $env:SCOOP) {
    [Console]::Error.WriteLine('scoop services: $env:SCOOP is not set')
    $global:LASTEXITCODE = 1
    if ($env:SCOOP_SHELL_INPROCESS -eq '1') { return }
    exit 1
}

function Stop-ScoopServicesCli {
    param([int]$Code = 0)
    $global:LASTEXITCODE = $Code
    if ($env:SCOOP_SHELL_INPROCESS -eq '1') {
        throw "___SCOOP_SERVICES_EXIT_$Code___"
    }
    exit $Code
}

function Get-ScoopServicesManifest {
    param([switch]$WarnIfMissing)

    $path = Join-Path $env:SCOOP 'config\scoop-services\manifest.json'
    if (-not (Test-Path -LiteralPath $path)) {
        if ($WarnIfMissing) {
            Write-Host "Service manifest not found at $path"
        }
        return @{}
    }
    $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $ht = @{}
    foreach ($prop in $obj.PSObject.Properties) {
        $ht[$prop.Name] = $prop.Value
    }
    return $ht
}

function Get-ScoopServicesSnapshotPath {
    return (Join-Path $env:SCOOP 'config\scoop-services\.update-snapshot.json')
}

function Get-ScoopServiceXmlPath {
    param([string]$Name)
    return (Join-Path $env:SCOOP "persist\$Name\$Name-winsw-service.xml")
}

function Test-ScoopServiceRestartOnUpdate {
    param($Cfg)
    if ($null -eq $Cfg) { return $true }
    if ($null -eq $Cfg.PSObject.Properties['restartOnUpdate']) { return $true }
    return [bool]$Cfg.restartOnUpdate
}

function Get-ScoopAppVersion {
    param([string]$Name)
    $manifest = Join-Path $env:SCOOP "apps\$Name\current\manifest.json"
    if (-not (Test-Path -LiteralPath $manifest)) { return $null }
    try {
        $version = [string]((Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json).version)
        if ([string]::IsNullOrWhiteSpace($version)) { return $null }
        return $version
    }
    catch {
        return $null
    }
}

function Get-ScoopWinSwStatusText {
    param([string]$Name)
    return "$(Invoke-ScoopWinSw status $Name)".Trim()
}

function Resolve-ScoopServicesUpdateTargets {
    param([string[]]$Apps)

    $manifest = Get-ScoopServicesManifest
    if ($manifest.Count -eq 0) { return @() }

    $all = $false
    if (-not $Apps -or $Apps.Count -eq 0) { $all = $true }
    elseif ($Apps.Count -eq 1 -and "$($Apps[0])".Trim() -eq '*') { $all = $true }

    $names = if ($all) {
        @($manifest.Keys)
    }
    else {
        @($Apps | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $manifest.ContainsKey($_) })
    }

    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($name in $names) {
        if (-not (Test-Path -LiteralPath (Get-ScoopServiceXmlPath -Name $name))) { continue }
        [void]$targets.Add($name)
    }
    return $targets.ToArray()
}

function Invoke-ScoopWinSw {
    if ($args.Count -ge 2) {
        $xml = Get-ScoopServiceXmlPath -Name $args[1]
        if (Test-Path -LiteralPath $xml) {
            $winswExe = Join-Path $env:SCOOP 'apps\winsw-pre\current\WinSW.exe'
            if (-not (Test-Path -LiteralPath $winswExe)) {
                [Console]::Error.WriteLine("winsw: WinSW not found at $winswExe (run 'scoop install winsw-pre')")
                Stop-ScoopServicesCli -Code 1
            }
            $splat = @($args[0], $xml)
            if ($args.Count -gt 2) { $splat += $args[2..($args.Count - 1)] }
            & $winswExe @splat
            return
        }
        if ($args[0] -eq 'status') {
            Write-Output 'NonExistent'
            return
        }
        if ($args[0] -eq 'stop') {
            & sc.exe stop $args[1]
            return
        }
        if ($args[0] -eq 'uninstall') {
            & sc.exe delete $args[1]
            return
        }
    }
    & winsw.exe @args
}

function Ensure-ScoopServiceXml {
    param([string]$Name)

    $manifest = Get-ScoopServicesManifest
    $cfg = $manifest[$Name]
    if (-not $cfg) { return $false }

    $xml = Get-ScoopServiceXmlPath -Name $Name
    if (Test-Path -LiteralPath $xml) { return $true }

    $persistDir = Join-Path $env:SCOOP "persist\$Name"
    if (-not (Test-Path -LiteralPath $persistDir)) {
        New-Item -ItemType Directory -Force -Path $persistDir | Out-Null
    }

    $exe = "%BASE%/../../apps/$Name/current/$($cfg.executable)"
    $stopExe = if ($cfg.stopexecutable) {
        "%BASE%/../../apps/$Name/current/$($cfg.stopexecutable)"
    }
    else {
        $exe
    }
    $argsEl = if ($cfg.arguments) { "`n  <arguments>$($cfg.arguments)</arguments>" } else { '' }
    $stopArgsEl = if ($cfg.stoparguments) { "`n  <stoparguments>$($cfg.stoparguments)</stoparguments>" } else { '' }

    $template = @"
<service>
  <id>$Name</id>
  <name>$Name</name>
  <description>$Name server (managed by WinSW)</description>
  <executable>$exe</executable>$argsEl
  <stopexecutable>$stopExe</stopexecutable>$stopArgsEl
  <log mode="roll" />
  <onfailure action="restart" delay="10 sec" />
  <onfailure action="restart" delay="20 sec" />
</service>
"@
    Set-Content -LiteralPath $xml -Value $template.Trim() -Encoding UTF8
    Write-Host "Generated: $xml"
    return $true
}

function Show-ScoopServicesHelp {
    Write-Host @"
Usage: scoop services <command> [name]

Commands:
  ls|list                List all managed services
  install     <name>     Register and start a service
  uninstall   <name>     Unregister a service
  start       <name>     Start a service
  stop        <name>     Stop a service
  restart     <name>     Restart a service
"@
}

function Invoke-ScoopServicesList {
    $winswExe = Join-Path $env:SCOOP 'apps\winsw-pre\current\WinSW.exe'
    if (-not (Test-Path -LiteralPath $winswExe)) {
        [Console]::Error.WriteLine("winsw: WinSW not found at $winswExe (run 'scoop install winsw-pre')")
        Stop-ScoopServicesCli -Code 1
    }
    $xmls = Get-ChildItem (Join-Path $env:SCOOP 'persist\*-winsw-service.xml') -Recurse -ErrorAction SilentlyContinue
    Write-Output ("{0} {1} Path" -f ('Name'.PadRight(15)), ('Status'.PadRight(15)))
    foreach ($xml in $xmls) {
        $name = $xml.Directory.Name
        $status = & $winswExe status $xml.FullName 2>$null
        $statusText = switch ("$status".Trim()) {
            'Active (running)' { 'started' }
            'Inactive (stopped)' { 'stopped' }
            'NonExistent' { 'not installed' }
            default { 'unknown' }
        }
        Write-Output ("{0} {1} {2}" -f $name.PadRight(15), $statusText.PadRight(15), $xml.FullName)
    }
}

function Invoke-ScoopServicesManager {
    param([string[]]$Args)

    $action = if ($Args -and $Args.Count -gt 0) { $Args[0] } else { 'ls' }
    $svc = if ($Args -and $Args.Count -gt 1) { $Args[1] } else { $null }

    switch ($action) {
        'ls' { Invoke-ScoopServicesList }
        'list' { Invoke-ScoopServicesList }
        'install' {
            if (-not $svc) {
                Write-Host 'Usage: scoop services install <name>'
                return
            }
            $manifest = Get-ScoopServicesManifest -WarnIfMissing
            if (-not $manifest.ContainsKey($svc)) {
                Write-Host "'$svc' is not in the service manifest"
                return
            }
            if (Ensure-ScoopServiceXml -Name $svc) {
                $status = Get-ScoopWinSwStatusText -Name $svc
                if ($status -eq 'NonExistent') {
                    Invoke-ScoopWinSw install $svc
                    Invoke-ScoopWinSw start $svc
                }
                else {
                    Write-Host "Service '$svc' is already registered ($status)"
                }
            }
        }
        'uninstall' {
            if (-not $svc) {
                Write-Host 'Usage: scoop services uninstall <name>'
                return
            }
            $status = Get-ScoopWinSwStatusText -Name $svc
            if ($status -ne 'NonExistent') {
                Invoke-ScoopWinSw stop $svc
                Invoke-ScoopWinSw uninstall $svc
                Remove-Item -LiteralPath (Get-ScoopServiceXmlPath -Name $svc) -Force -ErrorAction SilentlyContinue
            }
            else {
                Write-Host "Service '$svc' is not registered"
            }
        }
        'start' {
            if ($svc) { Invoke-ScoopWinSw start $svc }
            else { Write-Host 'Usage: scoop services start <name>' }
        }
        'stop' {
            if ($svc) { Invoke-ScoopWinSw stop $svc }
            else { Write-Host 'Usage: scoop services stop <name>' }
        }
        'restart' {
            if ($svc) { Invoke-ScoopWinSw restart $svc }
            else { Write-Host 'Usage: scoop services restart <name>' }
        }
        'help' { Show-ScoopServicesHelp }
        '-h' { Show-ScoopServicesHelp }
        '--help' { Show-ScoopServicesHelp }
        default {
            Write-Host 'Usage: scoop services <command> [name]'
            Write-Host "  Run 'scoop services help' for details"
        }
    }
}

function Invoke-ScoopServicesPrepareUninstall {
    param([string[]]$Apps)

    $manifest = Get-ScoopServicesManifest
    foreach ($app in @($Apps)) {
        if (-not $manifest.ContainsKey($app)) { continue }
        $xml = Get-ScoopServiceXmlPath -Name $app
        if (-not (Test-Path -LiteralPath $xml)) { continue }
        $status = Get-ScoopWinSwStatusText -Name $app
        if ($status -eq 'NonExistent') { continue }
        Invoke-ScoopWinSw stop $app
        Invoke-ScoopWinSw uninstall $app
        Remove-Item -LiteralPath $xml -Force -ErrorAction SilentlyContinue
    }
}

# Snapshot registered services before scoop update (brew restart_service: :changed).
function Invoke-ScoopServicesPrepareUpdate {
    param([string[]]$Apps)

    $snapshotPath = Get-ScoopServicesSnapshotPath
    Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue

    $manifest = Get-ScoopServicesManifest
    $targets = @(Resolve-ScoopServicesUpdateTargets -Apps $Apps)
    if ($targets.Count -eq 0) { return }

    $entries = [ordered]@{}
    foreach ($name in $targets) {
        $cfg = $manifest[$name]
        if (-not (Test-ScoopServiceRestartOnUpdate -Cfg $cfg)) { continue }
        $status = Get-ScoopWinSwStatusText -Name $name
        if ($status -eq 'NonExistent') { continue }
        $version = Get-ScoopAppVersion -Name $name
        $entries[$name] = [ordered]@{
            version = $version
            running = ($status -eq 'Active (running)')
        }
    }

    if ($entries.Count -eq 0) { return }

    $dir = Split-Path -Parent $snapshotPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $encoding = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($snapshotPath, (($entries | ConvertTo-Json -Depth 5) + "`n"), $encoding)
}

# After successful scoop update: restart services whose version changed and were running.
function Invoke-ScoopServicesRestartChanged {
    $snapshotPath = Get-ScoopServicesSnapshotPath
    if (-not (Test-Path -LiteralPath $snapshotPath)) { return }

    try {
        $snapshot = Get-Content -LiteralPath $snapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue
        return
    }
    finally {
        Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue
    }

    if (-not $snapshot) { return }
    $manifest = Get-ScoopServicesManifest

    foreach ($prop in @($snapshot.PSObject.Properties)) {
        $name = $prop.Name
        $before = $prop.Value
        if (-not $manifest.ContainsKey($name)) { continue }
        if (-not (Test-ScoopServiceRestartOnUpdate -Cfg $manifest[$name])) { continue }
        if (-not (Test-Path -LiteralPath (Get-ScoopServiceXmlPath -Name $name))) { continue }

        $status = Get-ScoopWinSwStatusText -Name $name
        if ($status -eq 'NonExistent') { continue }

        $afterVersion = Get-ScoopAppVersion -Name $name
        $beforeVersion = [string]$before.version
        if ([string]::IsNullOrWhiteSpace($afterVersion) -or [string]::IsNullOrWhiteSpace($beforeVersion)) { continue }
        if ($afterVersion -eq $beforeVersion) { continue }
        if (-not [bool]$before.running) { continue }

        try {
            Write-Host "Restarting service '$name' after update ($beforeVersion -> $afterVersion)" -ForegroundColor Cyan
            Invoke-ScoopWinSw restart $name
        }
        catch {
            Write-Host "Warning: failed to restart service '$name': $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

try {
    if ($PrepareUninstall) {
        Invoke-ScoopServicesPrepareUninstall -Apps $CommandArgs
        Stop-ScoopServicesCli -Code 0
    }
    if ($PrepareUpdate) {
        Invoke-ScoopServicesPrepareUpdate -Apps $CommandArgs
        Stop-ScoopServicesCli -Code 0
    }
    if ($RestartChanged) {
        Invoke-ScoopServicesRestartChanged
        Stop-ScoopServicesCli -Code 0
    }
    Invoke-ScoopServicesManager -Args $CommandArgs
    Stop-ScoopServicesCli -Code 0
}
catch {
    if ($_.Exception.Message -match '^___SCOOP_SERVICES_EXIT_(\d+)___$') {
        $global:LASTEXITCODE = [int]$Matches[1]
        if ($env:SCOOP_SHELL_INPROCESS -eq '1') { return }
        exit $global:LASTEXITCODE
    }
    [Console]::Error.WriteLine($_.Exception.Message)
    $global:LASTEXITCODE = 1
    if ($env:SCOOP_SHELL_INPROCESS -eq '1') { return }
    exit 1
}
