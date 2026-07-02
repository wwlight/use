# scoop services（winsw）
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

scoop() {
  [[ -n "$SCOOP" ]] || { echo "scoop: \$SCOOP is not set" >&2; return 1 }

  if [[ "$1" == "uninstall" ]]; then
    for app in $(_scoop_apps_from "${@:2}"); do
      if _scoop_manifest_has "$app" 2>/dev/null; then
        local xml="${SCOOP}/persist/${app}/${app}-winsw-service.xml"
        if [[ -f "$xml" ]]; then
          local _s=$(winsw status "$app")
          _s="${_s%"${_s##*[![:space:]]}"}"
          if [[ "$_s" != *NonExistent* ]]; then
            winsw stop "$app"
            winsw uninstall "$app"
            rm -f "${SCOOP}/persist/${app}/${app}-winsw-service.xml"
          fi
        fi
      fi
    done
    command scoop "$@"
  elif [[ "$1" == "services" ]]; then
    shift
    _scoop_services "$@"
  else
    command scoop "$@"
  fi
}

_scoop_apps_from() {
  for arg in "$@"; do
    [[ "$arg" != -* ]] && print -r -- "$arg"
  done
}

_scoop_load_manifest_raw() {
  local path="${SCOOP}/config/services-manifest.json"
  if [[ ! -f "$path" ]]; then
    echo "Service manifest not found at $path" >&2
    return 1
  fi
  local data="" line
  while IFS= read -r line; do
    data+="$line"$'\n'
  done < "$path"
  print -r -- "$data"
}

_scoop_manifest_has() {
  local manifest="$(_scoop_load_manifest_raw)" || return 1
  [[ "$manifest" == *"\"$1\": {"* ]]
}

_scoop_manifest_val() {
  local app="$1" key="$2"
  local manifest="$(_scoop_load_manifest_raw)" || return 1
  local rest="${manifest#*\"${app}\": {}"
  [[ "$rest" != "$manifest" ]] || return 1
  local line="${rest#*\"${key}\": \"}"
  [[ "$line" != "$rest" ]] || return 1
  local val="${line%%\",*}"
  val="${val//\\\"/\"}"
  print -r -- "$val"
}

_ensure_winsw_xml() {
  local app="$1"
  _scoop_manifest_has "$app" || { echo "'$app' is not in service manifest" >&2; return 1 }

  local xml="${SCOOP}/persist/${app}/${app}-winsw-service.xml"
  [[ -f "$xml" ]] && return 0

  mkdir -p "${SCOOP}/persist/${app}"

  local exe args stop_exe stop_args
  exe=$(_scoop_manifest_val "$app" "executable") || return 1
  args=$(_scoop_manifest_val "$app" "arguments")
  stop_exe=$(_scoop_manifest_val "$app" "stopexecutable")
  stop_args=$(_scoop_manifest_val "$app" "stoparguments")

  [[ -z "$stop_exe" ]] && stop_exe="$exe"

  local exe_path="%BASE%/../../apps/${app}/current/${exe}"
  local stop_path="%BASE%/../../apps/${app}/current/${stop_exe}"
  local args_xml=""
  [[ -n "$args" ]] && args_xml=$'\n'"  <arguments>${args}</arguments>"
  local stop_args_xml=""
  [[ -n "$stop_args" ]] && stop_args_xml=$'\n'"  <stoparguments>${stop_args}</stoparguments>"

  cat > "$xml" <<EOF
<service>
  <id>${app}</id>
  <name>${app}</name>
  <description>${app} server (managed by WinSW)</description>
  <executable>${exe_path}</executable>${args_xml}
  <stopexecutable>${stop_path}</stopexecutable>${stop_args_xml}
  <log mode="roll" />
  <onfailure action="restart" delay="10 sec" />
  <onfailure action="restart" delay="20 sec" />
</service>
EOF
  echo "Generated: ${SCOOP}\\persist\\${app}\\${app}-winsw-service.xml"
  return 0
}

_scoop_services_list() {
  local winsw_exe="${SCOOP}/apps/winsw-pre/current/WinSW.exe"
  if [[ ! -f "$winsw_exe" ]]; then
    echo "winsw: WinSW not found at $winsw_exe (run 'scoop install winsw-pre')" >&2
    return 1
  fi
  local xmls=(${SCOOP}/persist/*/*-winsw-service.xml(N))
  local name state
  printf "%-15s %-15s %s\n" "Name" "Status" "Path"
  for xml in $xmls; do
    name="${xml:h:t}"
    state=$("$winsw_exe" status "$xml" 2>/dev/null)
    state="${state%"${state##*[![:space:]]}"}"
    case "$state" in
      "Active (running)") state="started" ;;
      "Inactive (stopped)") state="stopped" ;;
      "NonExistent") state="not installed" ;;
      *) state="unknown" ;;
    esac
    printf "%-15s %-15s %s\n" "$name" "$state" "$xml"
  done
}

_scoop_services_help() {
  echo "Usage: scoop services <command> [name]"
  echo ""
  echo "Commands:"
  echo "  ls|list                List all managed services"
  echo "  install     <name>     Register and start a service"
  echo "  uninstall   <name>     Unregister a service"
  echo "  start       <name>     Start a service"
  echo "  restart     <name>     Restart a service"
  echo "  stop        <name>     Stop a service"
}

_scoop_services() {
  local action="${1:-ls}"
  local svc="$2"
  case "$action" in
    ls|list) _scoop_services_list ;;
    install)
      if [[ -n "$svc" ]]; then
        _scoop_manifest_has "$svc" || { echo "'$svc' is not in service manifest"; return 1 }
        _ensure_winsw_xml "$svc" || return
        local _s=$(winsw status "$svc")
        _s="${_s%"${_s##*[![:space:]]}"}"
        if [[ "$_s" == *NonExistent* ]]; then
          winsw install "$svc" && winsw start "$svc"
        else
          echo "Service '$svc ($svc)' already registered ($_s)"
        fi
      else
        echo "Usage: scoop services install <name>"
      fi
      ;;
    uninstall)
      if [[ -n "$svc" ]]; then
        local _s=$(winsw status "$svc")
        _s="${_s%"${_s##*[![:space:]]}"}"
        if [[ "$_s" != *NonExistent* ]]; then
          winsw stop "$svc"
          winsw uninstall "$svc"
          rm -f "${SCOOP}/persist/${svc}/${svc}-winsw-service.xml"
        else
          echo "Service '$svc ($svc)' not registered"
        fi
      else
        echo "Usage: scoop services uninstall <name>"
      fi
      ;;
    start|stop|restart)
      if [[ -n "$svc" ]]; then
        winsw "$action" "$svc"
      else
        echo "Usage: scoop services $action <name>"
      fi
      ;;
    help|-h|--help) _scoop_services_help ;;
    *)
      echo "Usage: scoop services <command> [name]"
      echo "  Use 'scoop services help' for details"
      ;;
  esac
}
