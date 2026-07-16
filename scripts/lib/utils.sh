#!/bin/bash

# --- 颜色定义和打印方法 ---
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
NC=$'\033[0m'

safe_echo() {
    printf '%s\n' "$1"
}

info() { safe_echo "${GREEN}[INFO] $1${NC}"; }
step() { safe_echo "${MAGENTA}[INFO] $1${NC}"; }
backup_info() { safe_echo "${CYAN}[INFO] $1${NC}"; }
warn() { safe_echo "${YELLOW}[WARN] $1${NC}"; }
error() { safe_echo "${RED}[ERROR] $1${NC}"; exit 1; }

# --- 系统环境检测 ---
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

# --- 检查是否匹配目标系统 ---
check_target_system() {
    local current=$(detect_system)
    [[ "$current" != "$1" ]] && error "本脚本仅支持 $1 系统，检测到当前系统为 $current"
}

# --- 备份（支持自定义路径+日期序号+错误不中断） ---
# 使用方法: backup_file <目标文件> [备份目录]
backup_file() {
    # 输出备份文件名（相对于 backup_dir），失败时返回空
    local target_file="$1"
    local backup_dir="${2:-$(dirname "$target_file")}"

    if [ ! -f "$target_file" ]; then
        return 0
    fi

    if ! mkdir -p "$backup_dir"; then
        warn "无法创建备份目录: $backup_dir"
        return 0
    fi

    local file_name=$(basename "$target_file")
    local date_str=$(date +%Y%m%d)
    local backup_base="${backup_dir}/${file_name}.bak.${date_str}"

    local next_num=0
    while [ -f "${backup_base}.${next_num}" ]; do
        ((next_num++))
    done

    local backup_file="${backup_base}.${next_num}"

    if cp "$target_file" "$backup_file" 2>/dev/null; then
        echo "${file_name}.bak.${date_str}.${next_num}"
    else
        warn "备份失败: $file_name"
    fi
}

# --- 解析 config-sync 方向参数 ---
# 用法: direction=$(prompt_sync_direction "$1" "示例: vpr sync 2" "1) ..." "2) ...")
prompt_sync_direction() {
    local arg="$1"
    local example="$2"
    local line1="$3"
    local line2="$4"

    if [ "$arg" = "1" ] || [ "$arg" = "2" ]; then
        echo "$arg"
        return 0
    fi

    if [ -n "$arg" ]; then
        safe_echo "${RED}[ERROR] 无效的同步方向: 请使用 1 或 2
$example${NC}" >&2
        return 1
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
        safe_echo "${RED}[ERROR] 非交互环境请传入方向参数: 1=备份到仓库, 2=应用到本地
$example${NC}" >&2
        return 1
    fi

    echo "$choice"
}

# --- manifest.json 读取 ---
expand_path() {
    local path="$1"
    case "$path" in
        "~/"*) echo "$HOME/${path#\~/}" ;;
        "~")    echo "$HOME" ;;
        *)      echo "$path" ;;
    esac
}

format_repo_display() {
    local path="$1"
    case "$path" in
        ./*) echo "$path" ;;
        *)   echo "./$path" ;;
    esac
}

format_local_display() {
    local path="${1//\\//}"
    case "$path" in
        ~) echo "~"; return ;;
        ~/*) echo "$path"; return ;;
    esac
    local home="${HOME%/}"
    if [ "$path" = "$home" ]; then
        echo "~"
    elif [[ "$path" == "$home/"* ]]; then
        echo "~/${path#$home/}"
    else
        echo "$path"
    fi
}

sync_select_run() {
    local direction="$1"
    local pairs_file="$2"
    local filtered_file="$3"
    local node_script="${SCRIPT_DIR}/lib/sync-select.mjs"
    local rc=0

    if [ -t 0 ] || [ -n "$(tty 2>/dev/null)" ]; then
        SYNC_INTERACTIVE=1 node "$node_script" "$direction" "$pairs_file" "$filtered_file" || rc=$?
    else
        node "$node_script" "$direction" "$pairs_file" "$filtered_file" || rc=$?
    fi

    if [ "$rc" -ne 0 ]; then
        rm -f "$pairs_file" "$filtered_file"
        if [ "$rc" -eq 130 ]; then
            error "文件选择已取消"
        fi
        error "文件选择失败，请重试或通过 vpr sync 运行"
    fi
}

init_manifest() {
    local scope="$1"
    if [[ -z "$scope" ]]; then
        error "init_manifest 需要指定 scope: mac|windows|common"
    fi
    local manifest_path="${PROJECT_ROOT}/scripts/${scope}/_manifest.json"
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
        manifest_path="${PROJECT_ROOT}/scripts/${scope}/_manifest.json"
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

manifest_directories() {
    local scopes=("$@")
    if [[ ${#scopes[@]} -eq 0 ]]; then
        if [[ -z "$MANIFEST_SCOPE" ]]; then
            error "请先调用 init_manifest"
        fi
        scopes=("$MANIFEST_SCOPE")
        if [[ "$MANIFEST_SCOPE" == mac || "$MANIFEST_SCOPE" == windows ]]; then
            scopes=("common" "$MANIFEST_SCOPE")
        fi
    fi

    node -e "
        const path = require('path');
        const projectRoot = process.argv[1];
        const scopes = process.argv.slice(2);
        const seen = new Set();
        const dirs = [];
        for (const scope of scopes) {
            const m = require(path.join(projectRoot, 'scripts', scope, '_manifest.json'));
            for (const d of m.directories ?? []) {
                if (!seen.has(d)) {
                    seen.add(d);
                    dirs.push(d);
                }
            }
        }
        console.log(JSON.stringify(dirs));
    " "$PROJECT_ROOT" "${scopes[@]}"
}

manifest_sync_pairs() {
    local scopes=("$@")
    if [[ ${#scopes[@]} -eq 0 ]]; then
        if [[ -z "$MANIFEST_SCOPE" ]]; then
            error "请先调用 init_manifest"
        fi
        scopes=("$MANIFEST_SCOPE")
    fi

    node -e "
        const fs = require('fs');
        const path = require('path');
        const projectRoot = process.argv[1];
        const scopes = process.argv.slice(2);
        for (const scope of scopes) {
            const manifestPath = path.join(projectRoot, 'scripts', scope, '_manifest.json');
            if (!fs.existsSync(manifestPath)) {
                process.stderr.write('找不到 manifest: ' + manifestPath + '\n');
                process.exit(1);
            }
            const m = require(manifestPath);
            const liteOnly = process.env.SYNC_PROFILE === 'lite';
            for (const item of m.sync.toRepo) {
                if (liteOnly && item.lite === false) continue;
                process.stdout.write(item.local + '\t' + item.repo + '\t' + (item.backup ? '1' : '0') + '\n');
            }
        }
    " "$PROJECT_ROOT" "${scopes[@]}"
}

should_skip_sync_select() {
    [ "$SYNC_SELECT_ALL" = "1" ] && return 0
    local tty_path
    tty_path=$(tty 2>/dev/null) || tty_path=""
    if [ -n "$tty_path" ] || [ -t 0 ]; then
        return 1
    fi
    return 0
}

is_sync_dispatch_mode() {
    [ "$SYNC_FROM_DISPATCH" = "1" ]
}

sync_progress_hint() {
    local direction="$1"
    local total="$2"

    [ "$total" -gt 0 ] || return 0
    is_sync_dispatch_mode && return 0

    if [ "$direction" = "1" ]; then
        info "正在备份 $total 个文件到仓库..."
    else
        info "正在恢复 $total 个文件到本地..."
    fi
}

manifest_sync_pairs_filtered() {
    local direction="$1"
    shift
    local scopes=("$@")
    local pairs_file filtered_file

    if [ -n "$SYNC_FILTERED_PAIRS" ] && [ -f "$SYNC_FILTERED_PAIRS" ]; then
        cat "$SYNC_FILTERED_PAIRS"
        rm -f "$SYNC_FILTERED_PAIRS"
        unset SYNC_FILTERED_PAIRS
        return
    fi

    if is_sync_dispatch_mode; then
        if should_skip_sync_select; then
            manifest_sync_pairs "${scopes[@]}"
            return
        fi
        error "缺少已选文件列表，请通过 vpr sync 运行"
    fi

    pairs_file=$(mktemp) || error "无法创建临时文件"
    manifest_sync_pairs "${scopes[@]}" > "$pairs_file"

    if should_skip_sync_select; then
        cat "$pairs_file"
        rm -f "$pairs_file"
        return
    fi

    filtered_file=$(mktemp) || { rm -f "$pairs_file"; error "无法创建临时文件"; }
    sync_select_run "$direction" "$pairs_file" "$filtered_file"
    cat "$filtered_file"
    rm -f "$pairs_file" "$filtered_file"
}

run_config_sync() {
    local scope="$1"
    shift
    local direction_arg=""
    local invalid_direction_arg=""
    local sync_scopes=("$scope")

    if [[ "$scope" == "mac" || "$scope" == "windows" ]]; then
        sync_scopes+=("common")
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            1|2) direction_arg="$1" ;;
            --) ;;
            *)
                [ -n "$1" ] && invalid_direction_arg="$1"
                ;;
        esac
        shift
    done

    local direction_input="$direction_arg"
    [ -z "$direction_input" ] && direction_input="$invalid_direction_arg"

    local example="示例: vpr sync 2"
    if is_sync_dispatch_mode && [ "$direction_input" != "1" ] && [ "$direction_input" != "2" ]; then
        error "缺少同步方向参数: $example"
    fi

    local line1 line2
    if [[ ${#sync_scopes[@]} -gt 1 ]]; then
        line1="1) 备份本地配置 -> 仓库"
        line2="2) 从仓库恢复配置 -> 本地"
    else
        line1="1) 备份本地配置 -> 仓库 configs/$scope/"
        line2="2) 从仓库恢复配置 -> 本地"
    fi

    direction=$(prompt_sync_direction "$direction_input" \
        "$example" \
        "$line1" \
        "$line2") || exit 1

    sync_pairs=()
    while IFS= read -r line; do
        [ -n "$line" ] && sync_pairs+=("$line")
    done < <(manifest_sync_pairs_filtered "$direction" "${sync_scopes[@]}")
    total=${#sync_pairs[@]}
    [ "$total" -gt 0 ] || error "没有可同步的配置项"
    sync_progress_hint "$direction" "$total"
    i=0

    case $direction in
        1)
            for pair in "${sync_pairs[@]}"; do
                IFS=$'\t' read -r local_path repo_path _backup_flag <<< "$pair"
                local_abs=$(expand_path "$local_path")
                repo_abs="${PROJECT_ROOT}/${repo_path}"
                repo_display=$(format_repo_display "$repo_path")
                mkdir -p "$(dirname "$repo_abs")" || error "无法创建目录: $(format_repo_display "$(dirname "$repo_path")")"
                cp "$local_abs" "$repo_abs" || error "备份失败: $local_path -> $repo_display"
                i=$((i + 1))
                info "[$i/$total] 已备份 $repo_display"
            done

            info "配置已备份到仓库"
            ;;
        2)
            for pair in "${sync_pairs[@]}"; do
                IFS=$'\t' read -r local_path repo_path backup_flag <<< "$pair"
                local_abs=$(expand_path "$local_path")
                repo_abs="${PROJECT_ROOT}/${repo_path}"
                repo_display=$(format_repo_display "$repo_path")
                i=$((i + 1))
                if [ "$backup_flag" = "1" ]; then
                    bak_name=$(backup_file "$local_abs" ~/.backup)
                    if [ -n "$bak_name" ]; then
                        backup_info "[$i/$total] 已备份 $(format_local_display "$local_path") -> ~/.backup/$bak_name"
                    fi
                fi
                mkdir -p "$(dirname "$local_abs")" || error "无法创建目录: $(dirname "$local_path")"
                cp "$repo_abs" "$local_abs" || error "恢复失败: $repo_display -> $local_path"
                info "[$i/$total] 已恢复 $(format_local_display "$local_path")"
            done

            info "配置已恢复到本地"
            ;;
        *)
            error "无效选择"
            ;;
    esac

    if [ -z "$direction_arg" ] && ! is_sync_dispatch_mode; then
        info "下次可直接运行：vpr sync $direction 跳过交互选择"
    fi
}
