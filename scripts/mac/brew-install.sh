#!/bin/bash

# 引入公共函数库（基于脚本绝对路径，支持在任意目录执行）
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

init_manifest mac

usage() {
    cat <<EOF
用法: $(basename "$0") [official|ustc|tuna]

  official  官方源（默认）
  ustc      中科大镜像 https://mirrors.ustc.edu.cn/help/brew.git.html
  tuna      清华大学镜像

示例:
  bash $(basename "$0")
  bash $(basename "$0") ustc
  vpr pm -- ustc
EOF
}

mirror_exports() {
    local mirror="$1"
    node -e "
        const m = require(process.argv[1]);
        const mirror = process.argv[2];
        const cfg = m.brewMirrors[mirror] || {};
        const lines = [];
        if (mirror === 'official') {
            lines.push('# Homebrew 镜像配置（官方源，未启用镜像）');
        } else if (mirror === 'ustc') {
            lines.push('# Homebrew 镜像配置 - 中科大镜像源');
        } else if (mirror === 'tuna') {
            lines.push('# Homebrew 镜像配置 - 清华大学镜像源');
        }
        if (cfg.brewGitRemote) lines.push('export HOMEBREW_BREW_GIT_REMOTE=\"' + cfg.brewGitRemote + '\"');
        if (cfg.bottleDomain) lines.push('export HOMEBREW_BOTTLE_DOMAIN=\"' + cfg.bottleDomain + '\"');
        if (cfg.apiDomain) lines.push('export HOMEBREW_API_DOMAIN=\"' + cfg.apiDomain + '\"');
        process.stdout.write(lines.join('\n'));
    " "$MANIFEST_PATH" "$mirror"
}

load_mirror_env() {
    eval "$(mirror_exports "$1" | grep '^export HOMEBREW_' || true)"
}

persist_zprofile() {
    local mirror="$1"
    local file_display file
    file_display=$(manifest_get "zprofile")
    file=$(expand_path "$file_display")
    local brew_path

    brew_path=$(command -v brew) || error "brew 未找到，无法写入 $file_display"

    {
        echo "eval \"\$($brew_path shellenv)\""
        echo
        mirror_exports "$mirror"
    } > "$file"

    info "已配置 Homebrew 镜像 ($mirror) 到 $file_display"
}

run_install_script() {
    local mirror="$1"

    if [[ "$mirror" == "tuna" ]]; then
        local install_git_repo
        install_git_repo=$(node -e "
            const m = require(process.argv[1]);
            process.stdout.write(m.brewMirrors.tuna.installGitRepo);
        " "$MANIFEST_PATH")
        git clone --depth=1 "$install_git_repo" brew-install || {
            error "Homebrew 安装脚本下载失败！"
        }
        /bin/bash brew-install/install.sh || {
            rm -rf brew-install
            error "Homebrew 安装失败！"
        }
        rm -rf brew-install
    else
        local install_script
        install_script=$(node -e "
            const m = require(process.argv[1]);
            process.stdout.write(m.brewMirrors.official.installScript);
        " "$MANIFEST_PATH")
        /bin/bash -c "$(curl -fsSL "$install_script")" || {
            error "Homebrew 安装失败！"
        }
    fi
}

install_homebrew() {
    local mirror="${1:-official}"

    if command -v brew &> /dev/null; then
        persist_zprofile "$mirror"
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

    source "$(expand_path "$(manifest_get "zprofile")")"
    brew update || {
        error "Homebrew 更新失败！"
    }
    info "Homebrew 安装成功"
}

main() {
    while [[ "${1:-}" == "--" ]]; do shift; done

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
