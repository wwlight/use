#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

init_manifest common

setup_git() {
    if ! command -v git &> /dev/null; then
        warn 'git 未安装，跳过 git 配置'
        return
    fi

    local default_branch ignorecase safe_directory credential_helper
    default_branch=$(manifest_get "git.defaultBranch")
    ignorecase=$(manifest_get "git.ignorecase")
    safe_directory=$(manifest_get "git.safeDirectory")
    credential_helper=$(manifest_get "git.credentialHelper")

    git config --global init.defaultBranch "$default_branch"
    git config --global core.ignorecase "$ignorecase"
    git config --global safe.directory "$safe_directory"
    git config --global credential.helper "$credential_helper"

    if git config --global --get user.name &>/dev/null && git config --global --get user.email &>/dev/null; then
        info 'git 用户名和邮箱已配置，跳过'
        return
    fi

    if [ ! -t 0 ]; then
        info '非交互环境，跳过 git 用户名和邮箱配置'
        return
    fi

    read -p "是否跳过 git 用户名和邮箱配置？(y/n) [默认 n]: " skip_config
    skip_config=${skip_config:-n}

    if [[ "$skip_config" != "y" && "$skip_config" != "Y" ]]; then
        read -p "请输入 Git 用户名: " username
        git config --global user.name "$username"

        read -p "请输入 Git 邮箱: " email
        git config --global user.email "$email"
    fi
}

setup_git
