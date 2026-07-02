# powershell 5 profile

# starship
Invoke-Expression (&starship init powershell)
$ENV:STARSHIP_CONFIG = "$HOME\\.config\\starship\\starship.toml"

# ls (eza)
function ls { eza --icons @args }
function l { eza -l --icons @args }
function la { eza -la --icons @args }
function lt { eza --tree --icons @args }

# vp (vite+)
. "$HOME/.vite-plus/env.ps1" # 环境初始化
function v { vp @args }
function vc { v create @args }
function vr { v run @args }
function s { vr start @args }
function d { vr dev @args }
function b { vr build @args }

# git
function gp { git push @args }
function gl { git pull @args }
function grt { cd "$(git rev-parse --show-toplevel)" }
function gc {
  $branch = git branch | fzf
  if ($branch) { git checkout $branch.Trim() }
}

# other
function reload { . $PROFILE }
function oc { opencode @args }

# scoop services（winsw）
$__scoop = "$env:SCOOP\shims\scoop.ps1"

function winsw {
  if (-not $env:SCOOP) { $host.ui.WriteErrorLine("winsw: `$env:SCOOP is not set"); return 1 }
  if ($args.Count -ge 2) {
    $xml = "$env:SCOOP\persist\$($args[1])\$($args[1])-winsw-service.xml"
    if (Test-Path $xml) {
      $winswExe = "$env:SCOOP\apps\winsw-pre\current\WinSW.exe"
      if (-not (Test-Path $winswExe)) {
        $host.ui.WriteErrorLine("winsw: WinSW not found at $winswExe (run 'scoop install winsw-pre')")
        return 1
      }
      $splat = @($args[0], $xml)
      if ($args.Count -gt 2) { $splat += $args[2..($args.Count - 1)] }
      & $winswExe @splat
      return
    }
    if ($args[0] -eq 'status') { return 'NonExistent' }
    if ($args[0] -eq 'stop') { & sc.exe stop $args[1]; return }
    if ($args[0] -eq 'uninstall') { & sc.exe delete $args[1]; return }
  }
  & "winsw.exe" $args
}

function scoop {
  if (-not $env:SCOOP) { $host.ui.WriteErrorLine("scoop: `$env:SCOOP is not set"); return 1 }
  if ($args.Count -ge 1) {
    if ($args[0] -eq 'uninstall') {
      foreach ($app in (_scoop_apps @args)) {
        $cfg = (_scoop_load_manifest).$app
        if ($cfg) {
          $xml = "$env:SCOOP\persist\$app\$app-winsw-service.xml"
          if (Test-Path $xml) {
            $status = (winsw status $app).Trim()
            if ($status -ne 'NonExistent') {
              winsw stop $app
              winsw uninstall $app
              Remove-Item "$env:SCOOP\persist\$app\$app-winsw-service.xml" -Force -ErrorAction SilentlyContinue
            }
          }
        }
      }
      & $__scoop @args
      return
    }
    if ($args[0] -eq 'services') {
      $svcArgs = $args[1..($args.Count - 1)]
      _scoop_services @svcArgs
      return
    }
  }
  & $__scoop @args
}

function _scoop_apps {
  $args | Where-Object { $_ -notlike '-*' } | Select-Object -Skip 1
}

function _scoop_load_manifest {
  $path = "$env:SCOOP\config\services-manifest.json"
  if (Test-Path $path) {
    $obj = Get-Content $path -Raw | ConvertFrom-Json
    $ht = @{}
    $obj.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
    return $ht
  }
  Write-Host "Service manifest not found at $path"
  return @{}
}

function _scoop_ensure_xml {
  param($name)
  $cfg = (_scoop_load_manifest).$name
  if (-not $cfg) { return $false }

  $xml = "$env:SCOOP\persist\$name\$name-winsw-service.xml"
  if (Test-Path $xml) { return $true }

  New-Item -ItemType Directory -Force -Path "$env:SCOOP\persist\$name" | Out-Null

  $exe = "%BASE%/../../apps/$name/current/$($cfg.executable)"
  $stopExe = if ($cfg.stopexecutable) { "%BASE%/../../apps/$name/current/$($cfg.stopexecutable)" } else { $exe }
  $argsEl = if ($cfg.arguments) { "`n  <arguments>$($cfg.arguments)</arguments>" } else { "" }
  $stopArgsEl = if ($cfg.stoparguments) { "`n  <stoparguments>$($cfg.stoparguments)</stoparguments>" } else { "" }

  $template = @"
<service>
  <id>$name</id>
  <name>$name</name>
  <description>$name server (managed by WinSW)</description>
  <executable>$exe</executable>$argsEl
  <stopexecutable>$stopExe</stopexecutable>$stopArgsEl
  <log mode="roll" />
  <onfailure action="restart" delay="10 sec" />
  <onfailure action="restart" delay="20 sec" />
</service>
"@
  Set-Content -Path $xml -Value $template.Trim() -Encoding UTF8
  Write-Host "Generated: $xml"
  return $true
}

function _scoop_services_list {
  $winswExe = "$env:SCOOP\apps\winsw-pre\current\WinSW.exe"
  if (-not (Test-Path $winswExe)) {
    $host.ui.WriteErrorLine("winsw: WinSW not found at $winswExe (run 'scoop install winsw-pre')")
    return 1
  }
  $xmls = Get-ChildItem "$env:SCOOP\persist\*-winsw-service.xml" -Recurse -ErrorAction SilentlyContinue
  "$("Name".PadRight(15)) $("Status".PadRight(15)) Path"
  foreach ($xml in $xmls) {
    $name = $xml.Directory.Name
    $status = & $winswExe status $xml.FullName 2>$null
    $statusText = switch ($status.Trim()) {
      'Active (running)' { 'started' }
      'Inactive (stopped)' { 'stopped' }
      'NonExistent' { 'not installed' }
      default { 'unknown' }
    }
    "$($name.PadRight(15)) $($statusText.PadRight(15)) $($xml.FullName)"
  }
}

function _scoop_services_help {
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

function _scoop_services {
  $action = if ($args.Count -gt 0) { $args[0] } else { 'ls' }
  $svc = if ($args.Count -gt 1) { $args[1] } else { $null }
  switch ($action) {
    'ls' { _scoop_services_list }
    'list' { _scoop_services_list }
    'install' {
      if (-not $svc) { Write-Host "Usage: scoop services install <name>"; return }
      $manifest = _scoop_load_manifest
      if (-not $manifest.ContainsKey($svc)) { Write-Host "'$svc' is not in service manifest"; return }
      if (_scoop_ensure_xml $svc) {
        $status = (winsw status $svc).Trim()
        if ($status -eq 'NonExistent') { winsw install $svc; winsw start $svc }
        else { Write-Host "Service '$svc ($svc)' already registered ($status)" }
      }
    }
    'uninstall' { if ($svc) { $s = (winsw status $svc).Trim(); if ($s -ne 'NonExistent') { winsw stop $svc; winsw uninstall $svc; Remove-Item "$env:SCOOP\persist\$svc\$svc-winsw-service.xml" -Force -ErrorAction SilentlyContinue } else { Write-Host "Service '$svc ($svc)' not registered" } } else { Write-Host "Usage: scoop services uninstall <name>" } }
    'start' { if ($svc) { winsw start $svc } else { Write-Host "Usage: scoop services start <name>" } }
    'stop' { if ($svc) { winsw stop $svc } else { Write-Host "Usage: scoop services stop <name>" } }
    'restart' { if ($svc) { winsw restart $svc } else { Write-Host "Usage: scoop services restart <name>" } }
    'help' { _scoop_services_help }
    '-h' { _scoop_services_help }
    '--help' { _scoop_services_help }
    default { Write-Host "Usage: scoop services <command> [name]"; Write-Host "  Use 'scoop services help' for details" }
  }
}
