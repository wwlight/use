#!/bin/bash
set -o pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

init_manifest common

if command -v vp &>/dev/null; then
    info 'vite.plus 已安装，跳过'
    exit 0
fi

install_url=$(manifest_get "vitePlus.installUrlSh")

info '正在安装 vite.plus...'
curl -fsSL "$install_url" | bash || error 'vite.plus 安装失败！'
info 'vite.plus 安装成功'
