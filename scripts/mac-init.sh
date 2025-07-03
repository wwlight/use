#!/bin/bash

# 引入公共函数库
SCRIPT_DIR="./scripts"
source "$SCRIPT_DIR/utils.sh"

# ==============================
# 主安装函数
# ==============================
setup_directories() {
    info "步骤1/4: 正在创建目录结构..."
    local directories=(
        "$HOME/.zsh/plugins"
        "$HOME/.zsh/cache"
        "$HOME/.zsh/functions"
        "$HOME/.zsh/zfunc"
        "$HOME/.config/starship"
        "$HOME/.npm_global"
    )

    for dir in "${directories[@]}"; do
        mkdir -p "$dir" || warn "目录创建失败或已存在: $dir"
    done
}

install_or_restore_brew() {
    info "步骤2/4: 正在安装/恢复 Homebrew 及依赖..."
    local BREWFILE="./mac/Brewfile"

    # 检查并安装 Homebrew
    if ! command -v brew &> /dev/null; then
        info "Homebrew 未安装，正在自动安装..."

        # 从镜像下载安装脚本并安装 Homebrew
        # git clone --depth=1 https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/install.git brew-install
        # /bin/bash brew-install/install.sh
        # rm -rf brew-install

        # 使用官方安装脚本
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
            error "Homebrew 安装失败！"
            return 1
        }

        info "同步 Homebrew 配置文件..."
        cp -v ./mac/.zprofile ~/.zprofile
        source ~/.zprofile
        brew update || {
            error "Homebrew 更新失败！"
            return 1
        }
        info "Homebrew 安装成功"
    fi

    # 安装 Brewfile 依赖
    if [ -f "$BREWFILE" ]; then
        info "正在从 Brewfile 安装依赖..."
        brew bundle install --file="$BREWFILE" || {
            error "Brewfile 依赖安装失败！"
            return 1
        }
        info "Brewfile 依赖安装完成"
    else
        error "找不到 Brewfile: $BREWFILE"
        return 1
    fi
}

install_zsh_plugins() {
    info "步骤3/4: 正在安装 zsh 插件..."

    # 使用兼容旧版 Bash 的数组代替关联数组
    local PLUGINS_REPOS=(
        "https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
        "https://github.com/zsh-users/zsh-autosuggestions.git"
        "https://github.com/zsh-users/zsh-completions.git"
    )

    local PLUGINS_NAMES=(
        "fast-syntax-highlighting"
        "zsh-autosuggestions"
        "zsh-completions"
    )

    local ZSH_PLUGINS_DIR="$HOME/.zsh/plugins"

    for i in "${!PLUGINS_REPOS[@]}"; do
        local repo="${PLUGINS_REPOS[$i]}"
        local plugin_name="${PLUGINS_NAMES[$i]}"
        local target_dir="$ZSH_PLUGINS_DIR/$plugin_name"

        if [ ! -d "$target_dir" ]; then
            info "正在下载插件: $plugin_name..."
            git clone "$repo" "$target_dir" || {
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
    local CONFIG_SCRIPT="$SCRIPT_DIR/mac-config-sync.sh"
    local OTHER_SCRIPT="$SCRIPT_DIR/other-sync.sh"

    # 同步 zsh 配置
    if [ -f "$CONFIG_SCRIPT" ]; then
        sh "$CONFIG_SCRIPT" 2 || error "同步配置失败！"
    else
        error "找不到配置同步脚本: $CONFIG_SCRIPT"
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
    info "===== macOS 系统配置脚本 ====="
    check_target_system "macOS"

    setup_directories            # 步骤1: 创建目录结构
    install_or_restore_brew      # 步骤2: 安装/恢复 Homebrew 及依赖
    install_zsh_plugins          # 步骤3: 安装 zsh 插件
    sync_configurations          # 步骤4: 同步配置

    info "🎉 所有操作完成！系统已准备就绪。"
}

# 执行主函数
main
