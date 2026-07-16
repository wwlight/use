#!/bin/bash
set -e

REPO="https://github.com/wwlight/use.git"
INSTALL_DIR="${HOME}/Desktop/use"

detect_os() {
  # Git Bash / MSYS / Cygwin: uname is MINGW*|MSYS*|CYGWIN*；再兜底 OSTYPE / OS
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

info()  { printf "\033[32m[INFO] %s\033[0m\n" "$1"; }
step()  { printf "\033[35m[INFO] %s\033[0m\n" "$1"; }
error() { printf "\033[31m[ERROR] %s\033[0m\n" "$1"; exit 1; }

usage() {
  cat <<EOF
用法: install.sh [lite|full]

  lite  尝鲜版
  full  完整版
  （省略则初始化时交互选择）

示例:
  curl -fsSL <url> | bash
  curl -fsSL <url> | bash -s -- lite
EOF
}

resolve_profile() {
  while [[ "${1:-}" == "--" ]]; do shift; done
  local arg="${1:-${USE_PROFILE:-}}"
  case "$arg" in
    ""|lite|full) echo "$arg" ;;
    --lite) echo lite ;;
    --full) echo full ;;
    *) error "未知参数: ${arg}（使用 lite / full）" ;;
  esac
}

normalize_repo_url() {
  local u="${1%.git}"
  u="${u%/}"
  u="${u#https://}"
  u="${u#http://}"
  u="${u#ssh://git@}"
  u="${u#git@}"
  u="${u/://}"
  printf '%s' "$u"
}

is_same_remote_repo() {
  local dir="$1"
  [ -d "$dir/.git" ] || return 1
  local remote
  remote=$(git -C "$dir" remote get-url origin 2>/dev/null) || return 1
  [ "$(normalize_repo_url "$remote")" = "$(normalize_repo_url "$REPO")" ]
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
    info "正在克隆仓库到 $INSTALL_DIR ..."
    git clone --depth=1 "$REPO" "$INSTALL_DIR"
    return
  fi

  if is_same_remote_repo "$target"; then
    INSTALL_DIR="$target"
    info "检测到已有仓库 ${INSTALL_DIR}，正在强制同步到 origin/main ..."
    git -C "$INSTALL_DIR" fetch origin main || error "拉取远程失败"
    git -C "$INSTALL_DIR" reset --hard origin/main || error "重置本地失败"
    return
  fi

  target=$(next_timestamped_dir "$INSTALL_DIR")
  INSTALL_DIR="$target"
  info "目录已占用，正在克隆到 $INSTALL_DIR ..."
  git clone --depth=1 "$REPO" "$INSTALL_DIR"
}

install_macos() {
  local profile="$1"
  ensure_repo
  cd "$INSTALL_DIR"

  step "步骤 1/2: 安装包管理器 ..."
  bash scripts/mac/brew-install.sh ustc
  # shellcheck disable=SC1090
  [ -f "${HOME}/.zprofile" ] && . "${HOME}/.zprofile"

  step "步骤 2/2: 系统初始化 ..."
  if [ -n "$profile" ]; then
    bash scripts/mac/init.sh "$profile"
  else
    bash scripts/mac/init.sh
  fi

  info "安装完成！"
}

case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac

case "$OS" in
  windows)
    error "检测到 Windows（含 Git Bash / MSYS / Cygwin）。请改用 PowerShell：
  irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex"
    ;;
  linux) error "Linux 暂不支持" ;;
  unknown) error "不支持的操作系统: $(uname -s 2>/dev/null || echo unknown)" ;;
esac

PROFILE=$(resolve_profile "$@")

case "$OS" in
  macos) install_macos "$PROFILE" ;;
  *)     error "不支持的操作系统: $(uname -s 2>/dev/null || echo unknown)" ;;
esac
