# Scoop services manager (WinSW).
# Only switches go in param(); bare tokens fall through to $args
# (ValueFromRemainingArguments drops them under `pwsh -File`).
param(
    [switch]$PrepareUninstall,
    [switch]$PrepareUpdate,
    [switch]$RestartChanged,
    [switch]$All,
    [switch]$Force
)

$CommandArgs = @($args | ForEach-Object { [string]$_ })

# Switches that missed param() binding (pwsh -File) still arrive in $args.
$filteredArgs = New-Object System.Collections.Generic.List[string]
foreach ($token in @($CommandArgs)) {
    switch ($token) {
        '-PrepareUninstall' { $PrepareUninstall = $true }
        '-PrepareUpdate'    { $PrepareUpdate = $true }
        '-RestartChanged'   { $RestartChanged = $true }
        '-All'              { $All = $true }
        '-Force'            { $Force = $true }
        default             { [void]$filteredArgs.Add($token) }
    }
}
$CommandArgs = @($filteredArgs)

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
        throw "___SCOOP_SERVICES_EXIT_${Code}___"
    }
    exit $Code
}

function Get-ScoopServicesManifest {
    param([switch]$WarnIfMissing)

    $path = Join-Path $PSScriptRoot 'manifest.json'
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
    return (Join-Path $PSScriptRoot '.update-snapshot.json')
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
    $dir = Join-Path $env:SCOOP "apps\$Name\current"
    foreach ($file in @('scoop-manifest.json', 'manifest.json')) {
        $manifest = Join-Path $dir $file
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        try {
            $version = [string]((Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json).version)
            if ([string]::IsNullOrWhiteSpace($version)) { return $null }
            return $version
        }
        catch {
            return $null
        }
    }
    return $null
}

function Get-ScoopWinSwStatusText {
    param([string]$Name)
    return "$(Invoke-ScoopWinSw status $Name)".Trim()
}

function Get-ScoopInstallRecord {
    param([string]$Name)

    $dir = Join-Path $env:SCOOP "apps\$Name\current"
    foreach ($file in @('scoop-install.json', 'install.json')) {
        $path = Join-Path $dir $file
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
        catch {
            return $null
        }
    }
    return $null
}

function Get-ScoopBucketAppVersion {
    param(
        [string]$Name,
        [string]$Bucket
    )

    if ([string]::IsNullOrWhiteSpace($Bucket)) { return $null }
    $root = Join-Path $env:SCOOP "buckets\$Bucket"
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $bucketDir = Join-Path $root 'bucket'
    $search = if (Test-Path -LiteralPath $bucketDir) { $bucketDir } else { $root }
    $hit = Get-ChildItem -Path $search -Filter "$Name.json" -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $hit) { return $null }
    try {
        $version = [string]((Get-Content -LiteralPath $hit.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).version)
    }
    catch {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($version)) { return $null }
    return $version
}

function Test-ScoopVersionNewer {
    param(
        [string]$Installed,
        [string]$Latest
    )

    if ([string]::IsNullOrWhiteSpace($Installed) -or [string]::IsNullOrWhiteSpace($Latest)) { return $false }
    if ($Installed -eq $Latest) { return $false }

    $left = @($Installed -split '[.\-]')
    $right = @($Latest -split '[.\-]')
    $count = [Math]::Max($left.Count, $right.Count)
    for ($i = 0; $i -lt $count; $i++) {
        $a = if ($i -lt $left.Count) { $left[$i] } else { '0' }
        $b = if ($i -lt $right.Count) { $right[$i] } else { '0' }
        $aNum = 0
        $bNum = 0
        $aOk = [int]::TryParse($a, [ref]$aNum)
        $bOk = [int]::TryParse($b, [ref]$bNum)
        if ($aOk -and $bOk) {
            if ($bNum -gt $aNum) { return $true }
            if ($bNum -lt $aNum) { return $false }
            continue
        }
        $cmp = [string]::Compare($b, $a, [StringComparison]::OrdinalIgnoreCase)
        if ($cmp -gt 0) { return $true }
        if ($cmp -lt 0) { return $false }
    }
    return $false
}

# Scoop skips held apps, and skips apps whose bucket version is not newer unless -f.
function Test-ScoopAppPendingUpdate {
    param(
        [string]$Name,
        [switch]$Force
    )

    $info = Get-ScoopInstallRecord -Name $Name
    if ($info -and $info.PSObject.Properties['hold'] -and [bool]$info.hold) { return $false }
    if ($Force) { return $true }

    $bucket = if ($info -and $info.PSObject.Properties['bucket']) { [string]$info.bucket } else { '' }
    $latest = Get-ScoopBucketAppVersion -Name $Name -Bucket $bucket
    return (Test-ScoopVersionNewer -Installed (Get-ScoopAppVersion -Name $Name) -Latest $latest)
}

function Resolve-ScoopServicesUpdateTargets {
    param(
        [string[]]$Apps,
        [switch]$All,
        [switch]$Force
    )

    $manifest = Get-ScoopServicesManifest
    if ($manifest.Count -eq 0) { return @() }

    $wantAll = [bool]$All
    foreach ($app in @($Apps)) {
        if ("$app".Trim() -eq '*') { $wantAll = $true }
    }

    $names = if ($wantAll) {
        @($manifest.Keys)
    }
    else {
        @($Apps | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -ne '*' -and $manifest.ContainsKey($_) })
    }

    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($name in $names) {
        if (-not (Test-Path -LiteralPath (Get-ScoopServiceXmlPath -Name $name))) { continue }
        if (-not (Test-ScoopAppPendingUpdate -Name $name -Force:$Force)) { continue }
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
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($xml, ($template.Trim() + "`n"), $utf8)
    Write-Host "Generated: $xml"
    return $true
}

function Show-ScoopServicesHelp {
    Write-Host @"
Usage: scoop services <command> [name]

Commands:
  ls|list                List all managed services
  info        <name>     Show a service's config and status
  install     <name>     Register and start a service
  uninstall   <name>     Unregister a service
  start       <name>     Start a service
  stop        <name>     Stop a service
  restart     <name>     Restart a service
"@
}

function Write-ScoopInfoLine {
    param([string]$Key, [string]$Value)
    Write-Host -NoNewline -ForegroundColor Green ($Key.PadRight(11))
    Write-Host ": $Value"
}

function Invoke-ScoopServicesInfo {
    param([string]$Name)

    if (-not $Name) {
        Write-Host 'Usage: scoop services info <name>'
        return
    }

    $manifest = Get-ScoopServicesManifest -WarnIfMissing
    if (-not $manifest.ContainsKey($Name)) {
        Write-Host "'$Name' is not in the service manifest (add it to manifest.json)" -ForegroundColor Yellow
        return
    }

    $cfg = $manifest[$Name]
    $xml = Get-ScoopServiceXmlPath -Name $Name
    $exists = Test-Path -LiteralPath $xml
    $status = Get-ScoopWinSwStatusText -Name $Name
    if ($status -eq 'NonExistent') { $status = 'not installed' }

    $exe = if ($cfg.executable) { [string]$cfg.executable } else { '' }
    $argsVal = if ($cfg.arguments) { [string]$cfg.arguments } else { '' }
    $stopExe = if ($cfg.stopexecutable) { [string]$cfg.stopexecutable } else { $exe }
    $stopArgs = if ($cfg.stoparguments) { [string]$cfg.stoparguments } else { '' }
    $configText = if ($exists) {
        (Get-Content -LiteralPath $xml -Raw -Encoding UTF8).Trim()
    }
    else {
        '(xml not generated yet — run: scoop services install ' + $Name + ')'
    }

    $xmlLabel = if ($exists) { "$xml (exists)" } else { "$xml (none)" }

    Write-Host ''
    Write-ScoopInfoLine 'Name' $Name
    Write-ScoopInfoLine 'Status' $status
    Write-ScoopInfoLine 'XML' $xmlLabel
    Write-ScoopInfoLine 'Executable' $exe
    Write-ScoopInfoLine 'Arguments' $argsVal
    Write-ScoopInfoLine 'Stop exe' $stopExe
    Write-ScoopInfoLine 'Stop args' $stopArgs
    $indent = ' ' * 13
    $cfgLines = $configText -split "`n"
    $cfgDisplay = if ($cfgLines.Count -gt 1) {
        $cfgLines[0] + "`n" + (($cfgLines[1..($cfgLines.Count - 1)] | ForEach-Object { "$indent$_" }) -join "`n")
    }
    else {
        $cfgLines[0]
    }
    Write-Host -NoNewline -ForegroundColor Green ('Config'.PadRight(11))
    Write-Host ": $cfgDisplay"
    Write-Host ''
}

function Invoke-ScoopServicesList {
    $winswExe = Join-Path $env:SCOOP 'apps\winsw-pre\current\WinSW.exe'
    if (-not (Test-Path -LiteralPath $winswExe)) {
        [Console]::Error.WriteLine("winsw: WinSW not found at $winswExe (run 'scoop install winsw-pre')")
        Stop-ScoopServicesCli -Code 1
    }
    # Literal wildcard glob; Join-Path mishandles '*'.
    $xmls = @(Get-ChildItem -Path "$env:SCOOP\persist\*\*-winsw-service.xml" -File -ErrorAction SilentlyContinue)
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
    param([string[]]$Tokens)

    $action = if ($Tokens -and $Tokens.Count -gt 0) { $Tokens[0] } else { 'ls' }
    $svc = if ($Tokens -and $Tokens.Count -gt 1) { $Tokens[1] } else { $null }

    switch ($action) {
        'ls' { Invoke-ScoopServicesList }
        'list' { Invoke-ScoopServicesList }
        'info' {
            Invoke-ScoopServicesInfo -Name $svc
        }
        'install' {
            if (-not $svc) {
                Write-Host 'Usage: scoop services install <name>'
                return
            }
            $manifest = Get-ScoopServicesManifest -WarnIfMissing
            if (-not $manifest.ContainsKey($svc)) {
                Write-Host "'$svc' is not in the service manifest (add it to manifest.json)" -ForegroundColor Yellow
                return
            }
            if (-not (Ensure-ScoopServiceXml -Name $svc)) {
                Write-Host "Failed to prepare service definition for '$svc'"
                return
            }
            $status = Get-ScoopWinSwStatusText -Name $svc
            if ($status -eq 'NonExistent') {
                Invoke-ScoopWinSw install $svc
                Invoke-ScoopWinSw start $svc
            }
            else {
                Write-Host "Service '$svc' is already registered ($status)"
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
                Write-Host "Service '$svc' unregistered"
            }
            else {
                Write-Host "Service '$svc' is not registered"
            }
        }
        'start' {
            if (-not $svc) {
                Write-Host 'Usage: scoop services start <name>'
                return
            }
            $manifest = Get-ScoopServicesManifest -WarnIfMissing
            if (-not $manifest.ContainsKey($svc)) {
                Write-Host "'$svc' is not in the service manifest (add it to manifest.json)" -ForegroundColor Yellow
                return
            }
            if (-not (Ensure-ScoopServiceXml -Name $svc)) {
                Write-Host "Failed to prepare service definition for '$svc'"
                return
            }
            $status = Get-ScoopWinSwStatusText -Name $svc
            if ($status -eq 'NonExistent') {
                Invoke-ScoopWinSw install $svc
                Invoke-ScoopWinSw start $svc
            }
            else {
                Invoke-ScoopWinSw start $svc
            }
        }
        'stop' {
            if (-not $svc) {
                Write-Host 'Usage: scoop services stop <name>'
                return
            }
            $status = Get-ScoopWinSwStatusText -Name $svc
            if ($status -eq 'NonExistent') {
                Write-Host "Service '$svc' is not installed"
                return
            }
            Invoke-ScoopWinSw stop $svc
        }
        'restart' {
            if (-not $svc) {
                Write-Host 'Usage: scoop services restart <name>'
                return
            }
            $status = Get-ScoopWinSwStatusText -Name $svc
            if ($status -eq 'NonExistent') {
                Write-Host "Service '$svc' is not installed"
                return
            }
            Invoke-ScoopWinSw restart $svc
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

# Stop running managed services and snapshot them before `scoop update`
# so package files are not locked (nginx, mysql, …).
function Invoke-ScoopServicesPrepareUpdate {
    param(
        [string[]]$Apps,
        [switch]$All,
        [switch]$Force
    )

    $snapshotPath = Get-ScoopServicesSnapshotPath
    Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue

    $manifest = Get-ScoopServicesManifest
    $targets = @(Resolve-ScoopServicesUpdateTargets -Apps $Apps -All:$All -Force:$Force)
    if ($targets.Count -eq 0) { return }

    $entries = [ordered]@{}
    foreach ($name in $targets) {
        $cfg = $manifest[$name]
        if (-not (Test-ScoopServiceRestartOnUpdate -Cfg $cfg)) { continue }
        $status = Get-ScoopWinSwStatusText -Name $name
        if ($status -eq 'NonExistent') { continue }
        $version = Get-ScoopAppVersion -Name $name
        $running = ($status -eq 'Active (running)')
        $entries[$name] = [ordered]@{
            version = $version
            running = $running
        }
        if (-not $running) { continue }
        try {
            Write-Host "Stopping service '$name' before update..." -ForegroundColor Cyan
            Invoke-ScoopWinSw stop $name
        }
        catch {
            Write-Host "▲ Failed to stop service '$name': $($_.Exception.Message)" -ForegroundColor Yellow
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

# After a successful update, resume services that were running (stopped in PrepareUpdate).
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
        if (-not [bool]$before.running) { continue }

        $status = Get-ScoopWinSwStatusText -Name $name
        if ($status -eq 'NonExistent') { continue }

        $afterVersion = Get-ScoopAppVersion -Name $name
        $beforeVersion = [string]$before.version
        $versionChanged = (
            -not [string]::IsNullOrWhiteSpace($afterVersion) -and
            -not [string]::IsNullOrWhiteSpace($beforeVersion) -and
            $afterVersion -ne $beforeVersion
        )

        try {
            if ($versionChanged) {
                Write-Host "Restarting service '$name' after update ($beforeVersion -> $afterVersion)" -ForegroundColor Cyan
                Invoke-ScoopWinSw restart $name
            }
            else {
                Write-Host "Starting service '$name' after update" -ForegroundColor Cyan
                Invoke-ScoopWinSw start $name
            }
        }
        catch {
            Write-Host "▲ Failed to resume service '$name': $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

try {
    if ($PrepareUninstall) {
        Invoke-ScoopServicesPrepareUninstall -Apps $CommandArgs
        Stop-ScoopServicesCli -Code 0
    }
    if ($PrepareUpdate) {
        Invoke-ScoopServicesPrepareUpdate -Apps $CommandArgs -All:$All -Force:$Force
        Stop-ScoopServicesCli -Code 0
    }
    if ($RestartChanged) {
        Invoke-ScoopServicesRestartChanged
        Stop-ScoopServicesCli -Code 0
    }
    Invoke-ScoopServicesManager -Tokens $CommandArgs
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
