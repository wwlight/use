#!/bin/bash

# 引入公共函数库
SCRIPT_DIR="./scripts"
source "$SCRIPT_DIR/lib/utils.sh"

# ==============================
# 主安装函数
# ==============================
install_zsh_for_git() {
    # 步骤1: 下载 zsh 压缩包
    local download_url="https://mirror.msys2.org/msys/x86_64/zsh-5.9-4-x86_64.pkg.tar.zst"
    local zip_file="$HOME/Desktop/zsh-5.9-4-x86_64.pkg.tar.zst"

    info "步骤1/4: 下载 zsh 压缩包..."
    if ! curl --ssl-no-revoke -L "$download_url" -o "$zip_file"; then
        error "下载 zsh 压缩包失败"
        return 1
    fi
    info "下载完成: $zip_file"

    # 步骤2: 获取 Git 安装路径
    info "步骤2/4: 查找 Git 安装路径..."
    local git_path=$(scoop prefix git)
    if [[ -z "$git_path" ]]; then
        error "无法获取 Git 路径"
        smart_clean "$zip_file"
        return 1
    fi
    info "Git 路径: $git_path"
    echo

    # 步骤3: 直接解压到 Git 目录
    info "步骤3/4: 直接解压到 Git 目录..."
    if ! command -v 7z &>/dev/null; then
        error "7z 命令未找到，请安装 7-Zip"
        smart_clean "$zip_file"
        return 1
    fi

    # 创建临时目录用于解压
    local temp_extract_dir="$HOME/Desktop/zsh-temp-extract"
    smart_clean "$temp_extract_dir"
    mkdir -p "$temp_extract_dir"

    # 直接解压 .tar.zst 到临时目录
    if ! 7z x -so "$zip_file" | 7z x -si -ttar -o"$temp_extract_dir"; then
        error "解压失败"
        smart_clean "$zip_file"
        smart_clean "$temp_extract_dir"
        return 1
    fi

    # 移动文件到 Git 目录
    info "移动文件到 Git 目录..."
    shopt -s dotglob  # 包含隐藏文件
    if cp -rf "$temp_extract_dir"/* "$git_path" 2> "$HOME/Desktop/cp_error.log"; then
        info "文件移动完成"
    else
        error "移动失败"
        smart_clean "$zip_file"
        smart_clean "$temp_extract_dir"
        return 1
    fi

    # 步骤4: 清理临时文件
    info "步骤4/4: 清理临时文件..."
    smart_clean "$zip_file"
    smart_clean "$temp_extract_dir"

    info "🎉 zsh 安装完成！"
}

# ==============================
# 主执行流程
# ==============================
main() {
    info "===== zsh for Git 安装脚本 ====="
    check_target_system "Windows"

    install_zsh_for_git
}

main
