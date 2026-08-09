# Scoop shell wrappers (`scoop mirror` / `scoop services` / winsw).

_scoop_ps_quote() {
  # Single-quote for PowerShell literals; escape embedded single quotes.
  local s=$1
  s=${s//\'/\'\'}
  print -r -- "'$s'"
}

_scoop_ps() {
  local file="$1"
  shift
  local ps_exe
  if command -v pwsh.exe >/dev/null 2>&1; then
    ps_exe=pwsh.exe
  elif command -v pwsh >/dev/null 2>&1; then
    ps_exe=pwsh
  else
    ps_exe=powershell.exe
  fi

  # Prefer a Windows path for -Command; MSYS /d/... paths are unreliable in pwsh.
  if command -v cygpath >/dev/null 2>&1; then
    file="$(cygpath -w "$file")"
  fi

  # Avoid `pwsh -File script.ps1 install nginx`: unbound tokens are often dropped.
  # Build an explicit PowerShell call so switches/args always reach the script.
  if (( $# == 0 )); then
    "$ps_exe" -NoProfile -ExecutionPolicy Bypass -File "$file"
    return $?
  fi
  local call="& $(_scoop_ps_quote "$file")"
  local a
  for a in "$@"; do
    # Keep -Switch tokens bare so PowerShell binds them as parameters.
    if [[ "$a" == -* ]]; then
      call+=" $a"
    else
      call+=" $(_scoop_ps_quote "$a")"
    fi
  done
  "$ps_exe" -NoProfile -ExecutionPolicy Bypass -Command "$call"
}

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

_scoop_config_dir() {
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    print -r -- "${XDG_CONFIG_HOME}/scoop"
  else
    print -r -- "${HOME}/.config/scoop"
  fi
}

_scoop_mirror_cli() {
  print -r -- "$(_scoop_config_dir)/mirror/cli.js"
}

_scoop_require_node() {
  command -v node >/dev/null 2>&1 && return 0
  echo "scoop: Node.js is required for scoop mirror" >&2
  return 1
}

# Presence: required = fail if cli missing (preflight); optional = skip if undeployed (post-update).
_scoop_run_mirror_repair() {
  local presence="${1:-required}"
  local cli
  cli="$(_scoop_mirror_cli)"
  if [[ ! -f "$cli" ]]; then
    [[ "$presence" == required ]] || return 0
    echo "scoop: mirror helper not found at $cli" >&2
    return 1
  fi
  _scoop_require_node || return 1
  node "$cli" repair
}

_scoop_ensure_mirror_hook() {
  _scoop_run_mirror_repair optional
}

_scoop_prepare_package_operation() {
  _scoop_run_mirror_repair required
}

_scoop_manage_mirror() {
  local cli
  cli="$(_scoop_mirror_cli)"
  [[ -f "$cli" ]] || {
    echo "scoop: mirror helper not found at $cli" >&2
    return 1
  }
  _scoop_require_node || return 1
  node "$cli" switch "${1:-}"
}

_scoop_services_helper() {
  print -r -- "$(_scoop_config_dir)/services/cli.ps1"
}

# Cheap gate before spawning pwsh for update-time service hooks.
_scoop_has_managed_services() {
  local d="${SCOOP}/persist" f
  [[ -d "$d" ]] || return 1
  for f in "$d"/*/*-winsw-service.xml(N); do
    [[ -f "$f" ]] && return 0
  done
  return 1
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
  _scoop_has_managed_services || return 0
  local p
  p="$(_scoop_services_helper)"
  [[ -f "$p" ]] || return 0
  _scoop_ps "$p" -PrepareUpdate "$@" >/dev/null 2>&1 || true
}

_scoop_restart_changed_services() {
  local snapshot="$(_scoop_config_dir)/services/.update-snapshot.json"
  [[ -f "$snapshot" ]] || return 0
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
      echo "Usage: scoop mirror [<name>|official|status]" >&2
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
    _scoop_ensure_mirror_hook
    return $ec
  else
    command scoop "$@"
  fi
}
