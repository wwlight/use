#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

init_manifest macos

MANIFEST_CONFIG="$SCRIPT_DIR/lib/manifest-config.mjs"

usage() {
    node "$MANIFEST_CONFIG" usage-init
}

# 解析安装配置档（stdout 输出档位）
resolve_brew_profile() {
    local arg="${1:-}"
    local profile=""

    case "$arg" in
        "" ) ;;
        --*) profile="${arg#--}" ;;
        *) profile="$arg" ;;
    esac

    if [[ -n "$profile" ]]; then
        node "$MANIFEST_CONFIG" has-profile "$profile" || {
            usage >&2
            error "未知参数: $arg"
        }
        echo "$profile"
        return 0
    fi

    if ! has_tty; then
        error "非交互环境请传入参数（示例: vpr init -- lite）"
    fi

    local menu_args=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        menu_args+=("$line")
    done < <(node "$MANIFEST_CONFIG" menu-profiles)

    local choice=""
    choice=$(node "$SCRIPT_DIR/lib/menu-select.mjs" \
        "请选择 Homebrew 安装范围" \
        "${menu_args[@]}") || choice=""
    choice=${choice//$'\r'/}
    choice=${choice//$'\n'/}

    if [[ -z "$choice" ]]; then
        error "非交互环境请传入参数（示例: vpr init -- lite）"
    fi

    node "$MANIFEST_CONFIG" has-profile "$choice" || {
        error "无效选择: ${choice}"
    }
    echo "$choice"
}

setup_directories() {
    next_step "正在创建目录结构..."
    local dir path
    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        path=$(expand_path "$dir")
        mkdir -p "$path" || warn "目录创建失败或已存在: $path"
    done < <(manifest_directories)
}

install_or_restore_brew() {
    local profile="$1"
    local label brewfile
    label=$(node "$MANIFEST_CONFIG" profile-label "$profile")
    next_step "正在恢复 Homebrew 依赖（${label}）..."

    brewfile=$(node "$MANIFEST_CONFIG" profile-artifact macos "$profile")
    local BREWFILE="$PROJECT_ROOT/$brewfile"

    if ! command -v brew &> /dev/null; then
        error "Homebrew 未安装！请先运行: vpr pm"
    fi

    if [ -f "$BREWFILE" ]; then
        info "正在从 $(basename "$BREWFILE") 安装依赖..."
        brew bundle install --file="$BREWFILE" || {
            error "Brewfile 依赖安装失败！"
        }
        info "Brewfile 依赖安装完成"
    else
        error "找不到 Brewfile: $BREWFILE"
    fi
}

install_zsh_plugins() {
    next_step "正在安装 zsh 插件..."
    bash "$SCRIPT_DIR/common/zsh-plugins-install.sh" || error "zsh 插件安装失败！"
}

sync_configurations() {
    local profile="$1"
    next_step "正在同步配置..."
    local CONFIG_SCRIPT="$SCRIPT_DIR/macos/config-sync.sh"
    local BASE_SCRIPT="$SCRIPT_DIR/common/git-setup.sh"

    if [ -f "$CONFIG_SCRIPT" ]; then
        SYNC_PROFILE="$profile" SYNC_SELECT_ALL=1 bash "$CONFIG_SCRIPT" 2 || error "同步配置失败！"
    else
        error "找不到配置同步脚本: $CONFIG_SCRIPT"
    fi

    if [ -f "$BASE_SCRIPT" ]; then
        bash "$BASE_SCRIPT" || error "基础配置初始化失败！"
    else
        warn "找不到基础配置初始化脚本: $BASE_SCRIPT"
    fi
}

main() {
    check_target_os "macos"

    while [[ "${1:-}" == "--" ]]; do shift; done

    case "${1:-}" in
        -h|--help|help) usage; exit 0 ;;
    esac

    local profile
    profile=$(resolve_brew_profile "${1:-}") || exit $?

    local INIT_STEP_COUNT=4
    init_step_progress "$INIT_STEP_COUNT"

    setup_directories
    install_or_restore_brew "$profile"
    install_zsh_plugins
    sync_configurations "$profile"

    info "所有操作完成！系统已准备就绪。"
}

main "$@"
