#!/bin/bash

# 引入公共函数库（基于脚本绝对路径，支持在任意目录执行）
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

usage() {
    cat <<EOF
用法: $(basename "$0") [official|ustc|tuna]

  official  官方源（默认）
  ustc      中科大镜像 https://mirrors.ustc.edu.cn/help/brew.git.html
  tuna      清华大学镜像

示例:
  bash $(basename "$0")
  bash $(basename "$0") ustc
  npm run mac:brew -- ustc
EOF
}

mirror_exports() {
    case "$1" in
        ustc)
            cat <<'EOF'
# Homebrew 镜像配置 - 中科大镜像源
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
EOF
            ;;
        tuna)
            cat <<'EOF'
# Homebrew 镜像配置 - 清华大学镜像源
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
EOF
            ;;
        official)
            cat <<'EOF'
# Homebrew 镜像配置（官方源，未启用镜像）
EOF
            ;;
    esac
}

# 从 mirror_exports 加载镜像变量，仅用于本次安装进程
load_mirror_env() {
    eval "$(mirror_exports "$1" | grep '^export HOMEBREW_' || true)"
}

# 安装完成后写入 ~/.zprofile（brew shellenv + 镜像配置）
persist_zprofile() {
    local mirror="$1"
    local file="$HOME/.zprofile"
    local brew_path

    brew_path=$(command -v brew) || error "brew 未找到，无法写入 $file"

    {
        echo "eval \"\$($brew_path shellenv)\""
        echo
        mirror_exports "$mirror"
    } > "$file"

    info "已写入 $file"
}

run_install_script() {
    local mirror="$1"

    case "$mirror" in
        tuna)
            git clone --depth=1 https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/install.git brew-install || {
                error "Homebrew 安装脚本下载失败！"
            }
            /bin/bash brew-install/install.sh || {
                rm -rf brew-install
                error "Homebrew 安装失败！"
            }
            rm -rf brew-install
            ;;
        *)
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
                error "Homebrew 安装失败！"
            }
            ;;
    esac
}

install_homebrew() {
    local mirror="${1:-official}"

    if command -v brew &> /dev/null; then
        info "Homebrew 已安装，跳过"
        return 0
    fi

    if [[ "$mirror" == "official" ]]; then
        info "Homebrew 未安装，正在从官方源安装..."
    else
        info "Homebrew 未安装，正在从 $mirror 镜像安装..."
    fi

    load_mirror_env "$mirror"
    run_install_script "$mirror"
    persist_zprofile "$mirror"

    source ~/.zprofile
    brew update || {
        error "Homebrew 更新失败！"
    }
    info "Homebrew 安装成功"
}

main() {
    local mirror="official"

    case "${1:-}" in
        ""|official|ustc|tuna) mirror="${1:-official}" ;;
        -h|--help|help) usage; exit 0 ;;
        *) usage >&2; error "未知参数: $1" ;;
    esac

    check_target_system "macOS"
    install_homebrew "$mirror"
}

main "$@"
