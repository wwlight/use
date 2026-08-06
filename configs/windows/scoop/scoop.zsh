# Scoop shell wrappers (mirror + services). Logic lives under $SCOOP/config/.
# Prefer pwsh over Windows PowerShell 5 to cut helper cold-start cost.

_scoop_ps() {
  local file="$1"
  shift
  if command -v pwsh.exe >/dev/null 2>&1; then
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "$file" "$@"
    return $?
  fi
  if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$file" "$@"
    return $?
  fi
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$file" "$@"
}

# Interactive winsw hot path (kept in-shell; services/manage.ps1 has the manager copy).
winsw() {
  if (( $# >= 2 )); then
    [[ -n "$SCOOP" ]] || { echo "winsw: \$SCOOP is not set" >&2; return 1 }
    local xml="${SCOOP}/persist/${2}/${2}-winsw-service.xml"
    if [[ -f "$xml" ]]; then
      local winsw_exe="${SCOOP}/apps/winsw-pre/current/WinSW.exe"
      if [[ ! -f "$winsw_exe" ]]; then
        echo "winsw: WinSW not found at $winsw_exe (run 'scoop install winsw-pre')" >&2
        return 1
      fi
      "$winsw_exe" "$1" "$xml" "${@:3}"
      return
    fi
    if [[ "$1" == "status" ]]; then print -r -- "NonExistent"; return; fi
    if [[ "$1" == "stop" ]]; then sc.exe stop "$2"; return $?; fi
    if [[ "$1" == "uninstall" ]]; then sc.exe delete "$2"; return $?; fi
  fi
  winsw.exe "$@"
}

_scoop_ensure_mirror_accel() {
  local p="${SCOOP}/config/scoop-mirror/hook.ps1"
  local cli="${SCOOP}/config/scoop-mirror/cli.mjs"
  [[ -f "$p" ]] || return 0
  # Node repair owns fast-path + rewrite; PS -RepairHook is no-Node fallback only.
  if [[ -f "$cli" ]] && command -v node >/dev/null 2>&1; then
    node "$cli" repair >/dev/null
    return $?
  fi
  _scoop_ps "$p" -RepairHook
}

_scoop_prepare_package_operation() {
  local p="${SCOOP}/config/scoop-mirror/hook.ps1"
  local cli="${SCOOP}/config/scoop-mirror/cli.mjs"
  [[ -f "$p" ]] || {
    echo "scoop: mirror preflight helper not found at $p" >&2
    return 1
  }
  if [[ -f "$cli" ]] && command -v node >/dev/null 2>&1; then
    node "$cli" repair
    return $?
  fi
  _scoop_ps "$p" -PrepareCommand
}

_scoop_manage_mirror() {
  local cli="${SCOOP}/config/scoop-mirror/cli.mjs"
  if [[ -f "$cli" ]] && command -v node >/dev/null 2>&1; then
    node "$cli" switch "${1:-}"
    return $?
  fi
  local p="${SCOOP}/config/scoop-mirror/manage.ps1"
  [[ -f "$p" ]] || {
    echo "scoop: mirror helper not found at $p" >&2
    return 1
  }
  _scoop_ps "$p" -MirrorChoice "${1:-}"
}

_scoop_services_helper() {
  print -r -- "${SCOOP}/config/scoop-services/manage.ps1"
}

_scoop_manage_services() {
  local p
  p="$(_scoop_services_helper)"
  [[ -f "$p" ]] || {
    echo "scoop: services helper not found at $p (re-run vpr pm / sync)" >&2
    return 1
  }
  _scoop_ps "$p" "$@"
}

_scoop_prepare_uninstall() {
  local p
  p="$(_scoop_services_helper)"
  (( $# )) || return 0
  if [[ ! -f "$p" ]]; then
    echo "scoop: services helper not found at $p (re-run vpr pm / sync); refusing uninstall without service cleanup" >&2
    return 1
  fi
  _scoop_ps "$p" -PrepareUninstall "$@"
}

_scoop_prepare_update_services() {
  local p
  p="$(_scoop_services_helper)"
  [[ -f "$p" ]] || return 0
  _scoop_ps "$p" -PrepareUpdate "$@" >/dev/null 2>&1 || true
}

_scoop_restart_changed_services() {
  local p
  p="$(_scoop_services_helper)"
  [[ -f "$p" ]] || return 0
  _scoop_ps "$p" -RestartChanged || {
    echo "scoop: service restart after update failed" >&2
    return 0
  }
}

_scoop_apps_from() {
  for arg in "$@"; do
    [[ "$arg" != -* ]] && print -r -- "$arg"
  done
}

scoop() {
  [[ -n "$SCOOP" ]] || { echo "scoop: \$SCOOP is not set" >&2; return 1 }
  if [[ "$1" == "mirror" ]]; then
    if (( $# > 2 )); then
      echo "Usage: scoop mirror [<name>|official]" >&2
      return 1
    fi
    _scoop_manage_mirror "${2:-}"
    return $?
  fi
  if [[ "$1" == "services" ]]; then
    shift
    _scoop_manage_services "$@"
    return $?
  fi
  if [[ "$1" == "update" || "$1" == "install" || "$1" == "import" ]]; then
    _scoop_prepare_package_operation || {
      echo "scoop: package operation aborted because the Scoop worktree is not clean" >&2
      return 1
    }
  fi

  if [[ "$1" == "uninstall" ]]; then
    local apps
    apps=($(_scoop_apps_from "${@:2}"))
    _scoop_prepare_uninstall "${apps[@]}" || return $?
    command scoop "$@"
  elif [[ "$1" == "update" ]]; then
    local apps ec
    apps=($(_scoop_apps_from "${@:2}"))
    _scoop_prepare_update_services "${apps[@]}"
    command scoop "$@"
    ec=$?
    if (( ec == 0 )); then
      _scoop_restart_changed_services
    fi
    _scoop_ensure_mirror_accel
    return $ec
  else
    command scoop "$@"
  fi
}
