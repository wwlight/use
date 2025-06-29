#!/bin/bash

# 引入公共函数库
SCRIPT_DIR="./bash"
source "$SCRIPT_DIR/utils.sh"

# ==============================
# 主安装函数
# ==============================
setup_directories() {
    info "步骤1/4: 正在创建目录结构..."
    mkdir -p D:/{DevelopApplication,SystemApplication} || warn "部分 D: 目录已存在"
    mkdir -p ~/.zsh/{plugins,cache,functions,zfunc} || warn "部分 .zsh 目录已存在"
    mkdir -p ~/.config/starship || warn ".config/starship 目录已存在"
    mkdir -p ~/.npm_global || warn ".npm_global 目录已存在"
}

install_zsh_plugins() {
    info "步骤2/4: 正在安装 zsh 插件..."

    # 保持原始顺序：key=仓库URL，value=插件目录名
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

restore_scoop_apps() {
    info "步骤3/4: 正在恢复 Scoop 应用..."
    local SCOOP_BACKUP="./windows/scoop_backup.json"

    if ! command -v scoop &> /dev/null; then
        error "Scoop 未安装！请先安装 Scoop。"
    fi

    if [ -f "$SCOOP_BACKUP" ]; then
        scoop import "$SCOOP_BACKUP" || {
            error "Scoop 应用恢复失败！"
        }
    else
        error "找不到 Scoop 备份文件: $SCOOP_BACKUP"
    fi
}

sync_configurations() {
    info "步骤4/4: 正在同步配置..."
    local ZSH_SCRIPT="$SCRIPT_DIR/win-zsh-sync.sh"
    local OTHER_SCRIPT="$SCRIPT_DIR/other-sync.sh"

    # 同步 zsh 配置
    if [ -f "$ZSH_SCRIPT" ]; then
        sh "$ZSH_SCRIPT" 2 || error "同步 zsh 配置失败！"
    else
        error "找不到 zsh 同步脚本: $ZSH_SCRIPT"
    fi

    # 同步其他配置
    if [ -f "$OTHER_SCRIPT" ]; then
        sh "$OTHER_SCRIPT" 2 || error "同步其他配置失败！"
    else
        warn "找不到其他同步脚本: $OTHER_SCRIPT"
    fi
}

# ==============================
# 主执行流程
# ==============================
main() {
    info "===== Windows 系统配置脚本 ====="
    check_target_system "Windows"

    setup_directories       # 步骤1: 创建目录结构
    install_zsh_plugins     # 步骤2: 安装 zsh 插件
    restore_scoop_apps      # 步骤3: 恢复 Scoop 应用
    sync_configurations     # 步骤4: 同步配置

    info "🎉 所有操作完成！系统已准备就绪。"
}

# 执行主函数
main
