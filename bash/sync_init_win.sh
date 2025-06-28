#!/bin/bash

# 定义路径
SCOOP_BACKUP="./windows/scoop_backup.json"
SCRIPT_DIR="./bash"
ZSH_SCRIPT="$SCRIPT_DIR/sync_zsh_win.sh"
OTHER_SCRIPT="$SCRIPT_DIR/sync_other.sh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 打印带颜色的状态信息
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 1. 创建目录结构
info "正在创建目录结构..."
mkdir -p D:/{DevelopApplication,SystemApplication} || warn "部分 D: 目录已存在"
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

# 3. 检查并安装 Scoop 依赖
info "正在检查 Scoop..."
if ! command -v scoop &> /dev/null; then
    error "Scoop 未安装！请先安装 Scoop。"
fi

info "正在通过 Scoop 备份文件恢复应用..."
if [ -f "$SCOOP_BACKUP" ]; then
    scoop import "$SCOOP_BACKUP" || {
        error "Scoop 应用恢复失败！"
    }
else
    error "找不到 Scoop 备份文件: $SCOOP_BACKUP"
fi

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
