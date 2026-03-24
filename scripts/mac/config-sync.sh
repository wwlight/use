#!/bin/bash

# 引入公共函数库（基于脚本绝对路径，支持在任意目录执行）
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# 检查是否在 macOS 环境运行
check_target_system "macOS"

# =========================
# 主脚本开始
# =========================

# 默认不自动选择
direction=""

# 检查是否有参数
if [ "$1" = "1" ] || [ "$1" = "2" ]; then
    direction=$1
else
    echo "请选择拷贝方向:"
    echo "1) 从本地目录拷贝到 mac 目录"
    echo "2) 从 mac 目录拷贝到本地目录"
    read -r direction
fi

case $direction in
    1)
        # 本地目录 -> mac 目录
        cp -v ~/.zprofile "$PROJECT_ROOT/configs/mac/.zprofile"
        cp -v ~/.zshrc "$PROJECT_ROOT/configs/mac/.zshrc"
        cp -v ~/.bashrc "$PROJECT_ROOT/configs/mac/.bashrc"
        cp -v ~/.zsh/functions/utils.zsh "$PROJECT_ROOT/configs/mac/utils.zsh"
        cp -v ~/.config/ghostty/config "$PROJECT_ROOT/configs/mac/ghostty_config"
        ;;
    2)
        # 备份系统配置文件
        backup_file ~/.zshrc ~/.backup

        # mac 目录 -> 本地目录
        cp -v "$PROJECT_ROOT/configs/mac/.zprofile" ~/.zprofile
        cp -v "$PROJECT_ROOT/configs/mac/.zshrc" ~/.zshrc
        cp -v "$PROJECT_ROOT/configs/mac/.bashrc" ~/.bashrc
        mkdir -p ~/.zsh/functions && cp -v "$PROJECT_ROOT/configs/mac/utils.zsh" ~/.zsh/functions/utils.zsh
        mkdir -p ~/.config/ghostty && cp -v "$PROJECT_ROOT/configs/mac/ghostty_config" ~/.config/ghostty/config
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo "操作完成！"
