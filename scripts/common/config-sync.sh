#!/bin/bash

# 默认不自动选择
direction=""

# 检查是否有参数
if [ "$1" = "1" ] || [ "$1" = "2" ]; then
    direction=$1
else
    echo "请选择拷贝方向:"
    echo "1) 从本地目录拷贝到 common 目录"
    echo "2) 从 common 目录拷贝到本地目录"
    read -r direction
fi

case $direction in
    1)
        # 本地目录 -> common 目录
        cp -v ~/.zsh/zfunc/_eza ./configs/common/_eza
        cp -v ~/.config/starship/starship.toml ./configs/common/starship.toml
        ;;
    2)
        # common 目录 -> 本地目录
        mkdir -p ~/.zsh/zfunc && cp -v ./configs/common/_eza ~/.zsh/zfunc/_eza
        mkdir -p ~/.config/starship && cp -v ./configs/common/starship.toml ~/.config/starship/starship.toml
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo "操作完成！"
