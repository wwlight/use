#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

init_manifest macos

MANIFEST_CONFIG="$SCRIPT_DIR/lib/manifest-config.mjs"

usage() {
    node "$MANIFEST_CONFIG" usage-pm
}

# 解析 Homebrew 镜像（stdout 输出 id）
resolve_brew_mirror() {
    local arg="${1:-}"
    local mirror=""

    case "$arg" in
        "" ) ;;
        --*) mirror="${arg#--}" ;;
        *) mirror="$arg" ;;
    esac

    if [[ -n "$mirror" ]]; then
        node "$MANIFEST_CONFIG" has-mirror "$mirror" || {
            usage >&2
            error "未知参数: $arg"
        }
        echo "$mirror"
        return 0
    fi

    if ! has_tty; then
        usage >&2
        error "非交互环境请传入参数（示例: vpr pm -- official）"
    fi

    local menu_args=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        menu_args+=("$line")
    done < <(node "$MANIFEST_CONFIG" menu-mirrors)

    local choice=""
    choice=$(node "$SCRIPT_DIR/lib/menu-select.mjs" \
        "请选择 Homebrew 镜像" \
        "${menu_args[@]}") || choice=""
    choice=${choice//$'\r'/}
    choice=${choice//$'\n'/}

    if [[ -z "$choice" ]]; then
        usage >&2
        error "非交互环境请传入参数（示例: vpr pm -- official）"
    fi

    node "$MANIFEST_CONFIG" has-mirror "$choice" || {
        error "无效选择: ${choice}"
    }
    echo "$choice"
}

mirror_exports() {
    local mirror="$1"
    node -e "
        const m = require(process.argv[1]);
        const mirror = process.argv[2];
        const cfg = m.brewMirrors[mirror] || {};
        const lines = [];
        if (cfg.label) lines.push('# Homebrew 镜像配置 - ' + cfg.label);
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
    local mode url

    IFS=$'\t' read -r mode url < <(node "$MANIFEST_CONFIG" mirror-install "$mirror")

    if [[ "$mode" == "git" ]]; then
        git clone --depth=1 "$url" brew-install || {
            error "Homebrew 安装脚本下载失败！"
        }
        /bin/bash brew-install/install.sh || {
            rm -rf brew-install
            error "Homebrew 安装失败！"
        }
        rm -rf brew-install
    else
        /bin/bash -c "$(curl -fsSL "$url")" || {
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

    case "${1:-}" in
        -h|--help|help) usage; exit 0 ;;
    esac

    check_target_os "macos"
    local mirror
    mirror=$(resolve_brew_mirror "${1:-}")
    install_homebrew "$mirror"
}

main "$@"
