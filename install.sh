#!/bin/bash
set -e

REPO="https://github.com/wwlight/use.git"
INSTALL_DIR="${HOME}/Desktop/use"
# BEGIN GENERATED GITHUB ACCEL
GITHUB_ACCEL_IDS=(
  "ghfast"
  "ghproxy"
)
GITHUB_ACCEL_PREFIXES=(
  "https://ghfast.top/"
  "https://gh-proxy.com/"
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

clone_repo() {
  local target="$1" url
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    rm -rf "$target"
    info "Trying clone URL: $url"
    if git clone --depth=1 "$url" "$target"; then
      return 0
    fi
  done < <(github_repo_candidates)
  error "Failed to clone repository"
}

update_repo() {
  local target="$1" url
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
    info "Cloning repository to $INSTALL_DIR ..."
    clone_repo "$INSTALL_DIR"
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
  info "Directory is in use; cloning to $INSTALL_DIR ..."
  clone_repo "$INSTALL_DIR"
}

install_macos() {
  local profile="$1"
  ensure_repo
  cd "$INSTALL_DIR"

  # The installer completes step 1; the total includes subsequent init steps.
  local init_steps=4
  export USE_STEP_CHAIN=1
  export USE_STEP_CURRENT=1
  export USE_STEP_TOTAL=$((USE_STEP_CURRENT + init_steps))
  step "Step ${USE_STEP_CURRENT}/${USE_STEP_TOTAL}: Installing package manager ..."
  # Same path as vpr pm: interactive select, or USE_BREW_MIRROR=<id> for non-interactive.
  bash scripts/macos/brew-install.sh

  if [ -n "$profile" ]; then
    bash scripts/macos/init.sh "$profile"
  else
    bash scripts/macos/init.sh
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
