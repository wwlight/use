#!/bin/bash
set -e

REPO="https://github.com/wwlight/use.git"
REPO_ZIP="https://github.com/wwlight/use/archive/refs/heads/main.zip"
INSTALL_DIR="${HOME}/Desktop/use"
ZIP_EXTRACT_NAME="use-main"
# BEGIN GENERATED GITHUB ACCEL
GITHUB_ACCEL_IDS=(
  "ghproxy"
  "ghfast"
)
GITHUB_ACCEL_PREFIXES=(
  "https://gh-proxy.com/"
  "https://ghfast.top/"
)
# END GENERATED GITHUB ACCEL

detect_os() {
  # Git Bash / MSYS / Cygwin: uname is MINGW*|MSYS*|CYGWIN*; fall back to OSTYPE / OS.
  local uname_s
  uname_s="$(uname -s 2>/dev/null || true)"
  case "$uname_s" in
    Darwin)  echo "macos" ;;
    CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
    Linux)   echo "linux" ;;
    *)
      case "${OSTYPE:-}" in
        msys*|cygwin*) echo "windows" ;;
        darwin*) echo "macos" ;;
        linux*) echo "linux" ;;
        *)
          if [ "${OS:-}" = "Windows_NT" ] || [ -n "${WINDIR:-}" ]; then
            echo "windows"
          else
            echo "unknown"
          fi
          ;;
      esac
      ;;
  esac
}

OS=$(detect_os)

info()  { printf "\033[32m[INFO] %s\033[0m\n" "$1" >&2; }
step()  { printf "\033[34m[INFO] %s\033[0m\n" "$1" >&2; }
error() { printf "\033[31m[ERROR] %s\033[0m\n" "$1" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: install.sh [lite|full]

  lite  Lite setup
  full  Full setup
  (omit to choose interactively during initialization)

Examples:
  curl -fsSL <url> | bash
  curl -fsSL <url> | bash -s -- lite
  curl -fsSL <url> | bash -s -- full
EOF
}

resolve_profile() {
  while [[ "${1:-}" == "--" ]]; do shift; done
  local arg="${1:-${USE_PROFILE:-}}"
  case "$arg" in
    ""|lite|full) echo "$arg" ;;
    --lite) echo lite ;;
    --full) echo full ;;
    *) error "Unknown argument: ${arg} (use lite or full)" ;;
  esac
}

# Normalize Git remotes for repository comparison.
strip_github_accel_prefix() {
  local url="$1" prefix
  for prefix in "${GITHUB_ACCEL_PREFIXES[@]}"; do
    case "$url" in
      "$prefix"*) printf '%s' "${url#"$prefix"}"; return ;;
    esac
  done
  printf '%s' "$url"
}

normalize_repo_url() {
  local u
  u=$(strip_github_accel_prefix "$1")
  while [ "${u%/}" != "$u" ]; do u="${u%/}"; done
  case "$u" in
    *.git) u="${u%.git}" ;;
  esac
  u="${u#https://}"
  u="${u#http://}"
  u="${u#ssh://git@}"
  u="${u#git@}"
  u="${u//://}"
  printf '%s' "$u"
}

is_same_remote_repo() {
  local dir="$1"
  [ -d "$dir/.git" ] || return 1
  local remote
  remote=$(git -C "$dir" remote get-url origin 2>/dev/null) || return 1
  [ "$(normalize_repo_url "$remote")" = "$(normalize_repo_url "$REPO")" ]
}

# Resolve USE_ACCEL=<id> (set by mirrored one-liners) to a known prefix.
resolve_accel_prefix() {
  local accel="${USE_ACCEL:-}" i
  [ -n "$accel" ] || return 0
  for i in "${!GITHUB_ACCEL_IDS[@]}"; do
    if [ "${GITHUB_ACCEL_IDS[$i]}" = "$accel" ]; then
      printf '%s' "${GITHUB_ACCEL_PREFIXES[$i]}"
      return 0
    fi
  done
}

github_repo_candidates() {
  local preferred prefix
  preferred=$(resolve_accel_prefix)
  if [ -n "$preferred" ]; then
    printf '%s%s\n' "$preferred" "$REPO"
  fi
  for prefix in "${GITHUB_ACCEL_PREFIXES[@]}"; do
    [ "$prefix" = "$preferred" ] && continue
    printf '%s%s\n' "$prefix" "$REPO"
  done
  printf '%s\n' "$REPO"
}

github_zip_candidates() {
  local preferred prefix
  preferred=$(resolve_accel_prefix)
  if [ -n "$preferred" ]; then
    printf '%s%s\n' "$preferred" "$REPO_ZIP"
  fi
  for prefix in "${GITHUB_ACCEL_PREFIXES[@]}"; do
    [ "$prefix" = "$preferred" ] && continue
    printf '%s%s\n' "$prefix" "$REPO_ZIP"
  done
  printf '%s\n' "$REPO_ZIP"
}

github_url_candidates() {
  local bare="$1" preferred prefix
  preferred=$(resolve_accel_prefix)
  if [ -n "$preferred" ]; then
    printf '%s%s\n' "$preferred" "$bare"
  fi
  for prefix in "${GITHUB_ACCEL_PREFIXES[@]}"; do
    [ "$prefix" = "$preferred" ] && continue
    printf '%s%s\n' "$prefix" "$bare"
  done
  printf '%s\n' "$bare"
}

download_zip_repo() {
  local target="$1" url tmp zipfile parent
  parent=$(dirname "$target")
  mkdir -p "$parent"
  tmp=$(mktemp -d "${parent}/use-zip.XXXXXX") || return 1
  zipfile="${tmp}/use-main.zip"

  while IFS= read -r url; do
    [ -n "$url" ] || continue
    info "Trying zip URL: $url"
    rm -f "$zipfile"
    if ! curl -fsSL --connect-timeout 15 --max-time 300 -o "$zipfile" "$url"; then
      continue
    fi
    rm -rf "${tmp}/${ZIP_EXTRACT_NAME}" "$target"
    if ! unzip -q "$zipfile" -d "$tmp"; then
      continue
    fi
    if [ ! -d "${tmp}/${ZIP_EXTRACT_NAME}" ]; then
      continue
    fi
    mv "${tmp}/${ZIP_EXTRACT_NAME}" "$target"
    rm -rf "$tmp"
    info "Extracted repository to $target"
    return 0
  done < <(github_zip_candidates)

  rm -rf "$tmp"
  return 1
}

clone_repo() {
  local target="$1" url
  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    rm -rf "$target"
    info "Trying clone URL: $url"
    if git clone --depth=1 "$url" "$target"; then
      return 0
    fi
  done < <(github_repo_candidates)
  return 1
}

fetch_repo() {
  local target="$1"
  if download_zip_repo "$target"; then
    return 0
  fi
  printf "\033[33m[WARN] %s\033[0m\n" "Zip download failed; falling back to git clone..." >&2
  if clone_repo "$target"; then
    return 0
  fi
  rm -rf "$target"
  error "Failed to fetch repository (zip and git clone both failed). Try another USE_ACCEL mirror or check the network."
}

update_repo() {
  local target="$1" url
  if ! command -v git >/dev/null 2>&1; then
    error "Git is required to update an existing repository checkout"
  fi
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    git -C "$target" remote set-url origin "$url" || continue
    info "Trying sync URL: $url"
    if git -C "$target" fetch origin main; then
      git -C "$target" reset --hard origin/main || error "Failed to reset local repository"
      return 0
    fi
  done < <(github_repo_candidates)
  error "Failed to fetch remote repository"
}

next_timestamped_dir() {
  local base="$1"
  local ts target
  ts=$(date +%Y%m%d-%H%M%S)
  target="${base}-${ts}"
  while [ -e "$target" ]; do
    sleep 1
    ts=$(date +%Y%m%d-%H%M%S)
    target="${base}-${ts}"
  done
  printf '%s' "$target"
}

ensure_repo() {
  local target="$INSTALL_DIR"

  if [ ! -e "$target" ]; then
    INSTALL_DIR="$target"
    info "Fetching repository to $INSTALL_DIR ..."
    fetch_repo "$INSTALL_DIR"
    return
  fi

  if is_same_remote_repo "$target"; then
    INSTALL_DIR="$target"
    info "Existing repository found at ${INSTALL_DIR}; syncing with origin/main ..."
    update_repo "$INSTALL_DIR"
    return
  fi

  target=$(next_timestamped_dir "$INSTALL_DIR")
  INSTALL_DIR="$target"
  info "Directory is in use; fetching to $INSTALL_DIR ..."
  fetch_repo "$INSTALL_DIR"
}

ensure_node() {
  if [ -d "${HOME}/.vite-plus/bin" ]; then
    export PATH="${HOME}/.vite-plus/bin:${PATH}"
  fi

  if ! command -v node >/dev/null 2>&1; then
    info "Node.js was not found."
    if [[ ! -c /dev/tty ]]; then
      error "Node.js is required. Install vite-plus (includes Node) or Node itself, then rerun:
  curl -fsSL https://vite.plus | bash
  # or: https://nodejs.org/"
    fi

    printf '\nInstall Node.js via vite-plus? (https://vite.plus)\n' >/dev/tty
    printf '  Y / Enter  install vite-plus (manages Node)\n' >/dev/tty
    printf '  N          cancel\n' >/dev/tty
    printf 'Proceed: ' >/dev/tty
    local answer
    IFS= read -r answer </dev/tty || answer=n
    case "$answer" in
      n|N|no|NO)
        error "Node.js is required. Install from https://vite.plus or https://nodejs.org/, then rerun."
        ;;
    esac

    info "Installing Node.js via vite-plus..."
    export VP_NODE_MANAGER=yes
    local url script
    while IFS= read -r url; do
      [ -n "$url" ] || continue
      info "Trying vite-plus installer: $url"
      if ! script=$(curl -fsSL "$url"); then
        info "vite-plus installer fetch failed: $url"
        continue
      fi
      case "$script" in
        *setup_node_manager*) ;;
        *) info "Response does not look like the vite-plus installer"; continue ;;
      esac
      if printf '%s\n' "$script" | bash; then
        [ -d "${HOME}/.vite-plus/bin" ] && export PATH="${HOME}/.vite-plus/bin:${PATH}"
        if command -v node >/dev/null 2>&1; then
          break
        fi
        error "vite-plus finished but node is unavailable in this session; open a new terminal and rerun"
      fi
      info "vite-plus installer failed: $url"
    done < <(github_url_candidates "https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli/install.sh")
  fi

  if ! command -v node >/dev/null 2>&1; then
    error "Failed to install Node.js via vite-plus. Install manually from https://vite.plus or https://nodejs.org/, then rerun."
  fi
  local major
  major=$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)
  if [ "${major:-0}" -lt 18 ]; then
    error "Node.js >= 18 is required (found $(node -v))"
  fi
  info "Using Node $(node -v)"
}

run_cli() {
  node "$INSTALL_DIR/src/cli.js" "$@"
}

install_macos() {
  local profile="$1"
  ensure_node
  ensure_repo
  cd "$INSTALL_DIR"

  # The installer completes step 1; the total includes subsequent init steps.
  local init_steps=4
  export USE_STEP_CHAIN=1
  export USE_STEP_CURRENT=1
  export USE_STEP_TOTAL=$((USE_STEP_CURRENT + init_steps))
  # curl|bash pipes stdin; menus still talk to /dev/tty when present.
  if [[ -c /dev/tty ]]; then
    export SYNC_INTERACTIVE=1
  fi
  step "Step ${USE_STEP_CURRENT}/${USE_STEP_TOTAL}: Installing package manager ..."
  run_cli pm

  if [ -n "$profile" ]; then
    run_cli init -- "$profile"
  else
    run_cli init
  fi

  info "Installation complete!"
  # curl | bash runs in a subshell; start an interactive shell through /dev/tty.
  if [[ -c /dev/tty ]] && [[ -t 2 ]]; then
    exec "${SHELL:-/bin/zsh}" -l </dev/tty >/dev/tty 2>/dev/tty
  fi
}

case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac

case "$OS" in
  windows)
    error "Windows detected. Use PowerShell instead:
  irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex"
    ;;
  linux) error "Linux is not currently supported" ;;
  unknown) error "Unsupported operating system: $(uname -s 2>/dev/null || echo unknown)" ;;
esac

PROFILE=$(resolve_profile "$@")

case "$OS" in
  macos) install_macos "$PROFILE" ;;
  *)     error "Unsupported operating system: $(uname -s 2>/dev/null || echo unknown)" ;;
esac
