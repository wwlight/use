#!/bin/bash

# 引入公共函数库（基于脚本绝对路径，支持在任意目录执行）
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

init_manifest mac

usage() {
    cat <<EOF
用法: $(basename "$0") [lite|full]

  lite  尝鲜版
  full  完整版

示例:
  bash $(basename "$0")
  bash $(basename "$0") lite
  vpr init -- lite
  vpr init -- full
EOF
}

# 解析安装配置档：lite | full → BREW_INSTALL_PROFILE
resolve_brew_profile() {
    local arg="${1:-}"
    BREW_INSTALL_PROFILE=""

    case "$arg" in
        "" )
            ;;
        full|--full)
            BREW_INSTALL_PROFILE="full"
            return 0
            ;;
        lite|--lite)
            BREW_INSTALL_PROFILE="lite"
            return 0
            ;;
        -h|--help|help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            error "未知参数: $arg"
            ;;
    esac

    local choice=""

    {
        echo "请选择 Homebrew 安装范围:"
        echo "1) 尝鲜版"
        echo "2) 完整版"
    } >&2

    if [ -r /dev/tty ]; then
        read -r choice < /dev/tty || choice=""
    elif [ -t 0 ]; then
        read -r choice || choice=""
    fi

    case "$choice" in
        1|lite) BREW_INSTALL_PROFILE="lite" ;;
        2|full) BREW_INSTALL_PROFILE="full" ;;
        "")
            error "非交互环境请传入参数: lite 或 full（示例: vpr init -- lite）"
            ;;
        *)
            error "无效选择: ${choice}（请使用 1/lite 或 2/full）"
            ;;
    esac
}

setup_directories() {
    step "步骤1/4: 正在创建目录结构..."
    local directories_json
    directories_json=$(manifest_directories)

    node -e "
        const dirs = JSON.parse(process.argv[1]);
        for (const dir of dirs) {
            console.log(dir);
        }
    " "$directories_json" | while IFS= read -r dir; do
        local path
        path=$(expand_path "$dir")
        mkdir -p "$path" || warn "目录创建失败或已存在: $path"
    done
}

install_or_restore_brew() {
    local profile="$1"
    local label="完整版"
    [ "$profile" = "lite" ] && label="尝鲜版"
    step "步骤2/4: 正在恢复 Homebrew 依赖（${label}）..."

    local brewfile_key="brewfile"
    if [ "$profile" = "lite" ]; then
        brewfile_key="brewfileLite"
    fi

    local brewfile
    brewfile=$(manifest_get "$brewfile_key")
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
    step "步骤3/4: 正在安装 zsh 插件..."
    bash "$SCRIPT_DIR/common/zsh-plugins-install.sh" || error "zsh 插件安装失败！"
}

sync_configurations() {
    local profile="$1"
    step "步骤4/4: 正在同步配置..."
    local CONFIG_SCRIPT="$SCRIPT_DIR/mac/config-sync.sh"
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
    info "===== macOS 系统配置脚本 ====="
    check_target_system "macOS"

    while [[ "${1:-}" == "--" ]]; do shift; done

    resolve_brew_profile "${1:-}"
    local profile="$BREW_INSTALL_PROFILE"

    setup_directories
    install_or_restore_brew "$profile"
    install_zsh_plugins
    sync_configurations "$profile"

    info "🎉 所有操作完成！系统已准备就绪。"
}

main "$@"
