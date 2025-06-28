#!/bin/bash

# 引入公共函数库
SCRIPT_DIR="./bash"
source "$SCRIPT_DIR/utils.sh"

# 检查是否在 macOS 环境运行
check_target_system "macOS"

# =========================
# 主脚本开始
# =========================

# 定义路径
BREWFILE="./mac/Brewfile"
ZSH_SCRIPT="$SCRIPT_DIR/sync_zsh_mac.sh"
OTHER_SCRIPT="$SCRIPT_DIR/sync_other.sh"

# 1. 创建目录结构
info "正在创建目录结构..."
mkdir -p ~/.zsh/{plugins,cache,functions,zfunc} || warn "部分 .zsh 目录已存在"
mkdir -p ~/.config/starship || warn ".config/starship 目录已存在"
mkdir -p ~/.npm_global || warn ".npm_global 目录已存在"

# 2. 安装 zsh 插件
info "正在安装 zsh 插件..."

install_plugin() {
    local repo=$1
    local dest=$2
    if [ ! -d "$dest" ]; then
        git clone "$repo" "$dest" && info "成功安装插件: $(basename $dest)"
    else
        warn "插件已存在，跳过安装: $(basename $dest)"
    fi
}

install_plugin "https://github.com/zdharma-continuum/fast-syntax-highlighting.git" \
    "$HOME/.zsh/plugins/fast-syntax-highlighting"

install_plugin "https://github.com/zsh-users/zsh-autosuggestions.git" \
    "$HOME/.zsh/plugins/zsh-autosuggestions"

install_plugin "https://github.com/zsh-users/zsh-completions.git" \
    "$HOME/.zsh/plugins/zsh-completions"

# 3. 检查并安装 Homebrew 依赖
info "正在检查 Homebrew..."
if ! command -v brew &> /dev/null; then
    error "Homebrew未安装！请先安装 Homebrew。"
fi

info "正在通过 Brewfile 安装依赖..."
brew bundle install --file="$BREWFILE" || {
    error "Brewfile 依赖安装失败！"
}

# 4. 同步 zsh 配置
info "正在同步 zsh 配置..."
if [ -f "$ZSH_SCRIPT" ]; then
    sh "$ZSH_SCRIPT" 2 || error "同步 zsh 配置失败！"
else
    error "找不到 zsh 同步脚本: $ZSH_SCRIPT"
fi

# 5. 同步其他配置
info "正在同步其他配置..."
if [ -f "$OTHER_SCRIPT" ]; then
    sh "$OTHER_SCRIPT" 2 || error "同步其他配置失败！"
else
    warn "找不到其他同步脚本: $OTHER_SCRIPT"
fi

info "所有操作完成！系统已准备就绪。"
