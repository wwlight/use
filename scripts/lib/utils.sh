#!/bin/bash

# --- 颜色定义和打印方法 ---
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

safe_echo() {
    printf '%s\n' "$1"
}

# 日志走 stderr，避免在 $(...) 中被吞掉；数据结果仍用 stdout
info() { safe_echo "${GREEN}[INFO] $1${NC}" >&2; }
step() { safe_echo "${BLUE}[INFO] $1${NC}" >&2; }
backup_info() { safe_echo "${CYAN}[INFO] $1${NC}" >&2; }
warn() { safe_echo "${YELLOW}[WARN] $1${NC}" >&2; }
error() { safe_echo "${RED}[ERROR] $1${NC}" >&2; exit 1; }

# 全局步骤计数（跨子进程，专用前缀避免脏环境干扰）
#   USE_STEP_CHAIN=1  由 install 入口设置，表示续接父进度
#   USE_STEP_TOTAL    总步数
#   USE_STEP_CURRENT  当前已完成步数
_use_step_is_uint() {
    case "${1:-}" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# 用法: next_step "正在创建目录结构..."
next_step() {
    local current=0
    if _use_step_is_uint "${USE_STEP_CURRENT:-}"; then
        current=$USE_STEP_CURRENT
    fi
    current=$((current + 1))
    export USE_STEP_CURRENT=$current

    if _use_step_is_uint "${USE_STEP_TOTAL:-}" && [ "$USE_STEP_TOTAL" -gt 0 ]; then
        step "步骤 ${current}/${USE_STEP_TOTAL}: $1"
    else
        step "$1"
    fi
}

# 用法: init_step_progress 4
# - 无 USE_STEP_CHAIN=1：始终按本脚本步数重置（忽略残留环境变量）
# - 有链式标记：总数 = 已完成 + 本脚本步数（以本脚本为准，防止与入口漂移）
init_step_progress() {
    local local_steps="${1:?}"
    if [ "${USE_STEP_CHAIN:-}" = "1" ]; then
        local current=0
        if _use_step_is_uint "${USE_STEP_CURRENT:-}"; then
            current=$USE_STEP_CURRENT
        fi
        export USE_STEP_CURRENT=$current
        export USE_STEP_TOTAL=$((current + local_steps))
        return
    fi
    export USE_STEP_TOTAL=$local_steps
    export USE_STEP_CURRENT=0
}

# 是否存在可用的控制终端（curl|bash 时 stdin 非 tty，但 /dev/tty 仍可能可用）
has_tty() {
    [ -t 0 ] && return 0
    { true </dev/tty; } 2>/dev/null
}

# 规范化 git remote，便于比较是否同一仓库
normalize_repo_url() {
    local u="$1"
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

# 用法: is_same_remote_repo <dir> <expected-url>
is_same_remote_repo() {
    local dir="$1"
    local expected="$2"
    [ -d "$dir/.git" ] || return 1
    local remote
    remote=$(git -C "$dir" remote get-url origin 2>/dev/null) || return 1
    [ "$(normalize_repo_url "$remote")" = "$(normalize_repo_url "$expected")" ]
}

# 安装或更新 git 仓库型插件
# 用法: sync_git_repo_plugin <repo> <target_dir> <name> [1]
# 第 4 参为 1：已存在则更新；否则跳过
update_git_repo_to_latest() {
    local dir="$1"
    git -C "$dir" fetch --prune origin || return 1

    local branch
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
    if [ "$branch" = "HEAD" ]; then
        branch=$(git -C "$dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
        branch="${branch#origin/}"
        [ -n "$branch" ] || return 1
    fi

    git -C "$dir" reset --hard "origin/$branch"
}

install_git_repo_clone() {
    local repo="$1"
    local target_dir="$2"
    local plugin_name="$3"

    info "正在下载插件: $plugin_name..."
    git clone "$repo" "$target_dir" || {
        warn "$plugin_name 下载失败，跳过此插件"
        return 1
    }
    info "$plugin_name 下载完成"
}

sync_git_repo_plugin() {
    local repo="$1"
    local target_dir="$2"
    local plugin_name="$3"
    local update="${4:-0}"

    if [ ! -d "$target_dir" ]; then
        install_git_repo_clone "$repo" "$target_dir" "$plugin_name"
        return
    fi

    if [ "$update" != "1" ]; then
        info "插件 $plugin_name 已存在，跳过"
        return
    fi

    if is_same_remote_repo "$target_dir" "$repo"; then
        info "插件 $plugin_name 已是线上仓库，正在拉取最新..."
        if update_git_repo_to_latest "$target_dir"; then
            info "$plugin_name 已更新到最新"
        else
            warn "$plugin_name 拉取最新失败，跳过此插件"
        fi
        return
    fi

    info "插件 $plugin_name 同名但非目标仓库，正在删除并重新克隆..."
    rm -rf "$target_dir"
    install_git_repo_clone "$repo" "$target_dir" "$plugin_name"
}

# 从控制终端读一行（curl|bash 时 stdin 是管道，必须用 /dev/tty）
# 用法: answer=$(read_tty "提示: ") || error "非交互环境"
read_tty() {
    local prompt="${1:-}"
    local line=""

    if [ -n "$prompt" ]; then
        printf '%s' "$prompt" >&2
    fi

    if { read -r line < /dev/tty; } 2>/dev/null; then
        printf '%s\n' "$line"
        return 0
    fi

    if [ -t 0 ] && read -r line; then
        printf '%s\n' "$line"
        return 0
    fi

    return 1
}

# --- 系统环境检测 ---
detect_os() {
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

# 期望值: macos / windows / linux
check_target_os() {
    local current
    current=$(detect_os)
    [[ "$current" != "$1" ]] && error "本脚本仅支持 $1，检测到当前系统为 $current"
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
# 用法: direction=$(prompt_sync_direction "$1" "示例: vpr sync 2")
prompt_sync_direction() {
    local arg="$1"
    local example="${2:-示例: vpr sync 2}"
    local hint

    if [ "$arg" = "1" ] || [ "$arg" = "2" ]; then
        echo "$arg"
        return 0
    fi

    if [ -n "$arg" ]; then
        # 不可用 error()：本函数经 $(...) 调用，exit 只会结束子 shell
        safe_echo "${RED}[ERROR] 无效的同步方向: 请使用 1 或 2
$example${NC}" >&2
        return 1
    fi

    local choice=""
    choice=$(node "${SCRIPT_DIR}/lib/sync-direction.mjs") || choice=""
    choice=${choice//$'\r'/}
    choice=${choice//$'\n'/}

    if [ "$choice" != "1" ] && [ "$choice" != "2" ]; then
        hint=$(node "${SCRIPT_DIR}/lib/sync-direction.mjs" --hint 2>/dev/null) || hint="1=备份配置→仓库, 2=恢复配置→本地"
        safe_echo "${RED}[ERROR] 非交互环境请传入方向参数: ${hint}
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

    if has_tty; then
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
        error "init_manifest 需要指定 scope: macos|windows|common"
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
        if [[ "$MANIFEST_SCOPE" == macos || "$MANIFEST_SCOPE" == windows ]]; then
            scopes=("common" "$MANIFEST_SCOPE")
        fi
    fi

    node -e "
        const path = require('path');
        const projectRoot = process.argv[1];
        const scopes = process.argv.slice(2);
        const seen = new Set();
        for (const scope of scopes) {
            const m = require(path.join(projectRoot, 'scripts', scope, '_manifest.json'));
            for (const d of m.directories ?? []) {
                if (!seen.has(d)) {
                    seen.add(d);
                    console.log(d);
                }
            }
        }
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
    has_tty && return 1
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
        step "正在备份 $total 个文件到仓库..."
    else
        step "正在恢复 $total 个文件到本地..."
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

    if [[ "$scope" == "macos" || "$scope" == "windows" ]]; then
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

    direction=$(prompt_sync_direction "$direction_input" "$example") || exit 1

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
                backup_info "[$i/$total] 已备份 $repo_display"
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
                backup_info "[$i/$total] 已恢复 $(format_local_display "$local_path")"
            done

            info "配置已恢复到本地"
            ;;
        *)
            error "无效选择"
            ;;
    esac
}
