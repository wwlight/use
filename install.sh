#!/bin/bash
set -e

REPO="https://github.com/wwlight/use.git"
INSTALL_DIR="${HOME}/Desktop/use"

# ---------- platform detection ----------
detect_os() {
  case "$(uname -s)" in
    Darwin)  echo "macos" ;;
    CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
    Linux)   echo "linux" ;;
    *)       echo "unknown" ;;
  esac
}

OS=$(detect_os)

# ---------- helpers ----------
info()  { printf "\033[32m[INFO]\033[0m %s\n" "$1"; }
step()  { printf "\033[35m[INFO]\033[0m %s\n" "$1"; }
error() { printf "\033[31m[ERROR]\033[0m %s\n" "$1"; exit 1; }

usage() {
  cat <<EOF
用法: install.sh [lite|full]

  lite  尝鲜版
  full  完整版
  （省略则初始化时交互选择）

示例:
  curl -fsSL <url> | bash -s -- lite
  USE_PROFILE=lite sh -c "\$(curl -fsSL <url>)"
EOF
}

# lite | full | 空（init 交互选择）
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

# ---------- clone / update repo ----------
ensure_repo() {
  if [ -d "$INSTALL_DIR/.git" ]; then
    info "仓库已存在，正在更新..."
    git -C "$INSTALL_DIR" pull --ff-only
  else
    info "正在克隆仓库到 $INSTALL_DIR ..."
    git clone --depth=1 "$REPO" "$INSTALL_DIR"
  fi
}

# ---------- macOS ----------
install_macos() {
  local profile="$1"
  ensure_repo
  cd "$INSTALL_DIR"

  step "步骤 1/2: 安装包管理器 ..."
  bash scripts/mac/brew-install.sh

  step "步骤 2/2: 系统初始化 ..."
  if [ -n "$profile" ]; then
    bash scripts/mac/init.sh "$profile"
  else
    bash scripts/mac/init.sh
  fi

  info "安装完成！"
}

# ---------- Windows ----------
install_windows() {
  local profile="$1"
  ensure_repo
  cd "$INSTALL_DIR"

  step "步骤 1/2: 安装包管理器 ..."
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/scoop-install.ps1

  step "步骤 2/2: 系统初始化 ..."
  if [ -n "$profile" ]; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1 "$profile"
  else
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1
  fi

  info "安装完成！"
}

# ---------- entry ----------
case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac

PROFILE=$(resolve_profile "$@")

case "$OS" in
  macos)   install_macos "$PROFILE" ;;
  windows) install_windows "$PROFILE" ;;
  linux)   error "Linux 暂不支持" ;;
  *)       error "不支持的操作系统: $(uname -s)" ;;
esac
