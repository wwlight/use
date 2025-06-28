#!/bin/bash

# ==============================
# 颜色定义和打印方法
# ==============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ==============================
# 系统环境检测
# ==============================
detect_system() {
    UNAME=$(uname -s)
    case "$UNAME" in
        Darwin*)
            echo "macOS"
            ;;
        Linux*)
            if [[ $(uname -r) == *microsoft* ]]; then
                echo "WSL"
            else
                echo "Linux"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "Windows"
            ;;
        *)
            error "不支持的系统类型: $UNAME"
            ;;
    esac
}

# ==============================
# 检查是否匹配目标系统
# ==============================
check_target_system() {
    local CURRENT_SYSTEM=$(detect_system)
    local TARGET_SYSTEM=$1

    if [[ "$CURRENT_SYSTEM" != "$TARGET_SYSTEM" ]]; then
        error "此脚本专为 $TARGET_SYSTEM 设计，当前系统是 $CURRENT_SYSTEM"
    fi
}
