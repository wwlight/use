#!/bin/bash

# 引入公共函数库
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ==============================
# 主安装函数
# ==============================
install_git_extras() {
    # 步骤1: 克隆仓库
    info "步骤1/5: 克隆 git-extras 仓库到桌面..."
    git clone https://github.com/tj/git-extras.git ~/Desktop/git-extras || {
        error "克隆 git-extras 仓库失败"
    }

    # 步骤2: 进入目录
    info "步骤2/5: 进入 git-extras 目录..."
    cd ~/Desktop/git-extras || {
        error "无法进入 ~/Desktop/git-extras 目录"
    }

    # 步骤3: 检出最新版本
    info "步骤3/5: 检出最新版本..."
    local latest_tag=$(git describe --tags $(git rev-list --tags --max-count=1))
    git checkout "$latest_tag" || {
        error "检出最新标签失败"
    }
    info "已检出版本: $latest_tag"

    # 步骤4: 安装
    info "步骤4/5: 正在安装 git-extras..."
    local git_path=$(scoop prefix git)
    if [[ -z "$git_path" ]]; then
        error "无法获取 Git 路径"
        return 1
    fi
    if [[ -f "./install.cmd" ]]; then
        ./install.cmd "$git_path" || {
            warn "安装命令执行可能不完全成功，请手动检查"
        }
    else
        warn "未找到 install.cmd 文件"
    fi

    # 步骤5: 验证安装
    info "步骤5/5: 验证安装..."
    git extras --help >/dev/null 2>&1 || {
        error "git extras 命令验证失败，可能安装未成功"
    }
    info "安装验证成功"

    # 清理
    info "清理临时文件..."
    cd ~/Desktop && smart_clean "git-extras"
    info "🎉 git-extras 安装完成!"
}

# ==============================
# 主执行流程
# ==============================
main() {
    info "===== git-extras 安装脚本 ====="
    check_target_system "Windows"

    install_git_extras
}

# 执行主函数
main
