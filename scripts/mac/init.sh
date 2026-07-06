#!/bin/bash

# 引入公共函数库（基于脚本绝对路径，支持在任意目录执行）
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

init_manifest mac

setup_directories() {
    info "步骤1/5: 正在创建目录结构..."
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
    info "步骤2/5: 正在恢复 Homebrew 依赖..."
    local brewfile
    brewfile=$(manifest_get "brewfile")
    local BREWFILE="$PROJECT_ROOT/$brewfile"

    if ! command -v brew &> /dev/null; then
        error "Homebrew 未安装！请先运行: vpr pm"
    fi

    if [ -f "$BREWFILE" ]; then
        info "正在从 Brewfile 安装依赖..."
        brew bundle install --file="$BREWFILE" || {
            error "Brewfile 依赖安装失败！"
        }
        info "Brewfile 依赖安装完成"
    else
        error "找不到 Brewfile: $BREWFILE"
    fi
}

install_zsh_plugins() {
    info "步骤3/5: 正在安装 zsh 插件..."
    bash "$SCRIPT_DIR/common/zsh-plugins-install.sh" || error "zsh 插件安装失败！"
}

install_vite_plus() {
    info "步骤4/5: 正在安装 vite.plus..."
    bash "$SCRIPT_DIR/common/vite-plus-install.sh" || error "vite.plus 安装失败！"
}

sync_configurations() {
    info "步骤5/5: 正在同步配置..."
    local CONFIG_SCRIPT="$SCRIPT_DIR/mac/config-sync.sh"
    local BASE_SCRIPT="$SCRIPT_DIR/common/git-setup.sh"

    if [ -f "$CONFIG_SCRIPT" ]; then
        SYNC_SELECT_ALL=1 bash "$CONFIG_SCRIPT" 2 || error "同步配置失败！"
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

    setup_directories
    install_or_restore_brew
    install_zsh_plugins
    install_vite_plus
    sync_configurations

    info "🎉 所有操作完成！系统已准备就绪。"
}

main
