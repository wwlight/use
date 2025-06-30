#!/bin/bash

# 引入公共函数库
source ./bash/utils.sh

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
        cp -v ~/.zprofile ./mac/.zprofile
        cp -v ~/.zshrc ./mac/.zshrc
        cp -v ~/.bashrc ./mac/.bashrc
        cp -v ~/.zsh/functions/utils.zsh ./mac/utils.zsh
        ;;
    2)
        # 备份系统配置文件
        backup_file ~/.zshrc ~/.backup

        # mac 目录 -> 本地目录
        cp -v ./mac/.zprofile ~/.zprofile
        cp -v ./mac/.zshrc ~/.zshrc
        cp -v ./mac/.bashrc ~/.bashrc
        mkdir -p ~/.zsh/functions && cp -v ./mac/utils.zsh ~/.zsh/functions/utils.zsh
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo "操作完成！"
