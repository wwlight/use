#!/bin/bash

# 引入公共函数库
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ==============================
# 主安装函数
# ==============================
setup_directories() {
    info "步骤1/4: 正在创建目录结构..."
    mkdir -p D:/SoftwareApps || warn "部分 D: 目录已存在"
    mkdir -p ~/.zsh/{plugins,cache,functions,zfunc} || warn "部分 .zsh 目录已存在"
    mkdir -p ~/.config/starship || warn ".config/starship 目录已存在"
}

install_or_restore_scoop() {
    info "步骤2/4: 正在安装/恢复 Scoop 应用..."
    local SCOOP_BACKUP="$PROJECT_ROOT/configs/windows/scoop_backup.json"

    if ! command -v scoop &> /dev/null; then
        error "Scoop 未安装！请先安装 Scoop。"
        return 1
    fi

    if [ -f "$SCOOP_BACKUP" ]; then
        scoop import "$SCOOP_BACKUP" || {
            error "Scoop 应用恢复失败！"
            return 1
        }
    else
        error "找不到 Scoop 备份文件: $SCOOP_BACKUP"
        return 1
    fi
}

install_zsh_plugins() {
    info "步骤3/4: 正在安装 zsh 插件..."

    declare -A PLUGINS=(
        ["https://github.com/zdharma-continuum/fast-syntax-highlighting.git"]="fast-syntax-highlighting"
        ["https://github.com/zsh-users/zsh-autosuggestions.git"]="zsh-autosuggestions"
        ["https://github.com/zsh-users/zsh-completions.git"]="zsh-completions"
    )

    local ZSH_PLUGINS_DIR="$HOME/.zsh/plugins"
    for repo in "${!PLUGINS[@]}"; do
        plugin_name="${PLUGINS[$repo]}"
        target_path="$ZSH_PLUGINS_DIR/$plugin_name"

        if [ ! -d "$target_path" ]; then
            info "正在下载插件: $plugin_name..."
            git clone "$repo" "$target_path" || {
                warn "$plugin_name 下载失败，跳过此插件"
                continue
            }
            info "$plugin_name 下载完成"
        else
            info "插件 $plugin_name 已存在，跳过下载"
        fi
    done
}

sync_configurations() {
    info "步骤4/4: 正在同步配置..."
    local CONFIG_SCRIPT="$SCRIPT_DIR/windows/config-sync.sh"
    local COMMON_SCRIPT="$SCRIPT_DIR/common/config-sync.sh"
    local BASE_SCRIPT="$SCRIPT_DIR/common/git-setup.sh"

    # 同步 zsh 配置
    if [ -f "$CONFIG_SCRIPT" ]; then
        bash "$CONFIG_SCRIPT" 2 || error "同步配置失败！"
    else
        error "找不到配置同步脚本: $CONFIG_SCRIPT"
    fi

    # 同步公共配置
    if [ -f "$COMMON_SCRIPT" ]; then
        bash "$COMMON_SCRIPT" 2 || error "同步公共配置失败！"
    else
        warn "找不到公共同步脚本: $COMMON_SCRIPT"
    fi

    # 基础配置初始化
    if [ -f "$BASE_SCRIPT" ]; then
        bash "$BASE_SCRIPT" || error "基础配置初始化失败！"
    else
        warn "找不到基础配置初始化脚本: $BASE_SCRIPT"
    fi
}

# ==============================
# 主执行流程
# ==============================
main() {
    info "===== Windows 系统配置脚本 ====="
    check_target_system "Windows"

    setup_directories              # 步骤1: 创建目录结构
    install_or_restore_scoop       # 步骤2: 安装/恢复 Scoop 应用
    install_zsh_plugins            # 步骤3: 安装 zsh 插件
    sync_configurations            # 步骤4: 同步配置

    info "🎉 所有操作完成！系统已准备就绪。"
}

# 执行主函数
main
