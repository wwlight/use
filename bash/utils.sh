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

# ==============================
# 清理函数
# ==============================
smart_clean() {
    local target="$1"
    if command -v rm &>/dev/null; then
        rm -rf "$target" 2>/dev/null || {
            warn "使用 rm 清理失败，尝试 Windows 方式..."
            target="${target//\//\\}"
            cmd /c "rmdir /S /Q \"$target\"" >nul 2>&1
        }
    else
        target="${target//\//\\}"
        cmd /c "rmdir /S /Q \"$target\"" >nul 2>&1
    fi
}


# ==============================
# 备份（支持自定义路径+日期序号+错误不中断）
# 使用方法: backup_file <目标文件> [备份目录]
# ==============================
backup_file() {
    local target_file="$1"
    local backup_dir="${2:-$(dirname "$target_file")}"  # 默认目标文件所在目录

    # 检查目标文件
    if [ ! -f "$target_file" ]; then
        warn "目标文件不存在: $target_file"
        return 0
    fi

    # 创建备份目录（如果不存在）
    if ! mkdir -p "$backup_dir"; then
        warn "无法创建备份目录: $backup_dir"
        return 0
    fi

    # 生成备份文件名（格式：原文件名.bak.年月日.序号）
    local file_name=$(basename "$target_file")
    local backup_base="${backup_dir}/${file_name}.bak.$(date +%Y%m%d)"
    local next_num=$(ls "${backup_base}."* 2>/dev/null | wc -l)
    local backup_file="${backup_base}.${next_num}"

    # 执行备份
    if cp "$target_file" "$backup_file" 2>/dev/null; then
        info "备份成功: $target_file -> $backup_file"
    else
        warn "备份失败: $target_file -> $backup_file"
    fi

    return 0
}
