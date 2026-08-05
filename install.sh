#!/bin/bash
set -e

REPO="https://github.com/wwlight/use.git"
INSTALL_DIR="${HOME}/Desktop/use"
# BEGIN GENERATED GITHUB ACCEL
GITHUB_ACCEL_PREFIXES=(
  "https://ghfast.top/"
  "https://gh-proxy.com/"
)
# END GENERATED GITHUB ACCEL

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

info()  { printf "\033[32m[INFO] %s\033[0m\n" "$1" >&2; }
step()  { printf "\033[34m[INFO] %s\033[0m\n" "$1" >&2; }
error() { printf "\033[31m[ERROR] %s\033[0m\n" "$1" >&2; exit 1; }

usage() {
  cat <<EOF
用法: install.sh [lite|full]

  lite  尝鲜版
  full  完整版
  （省略则初始化时交互选择）

示例:
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
    *) error "未知参数: ${arg}（使用 lite / full）" ;;
  esac
}

# 规范化 git remote，便于比较是否同一仓库
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

github_repo_candidates() {
  local prefix
  for prefix in "${GITHUB_ACCEL_PREFIXES[@]}"; do
    printf '%s%s\n' "$prefix" "$REPO"
  done
  printf '%s\n' "$REPO"
}

clone_repo() {
  local target="$1" url
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    rm -rf "$target"
    info "正在尝试克隆: $url"
    if git clone --depth=1 "$url" "$target"; then
      return 0
    fi
  done < <(github_repo_candidates)
  error "克隆仓库失败"
}

update_repo() {
  local target="$1" url
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    git -C "$target" remote set-url origin "$url" || continue
    info "正在尝试同步: $url"
    if git -C "$target" fetch origin main; then
      git -C "$target" reset --hard origin/main || error "重置本地失败"
      return 0
    fi
  done < <(github_repo_candidates)
  error "拉取远程失败"
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
    clone_repo "$INSTALL_DIR"
    return
  fi

  if is_same_remote_repo "$target"; then
    INSTALL_DIR="$target"
    info "检测到已有仓库 ${INSTALL_DIR}，正在同步到 origin/main ..."
    update_repo "$INSTALL_DIR"
    return
  fi

  target=$(next_timestamped_dir "$INSTALL_DIR")
  INSTALL_DIR="$target"
  info "目录已占用，正在克隆到 $INSTALL_DIR ..."
  clone_repo "$INSTALL_DIR"
}

install_macos() {
  local profile="$1"
  ensure_repo
  cd "$INSTALL_DIR"

  # 进度：入口完成第 1 步，总数含后续 init 步数
  local init_steps=4
  export USE_STEP_CHAIN=1
  export USE_STEP_CURRENT=1
  export USE_STEP_TOTAL=$((USE_STEP_CURRENT + init_steps))
  step "步骤 ${USE_STEP_CURRENT}/${USE_STEP_TOTAL}: 安装包管理器 ..."
  bash scripts/macos/brew-install.sh ustc
  # shellcheck disable=SC1090
  [ -f "${HOME}/.zprofile" ] && . "${HOME}/.zprofile"

  if [ -n "$profile" ]; then
    bash scripts/macos/init.sh "$profile"
  else
    bash scripts/macos/init.sh
  fi

  info "安装完成！"
  # curl | bash 在子 shell 中执行，cd 无法影响父终端；通过 /dev/tty 进入交互 shell
  if [[ -c /dev/tty ]] && [[ -t 2 ]]; then
    exec "${SHELL:-/bin/zsh}" -l </dev/tty >/dev/tty 2>/dev/tty
  fi
}

case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac

case "$OS" in
  windows)
    error "检测到 windows。请改用 PowerShell：
  irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex"
    ;;
  linux) error "检测到 linux，暂不支持" ;;
  unknown) error "不支持的操作系统: $(uname -s 2>/dev/null || echo unknown)" ;;
esac

PROFILE=$(resolve_profile "$@")

case "$OS" in
  macos) install_macos "$PROFILE" ;;
  *)     error "不支持的操作系统: $(uname -s 2>/dev/null || echo unknown)" ;;
esac
