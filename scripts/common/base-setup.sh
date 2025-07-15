#!/bin/bash

# 引入公共函数库
SCRIPT_DIR="./scripts"
source "$SCRIPT_DIR/lib/utils.sh"

# ==============================
# 设置 Git 配置
# ==============================
setup_git() {
    # 检查是否安装 git
    if ! command -v git &> /dev/null; then
        error "Git 未安装，跳过 Git 配置"
        return
    fi

    info "配置 Git..."

    # 显示当前配置
    info "当前 Git 全局配置:"
    git config --global -l

    # 设置默认分支为 main
    git config --global init.defaultBranch main

    # 设置文件大小写敏感
    git config --global core.ignorecase false

    # 忽略目录安全限制
    git config --global safe.directory "*"

    # 记住提交账号密码
    git config --global credential.helper store

    # 询问是否跳过用户名和邮箱配置
    read -p "是否跳过 Git 用户名和邮箱配置？(y/n) [默认 n]: " skip_config
    skip_config=${skip_config:-n}  # 默认值为 'n'

    if [[ "$skip_config" != "y" && "$skip_config" != "Y" ]]; then
        # 提示输入用户名和邮箱
        read -p "请输入 Git 用户名: " username
        git config --global user.name "$username"

        read -p "请输入 Git 邮箱: " email
        git config --global user.email "$email"
    else
        info "已跳过 Git 用户名和邮箱配置"
    fi

    # 显示更新后的配置
    info "更新后的 Git 全局配置:"
    git config --global -l
}

# ==============================
# 设置 fnm 和 Node.js
# ==============================
setup_node() {
    # 检查是否安装 fnm
    if ! command -v fnm &> /dev/null; then
        error "fnm 未安装，跳过 Node.js 配置"
        return
    fi

    info "配置 Node.js..."

    # 列出已安装版本
    info "已安装的 Node.js 版本:"
    fnm ls

    # 安装 LTS 版本
    info "安装最新的 LTS 版本..."
    fnm install --lts

    # 显示 Node.js 版本
    info "当前 Node.js 版本:"
    node -v

    # 设置 npm 全局安装目录
    info "设置 npm 全局安装目录..."
    npm config set prefix ~/.npm_global

    # 安装 ni 工具
    info "安装 @antfu/ni..."
    npm i -g @antfu/ni
}

# ==============================
# 主执行流程
# ==============================
main() {
    setup_git
    info "\n=================================\n"
    setup_node
}

# 执行主函数
main
