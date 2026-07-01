# powershell 7 profile

# starship
Invoke-Expression (&starship init powershell)
$ENV:STARSHIP_CONFIG = "$HOME\\.config\\starship\\starship.toml"

# vp (vite+) 环境初始化
. "$HOME/.vite-plus/env"

# ls (eza)
function ls { eza --icons @args }
function l { eza -l --icons @args }
function la { eza -la --icons @args }
function lt { eza --tree --icons @args }

# vp (vite+)
function v { vp @args }
function vc { v create @args }
function vr { v run @args }
function s { vr start @args }
function d { vr dev @args }
function b { vr build @args }

# Git
function gp { git push @args }
function gl { git pull @args }
function grt { cd "$(git rev-parse --show-toplevel)" }
function gc {
  $branch = git branch | fzf
  if ($branch) { git checkout $branch.Trim() }
}

# other
function oc { opencode @args }
function reload { . $PROFILE }

# winsw + scoop services (like brew services)
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
  }
  & "winsw.exe" $args
}

function scoop {
  if (-not $env:SCOOP) { $host.ui.WriteErrorLine("scoop: `$env:SCOOP is not set"); return 1 }
  if ($args.Count -ge 1) {
    if ($args[0] -eq 'install' -and $args -contains '--services') {
      $filtered = $args | Where-Object { $_ -ne '--services' }
      & $__scoop @filtered
      if ($LASTEXITCODE -ne 0) { return }
      foreach ($app in (_scoop_apps @args)) {
        _scoop_ensure_xml $app
        if ((winsw status $app).Trim() -eq 'NonExistent') { winsw install $app; winsw start $app } else { Write-Host "Service '$app ($app)' already registered" }
      }
      return
    }
    if ($args[0] -eq 'uninstall') {
      $filtered = $args | Where-Object { $_ -ne '--services' }
      foreach ($app in (_scoop_apps @args)) {
        $xml = "$env:SCOOP\persist\$app\$app-winsw-service.xml"
        if (Test-Path $xml) {
          if ((winsw status $app).Trim() -ne 'NonExistent') {
            winsw uninstall $app
          } else {
            Write-Host "Service '$app ($app)' not registered, skipping"
          }
        }
      }
      & $__scoop @filtered
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

function _scoop_ensure_xml {
  param($name)
  $xml = "$env:SCOOP\persist\$name\$name-winsw-service.xml"
  if (!(Test-Path $xml)) {
    New-Item -ItemType Directory -Force -Path "$env:SCOOP\persist\$name" | Out-Null
    $exe = "$name.exe"
    $exeDir = "$env:SCOOP\apps\$name\current"
    $files = @()
    if (Test-Path $exeDir) { $files += Get-ChildItem "$exeDir\*.exe" -ErrorAction SilentlyContinue }
    if (-not $files -and (Test-Path "$exeDir\bin")) { $files = Get-ChildItem "$exeDir\bin\*.exe" -ErrorAction SilentlyContinue }
    if ($files) {
      $matched = $files | Where-Object { $_.Name -eq "$name.exe" }
      if ($matched) {
        $rel = $matched[0].DirectoryName.Substring($exeDir.Length).TrimStart('\')
        $exe = if ($rel) { "$rel\$($matched[0].Name)" } else { $matched[0].Name }
      } else {
        $rel = $files[0].DirectoryName.Substring($exeDir.Length).TrimStart('\')
        $exe = if ($rel) { "$rel\$($files[0].Name)" } else { $files[0].Name }
        $host.ui.WriteErrorLine("  (auto-detected executable: $exe)")
      }
    }
    $template = @"
<service>
  <id>$name</id>
  <name>$name</name>
  <description>$name server (managed by WinSW)</description>
  <executable>%BASE%\..\..\apps\$name\current\$exe</executable>
  <stopexecutable>%BASE%\..\..\apps\$name\current\$exe</stopexecutable>
  <log mode="roll" />
  <onfailure action="restart" delay="10 sec" />
  <onfailure action="restart" delay="20 sec" />
</service>
"@
    Set-Content -Path $xml -Value $template.Trim() -Encoding UTF8
    Write-Host "Generated: $xml"
    Write-Host "Tip: edit the XML to add <arguments>/<stoparguments> if needed"
  }
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
      _scoop_ensure_xml $svc
      if ((winsw status $svc).Trim() -eq 'NonExistent') { winsw install $svc; winsw start $svc } else { Write-Host "Service '$svc ($svc)' already registered" }
    }
    'uninstall' { if ($svc) { winsw uninstall $svc } else { Write-Host "Usage: scoop services uninstall <name>" } }
    'start' { if ($svc) { winsw start $svc } else { Write-Host "Usage: scoop services start <name>" } }
    'stop' { if ($svc) { winsw stop $svc } else { Write-Host "Usage: scoop services stop <name>" } }
    'restart' { if ($svc) { winsw restart $svc } else { Write-Host "Usage: scoop services restart <name>" } }
    'help' { _scoop_services_help }
    '-h' { _scoop_services_help }
    '--help' { _scoop_services_help }
    default { Write-Host "Usage: scoop services <command> [name]"; Write-Host "  Use 'scoop services help' for details" }
  }
}
