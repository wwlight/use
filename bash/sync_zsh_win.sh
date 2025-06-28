#!/bin/bash

# 默认不自动选择
direction=""

# 检查是否有参数
if [ "$1" = "1" ] || [ "$1" = "2" ]; then
    direction=$1
else
    echo "请选择拷贝方向:"
    echo "1) 从本地目录拷贝到 windows 目录"
    echo "2) 从 windows 目录拷贝到本地目录"
    read -r direction
fi

case $direction in
    1)
        # 本地目录 -> windows 目录
        cp -v ~/.zshrc ./windows/.zshrc
        cp -v ~/.bashrc ./windows/.bashrc
        cp -v ~/.zsh/functions/utils.zsh ./windows/utils.zsh
        ;;
    2)
        # windows 目录 -> 本地目录
        cp -v ./windows/.zshrc ~/.zshrc
        cp -v ./windows/.bashrc ~/.bashrc
        cp -v ./windows/utils.zsh ~/.zsh/functions/utils.zsh
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo "操作完成！"
