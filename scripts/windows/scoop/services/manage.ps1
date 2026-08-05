# Scoop services (WinSW). Deployed to $env:SCOOP\config\scoop-services\manage.ps1.
param(
    [switch]$PrepareUninstall,
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
    $path = Join-Path $env:SCOOP 'config\scoop-services\manifest.json'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "Service manifest not found at $path"
        return @{}
    }
    $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $ht = @{}
    foreach ($prop in $obj.PSObject.Properties) {
        $ht[$prop.Name] = $prop.Value
    }
    return $ht
}

function Invoke-ScoopWinSw {
    if ($args.Count -ge 2) {
        $xml = Join-Path $env:SCOOP "persist\$($args[1])\$($args[1])-winsw-service.xml"
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

    $xml = Join-Path $env:SCOOP "persist\$Name\$Name-winsw-service.xml"
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
            $manifest = Get-ScoopServicesManifest
            if (-not $manifest.ContainsKey($svc)) {
                Write-Host "'$svc' is not in the service manifest"
                return
            }
            if (Ensure-ScoopServiceXml -Name $svc) {
                $status = "$(Invoke-ScoopWinSw status $svc)".Trim()
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
            $status = "$(Invoke-ScoopWinSw status $svc)".Trim()
            if ($status -ne 'NonExistent') {
                Invoke-ScoopWinSw stop $svc
                Invoke-ScoopWinSw uninstall $svc
                $xml = Join-Path $env:SCOOP "persist\$svc\$svc-winsw-service.xml"
                Remove-Item -LiteralPath $xml -Force -ErrorAction SilentlyContinue
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
        $xml = Join-Path $env:SCOOP "persist\$app\$app-winsw-service.xml"
        if (-not (Test-Path -LiteralPath $xml)) { continue }
        $status = "$(Invoke-ScoopWinSw status $app)".Trim()
        if ($status -eq 'NonExistent') { continue }
        Invoke-ScoopWinSw stop $app
        Invoke-ScoopWinSw uninstall $app
        Remove-Item -LiteralPath $xml -Force -ErrorAction SilentlyContinue
    }
}

try {
    if ($PrepareUninstall) {
        Invoke-ScoopServicesPrepareUninstall -Apps $CommandArgs
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
