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
  fi
  winsw.exe "$@"
}

scoop() {
  [[ -n "$SCOOP" ]] || { echo "scoop: \$SCOOP is not set" >&2; return 1 }
  if [[ "$1" == "install" && " $* " == *" --services "* ]]; then
    local filtered=()
    for arg in "$@"; do
      [[ "$arg" != "--services" ]] && filtered+=("$arg")
    done
    command scoop "${filtered[@]}" || return
    for app in $(_scoop_apps_from "${@:2}"); do
      _ensure_winsw_xml "$app"
      local _s=$(winsw status "$app"); _s="${_s%"${_s##*[![:space:]]}"}"
      if [[ "$_s" == "NonExistent" ]]; then
        winsw install "$app" && winsw start "$app"
      else
        echo "Service '$app ($app)' already registered"
      fi
    done
  elif [[ "$1" == "uninstall" ]]; then
    local filtered=()
    for arg in "$@"; do
      [[ "$arg" != "--services" ]] && filtered+=("$arg")
    done
    for app in $(_scoop_apps_from "${@:2}"); do
      local xml="${SCOOP}/persist/${app}/${app}-winsw-service.xml"
      if [[ -f "$xml" ]]; then
        local _s=$(winsw status "$app"); _s="${_s%"${_s##*[![:space:]]}"}"
        if [[ "$_s" != "NonExistent" ]]; then
          winsw uninstall "$app"
        else
          echo "Service '$app ($app)' not registered, skipping"
        fi
      fi
    done
    command scoop "${filtered[@]}"
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

_ensure_winsw_xml() {
  local app="$1"
  local xml="${SCOOP}/persist/${app}/${app}-winsw-service.xml"
  if [[ ! -f "$xml" ]]; then
    mkdir -p "${SCOOP}/persist/${app}"
    local basename="${app}.exe"
    local exe_dir="${SCOOP}/apps/${app}/current"
    local matches=()
    if [[ -d "$exe_dir" ]]; then
      matches=("$exe_dir"/*.exe(N))
      if (( ${#matches} == 0 )) && [[ -d "$exe_dir/bin" ]]; then
        matches=("$exe_dir/bin"/*.exe(N))
      fi
    fi
    local subdir=""
    if (( ${#matches} > 0 )); then
      local found=0
      for f in $matches; do
        local base="${f:t}"
        if [[ "${base:l}" == "${app}.exe" ]]; then
          local d="${f%"$base"}"
          d="${d#$exe_dir/}"
          subdir="${${d#/}%/}"
          basename="$base"
          found=1
          break
        fi
      done
      if (( ! found )); then
        local base="${matches[1]:t}"
        local d="${matches[1]%"$base"}"
        d="${d#$exe_dir/}"
        subdir="${${d#/}%/}"
        basename="$base"
        echo "  (auto-detected executable: ${subdir:+"$subdir/"}$basename)" >&2
      fi
    fi
    local winpath="apps\\${app}\\current"
    [[ -n "$subdir" ]] && winpath="${winpath}\\${subdir}"
    winpath="${winpath}\\${basename}"
    cat > "$xml" <<EOF
<service>
  <id>${app}</id>
  <name>${app}</name>
  <description>${app} server (managed by WinSW)</description>
  <executable>%BASE%\..\..\\${winpath}</executable>
  <stopexecutable>%BASE%\..\..\\${winpath}</stopexecutable>
  <log mode="roll" />
  <onfailure action="restart" delay="10 sec" />
  <onfailure action="restart" delay="20 sec" />
</service>
EOF
    local msgpath="${SCOOP}\\persist\\${app}\\${app}-winsw-service.xml"
    echo "Generated: $msgpath"
    echo "Tip: edit the XML to add <arguments>/<stoparguments> if needed"
  fi
  [[ -f "$xml" ]]
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
    local winpath="${SCOOP}\\persist\\${name}\\${name}-winsw-service.xml"
    printf "%-15s %-15s %s\n" "$name" "$state" "$winpath"
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
  echo "  stop        <name>     Stop a service"
  echo "  restart     <name>     Restart a service"
}

_scoop_services() {
  local action="${1:-ls}"
  local svc="$2"
  case "$action" in
    ls|list) _scoop_services_list ;;
    install)
      if [[ -n "$svc" ]]; then
        _ensure_winsw_xml "$svc"
        local _s=$(winsw status "$svc"); _s="${_s%"${_s##*[![:space:]]}"}"
        if [[ "$_s" == "NonExistent" ]]; then
          winsw install "$svc" && winsw start "$svc"
        else
          echo "Service '$svc ($svc)' already registered"
        fi
      else
        echo "Usage: scoop services install <name>"
      fi
      ;;
    uninstall)
      if [[ -n "$svc" ]]; then
        winsw uninstall "$svc"
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
