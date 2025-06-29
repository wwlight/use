#!/bin/bash

# ==============================
# 颜色定义和打印方法
# ==============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ==============================
# 系统环境检测
# ==============================
detect_system() {
    case "$(uname -s)" in
        Darwin*)  echo "macOS";;
        Linux*)   [[ $(uname -r) == *microsoft* ]] && echo "WSL" || echo "Linux";;
        CYGWIN*|MINGW*|MSYS*) echo "Windows";;
        *)        error "不支持的系统类型";;
    esac
}

# ==============================
# 检查是否匹配目标系统
# ==============================
check_target_system() {
    local current=$(detect_system)
    [[ "$current" != "$1" ]] && error "本脚本仅支持 $1 系统，检测到当前系统为 $current"
}
