# Scoop PowerShell shell extensions (winsw + scoop wrappers).
# Deployed to $env:SCOOP\config\scoop.ps1 and dotted from pwsh5/pwsh7 profiles.
# Core logic stays in scoop-mirror/ and scoop-services/.
# winsw shim stays here for interactive hot path; services manager has its own WinSW helper.

$__scoop = "$env:SCOOP\shims\scoop.ps1"

function winsw {
  if (-not $env:SCOOP) {
    $host.ui.WriteErrorLine('winsw: $env:SCOOP is not set')
    $global:LASTEXITCODE = 1
    return
  }
  if ($args.Count -ge 2) {
    $xml = "$env:SCOOP\persist\$($args[1])\$($args[1])-winsw-service.xml"
    if (Test-Path $xml) {
      $winswExe = "$env:SCOOP\apps\winsw-pre\current\WinSW.exe"
      if (-not (Test-Path $winswExe)) {
        $host.ui.WriteErrorLine("winsw: WinSW not found at $winswExe (run 'scoop install winsw-pre')")
        $global:LASTEXITCODE = 1
        return
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

function _scoop_invoke_helper {
  param(
    [Parameter(Mandatory)][string]$Path,
    [object[]]$ArgumentList = @()
  )
  $previous = $env:SCOOP_SHELL_INPROCESS
  $env:SCOOP_SHELL_INPROCESS = '1'
  try {
    & $Path @ArgumentList
  }
  finally {
    if ($null -eq $previous) { Remove-Item Env:SCOOP_SHELL_INPROCESS -ErrorAction SilentlyContinue }
    else { $env:SCOOP_SHELL_INPROCESS = $previous }
  }
}

function _scoop_ensure_mirror_accel {
  $p = "$env:SCOOP\config\scoop-mirror\hook.ps1"
  $cli = "$env:SCOOP\config\scoop-mirror\cli.mjs"
  if (-not (Test-Path $p)) { return }
  # Node repair owns fast-path + rewrite; PS -RepairHook is no-Node fallback only.
  if ((Test-Path $cli) -and (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    & node.exe $cli repair | Out-Null
    return
  }
  _scoop_invoke_helper -Path $p -ArgumentList @('-RepairHook')
}

function _scoop_prepare_package_operation {
  $p = "$env:SCOOP\config\scoop-mirror\hook.ps1"
  $cli = "$env:SCOOP\config\scoop-mirror\cli.mjs"
  if (-not (Test-Path $p)) {
    $host.ui.WriteErrorLine("scoop: mirror preflight helper not found at $p")
    $global:LASTEXITCODE = 1
    return
  }
  if ((Test-Path $cli) -and (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    $output = & node.exe $cli repair 2>&1
    if ($LASTEXITCODE -ne 0) {
      $detail = ($output | Out-String).Trim()
      if (-not [string]::IsNullOrWhiteSpace($detail)) { $host.ui.WriteErrorLine($detail) }
      $global:LASTEXITCODE = 1
    }
    return
  }
  _scoop_invoke_helper -Path $p -ArgumentList @('-PrepareCommand')
}

function _scoop_manage_mirror {
  param([string]$Choice = '')
  $cli = "$env:SCOOP\config\scoop-mirror\cli.mjs"
  if ((Test-Path $cli) -and (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    & node.exe $cli switch $Choice
    return
  }
  $p = "$env:SCOOP\config\scoop-mirror\manage.ps1"
  if (-not (Test-Path $p)) {
    $host.ui.WriteErrorLine("scoop: mirror helper not found at $p")
    $global:LASTEXITCODE = 1
    return
  }
  _scoop_invoke_helper -Path $p -ArgumentList @('-MirrorChoice', $Choice)
}

function _scoop_services_helper {
  return "$env:SCOOP\config\scoop-services\manage.ps1"
}

function Test-ScoopHasManagedServices {
  $persist = Join-Path $env:SCOOP 'persist'
  if (-not (Test-Path -LiteralPath $persist)) { return $false }
  # Same depth as scoop.zsh: persist/<app>/*-winsw-service.xml (avoid full-tree recurse).
  return [bool](Get-ChildItem -Path (Join-Path $persist '*\*-winsw-service.xml') -File -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function _scoop_manage_services {
  $p = _scoop_services_helper
  if (-not (Test-Path $p)) {
    $host.ui.WriteErrorLine("scoop: services helper not found at $p (re-run vpr pm / sync)")
    $global:LASTEXITCODE = 1
    return
  }
  _scoop_invoke_helper -Path $p -ArgumentList @($args)
}

function _scoop_prepare_uninstall {
  $p = _scoop_services_helper
  if ($args.Count -eq 0) { return }
  if (-not (Test-Path $p)) {
    $host.ui.WriteErrorLine("scoop: services helper not found at $p (re-run vpr pm / sync); refusing uninstall without service cleanup")
    $global:LASTEXITCODE = 1
    return
  }
  $argList = [System.Collections.Generic.List[object]]::new()
  [void]$argList.Add('-PrepareUninstall')
  foreach ($a in $args) { [void]$argList.Add($a) }
  _scoop_invoke_helper -Path $p -ArgumentList $argList.ToArray()
}

function _scoop_prepare_update_services {
  # Cheap gate: avoid loading manage.ps1 when nothing is registered.
  if (-not (Test-ScoopHasManagedServices)) { return }
  $p = _scoop_services_helper
  if (-not (Test-Path $p)) { return }
  $argList = [System.Collections.Generic.List[object]]::new()
  [void]$argList.Add('-PrepareUpdate')
  foreach ($a in $args) { [void]$argList.Add($a) }
  try {
    _scoop_invoke_helper -Path $p -ArgumentList $argList.ToArray()
  }
  catch {
    # Snapshot is best-effort; never block scoop update.
  }
}

function _scoop_restart_changed_services {
  $snapshot = Join-Path $env:SCOOP 'config\scoop-services\.update-snapshot.json'
  if (-not (Test-Path -LiteralPath $snapshot)) { return }
  $p = _scoop_services_helper
  if (-not (Test-Path $p)) { return }
  try {
    _scoop_invoke_helper -Path $p -ArgumentList @('-RestartChanged')
  }
  catch {
    $host.ui.WriteErrorLine("scoop: service restart after update failed: $($_.Exception.Message)")
  }
}

function _scoop_apps {
  $args | Where-Object { $_ -notlike '-*' } | Select-Object -Skip 1
}

function scoop {
  if (-not $env:SCOOP) {
    $host.ui.WriteErrorLine('scoop: $env:SCOOP is not set')
    $global:LASTEXITCODE = 1
    return
  }
  if ($args.Count -ge 1) {
    if ($args[0] -eq 'mirror') {
      if ($args.Count -gt 2) {
        $host.ui.WriteErrorLine('Usage: scoop mirror [<name>|official|status]')
        $global:LASTEXITCODE = 1
        return
      }
      $choice = if ($args.Count -eq 2) { [string]$args[1] } else { '' }
      _scoop_manage_mirror -Choice $choice
      return
    }
    if ($args[0] -eq 'services') {
      $svcArgs = @()
      if ($args.Count -gt 1) { $svcArgs = $args[1..($args.Count - 1)] }
      _scoop_manage_services @svcArgs
      return
    }
    if ($args[0] -eq 'uninstall') {
      $apps = @(_scoop_apps @args)
      if ($apps.Count -gt 0) {
        _scoop_prepare_uninstall @apps
        if ($LASTEXITCODE -ne 0) { return }
      }
      & $__scoop @args
      return
    }
  }
  if ($args.Count -ge 1 -and $args[0] -in @('update', 'install', 'import')) {
    _scoop_prepare_package_operation
    if ($LASTEXITCODE -ne 0) {
      $host.ui.WriteErrorLine('scoop: package operation aborted because the Scoop worktree is not clean')
      $global:LASTEXITCODE = 1
      return
    }
  }
  $updateApps = @()
  if ($args.Count -ge 1 -and $args[0] -eq 'update') {
    $updateApps = @(_scoop_apps @args)
    _scoop_prepare_update_services @updateApps
  }
  & $__scoop @args
  $ec = $LASTEXITCODE
  if ($args.Count -ge 1 -and $args[0] -eq 'update') {
    if ($ec -eq 0) { _scoop_restart_changed_services }
    _scoop_ensure_mirror_accel
  }
  $global:LASTEXITCODE = $ec
  return
}
