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
error() { printf "\033[31m[ERROR]\033[0m %s\n" "$1"; exit 1; }

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
  ensure_repo
  cd "$INSTALL_DIR"

  info "步骤 1/2: 安装包管理器 ..."
  bash scripts/mac/brew-install.sh

  info "步骤 2/2: 系统初始化 ..."
  bash scripts/mac/init.sh

  info "安装完成！"
}

# ---------- Windows ----------
install_windows() {
  ensure_repo
  cd "$INSTALL_DIR"

  info "步骤 1/2: 安装包管理器 ..."
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/scoop-install.ps1

  info "步骤 2/2: 系统初始化 ..."
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/init.ps1

  info "安装完成！"
}

# ---------- entry ----------
case "$OS" in
  macos)   install_macos ;;
  windows) install_windows ;;
  linux)   error "Linux 暂不支持" ;;
  *)       error "不支持的操作系统: $(uname -s)" ;;
esac
