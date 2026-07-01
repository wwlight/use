#!/bin/bash

# ==============================
# 颜色定义和打印方法
# ==============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

safe_echo() {
    if command -v printf >/dev/null && printf "%b" "$1" >/dev/null 2>&1; then
        printf "%b\n" "$1"
    elif echo -e "$1" >/dev/null 2>&1; then
        echo -e "$1"
    else
        echo "$1"
    fi
}

info() { safe_echo "${GREEN}[INFO]${NC} $1"; }
warn() { safe_echo "${YELLOW}[WARN]${NC} $1"; }
error() { safe_echo "${RED}[ERROR]${NC} $1"; exit 1; }

# ==============================
# 系统环境检测
# ==============================
detect_system() {
    if command -v uname &>/dev/null; then
        case "$(uname -s)" in
            Darwin*)  echo "macOS";;
            Linux*)   [[ $(uname -r) == *microsoft* ]] && echo "WSL" || echo "Linux";;
            CYGWIN*|MINGW*|MSYS*) echo "Windows";;
            *)        echo "Unknown";;
        esac
    else
        if [[ "$OSTYPE" == "win32" || "$OSTYPE" == "msys" ]]; then
            echo "Windows"
        else
            echo "Unknown"
        fi
    fi
}

# ==============================
# 检查是否匹配目标系统
# ==============================
check_target_system() {
    local current=$(detect_system)
    [[ "$current" != "$1" ]] && error "本脚本仅支持 $1 系统，检测到当前系统为 $current"
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
    local date_str=$(date +%Y%m%d)
    local backup_base="${backup_dir}/${file_name}.bak.${date_str}"

    # 查找已存在的备份文件确定下一个序号
    local next_num=0
    while [ -f "${backup_base}.${next_num}" ]; do
        ((next_num++))
    done

    local backup_file="${backup_base}.${next_num}"

    # 执行备份
    if cp "$target_file" "$backup_file" 2>/dev/null; then
        info "备份成功: $target_file -> $backup_file"
    else
        warn "备份失败: $target_file -> $backup_file"
    fi

    return 0
}

# ==============================
# 解析 config-sync 方向参数
# 兼容 npm/pnpm/vpr：这些 runner 常关闭 stdin，但 /dev/tty 仍可用
# 用法: direction=$(prompt_sync_direction "$1" "示例: npm run mac:sync -- 2 或 vpr mac:sync 2" "1) ..." "2) ...")
# ==============================
prompt_sync_direction() {
    local arg="$1"
    local example="$2"
    local line1="$3"
    local line2="$4"

    if [ "$arg" = "1" ] || [ "$arg" = "2" ]; then
        echo "$arg"
        return 0
    fi

    local choice=""
    local tty_path=""

    tty_path=$(tty 2>/dev/null) || tty_path=""

    if [ -n "$tty_path" ]; then
        {
            echo "请选择拷贝方向:"
            echo "$line1"
            echo "$line2"
        } > "$tty_path"
        read -r choice < "$tty_path" || choice=""
    fi

    if [ -z "$choice" ] && [ -t 0 ]; then
        echo "请选择拷贝方向:"
        echo "$line1"
        echo "$line2"
        read -r choice
    fi

    if [ -z "$choice" ]; then
        safe_echo "${RED}[ERROR]${NC} 非交互环境请传入方向参数: 1=备份到仓库, 2=应用到本地
$example" >&2
        return 1
    fi

    echo "$choice"
}

# ==============================
# manifest.json 读取
# ==============================
expand_path() {
    local path="$1"
    case "$path" in
        "~/"*) echo "$HOME/${path#~/}" ;;
        "~")    echo "$HOME" ;;
        *)      echo "$path" ;;
    esac
}

init_manifest() {
    local scope="$1"
    if [[ -z "$scope" ]]; then
        error "init_manifest 需要指定 scope: mac|windows|common"
    fi
    local manifest_path="${PROJECT_ROOT}/scripts/${scope}/manifest.json"
    if [[ ! -f "$manifest_path" ]]; then
        error "找不到 manifest: $manifest_path"
    fi
    MANIFEST_SCOPE="$scope"
    MANIFEST_PATH="$manifest_path"
}

manifest_get() {
    local key="$1"
    local scope="${2:-}"
    local manifest_path="$MANIFEST_PATH"

    if [[ -n "$scope" ]]; then
        manifest_path="${PROJECT_ROOT}/scripts/${scope}/manifest.json"
        if [[ ! -f "$manifest_path" ]]; then
            error "找不到 manifest: $manifest_path"
        fi
    elif [[ -z "$manifest_path" ]]; then
        error "请先调用 init_manifest"
    fi

    node -e "
        const m = require(process.argv[1]);
        let v = m;
        for (const k of process.argv[2].split('.')) {
            v = v?.[k];
        }
        if (v === undefined || v === null) {
            process.stderr.write('manifest 缺少配置: ' + process.argv[2] + '\n');
            process.exit(1);
        }
        if (typeof v === 'object') console.log(JSON.stringify(v));
        else console.log(String(v));
    " "$manifest_path" "$key"
}

manifest_sync_pairs() {
    if [[ -z "$MANIFEST_PATH" ]]; then
        error "请先调用 init_manifest"
    fi
    node -e "
        const path = require('path');
        const os = require('os');
        const m = require(process.argv[1]);
        const projectRoot = process.argv[2];
        const expand = (p) => p.replace(/^~(?=\/|$)/, os.homedir());
        for (const item of m.sync.toRepo) {
            process.stdout.write(expand(item.local) + '\t' + path.join(projectRoot, item.repo) + '\n');
        }
    " "$MANIFEST_PATH" "$PROJECT_ROOT"
}
