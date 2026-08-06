#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$PROJECT_ROOT/configs/macos/brew-mirror.zsh"

init_manifest macos

MANIFEST_CONFIG="$SCRIPT_DIR/lib/manifest-config.mjs"

usage() {
    node "$MANIFEST_CONFIG" usage-pm
}

# Resolve the Homebrew mirror and print its ID to stdout.
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
            error "Unknown argument: $arg"
        }
        echo "$mirror"
        return 0
    fi

    if ! has_tty; then
        usage >&2
        error "Pass an argument in non-interactive environments (example: vpr pm -- ustc)"
    fi

    local menu_args=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        menu_args+=("$line")
    done < <(node "$MANIFEST_CONFIG" menu-mirrors)

    local choice=""
    choice=$(node "$SCRIPT_DIR/lib/menu-select.mjs" \
        "Choose a Homebrew mirror" \
        "${menu_args[@]}") || choice=""
    choice=${choice//$'\r'/}
    choice=${choice//$'\n'/}

    if [[ -z "$choice" ]]; then
        usage >&2
        error "Pass an argument in non-interactive environments (example: vpr pm -- ustc)"
    fi

    node "$MANIFEST_CONFIG" has-mirror "$choice" || {
        error "Invalid selection: ${choice}"
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
        if (cfg.label) lines.push('# Homebrew mirror configuration - ' + cfg.label);
        if (cfg.brewGitRemote) lines.push('export HOMEBREW_BREW_GIT_REMOTE=\"' + cfg.brewGitRemote + '\"');
        if (cfg.bottleDomain) lines.push('export HOMEBREW_BOTTLE_DOMAIN=\"' + cfg.bottleDomain + '\"');
        if (cfg.apiDomain) lines.push('export HOMEBREW_API_DOMAIN=\"' + cfg.apiDomain + '\"');
        process.stdout.write(lines.join('\n'));
    " "$MANIFEST_PATH" "$mirror"
}

load_mirror_env() {
    eval "$(mirror_exports "$1" | grep '^export HOMEBREW_' || true)"
}

deploy_brew_mirror() {
    local target_dir="$HOME/.zsh/functions"
    mkdir -p "$target_dir" || error "Failed to create $target_dir"
    cp "$PROJECT_ROOT/configs/macos/brew-mirror.zsh" "$target_dir/brew-mirror.zsh" ||
        error 'Failed to deploy brew-mirror'
}

persist_zprofile() {
    local mirror="$1"
    local file_display
    file_display=$(manifest_get "zprofile")
    command -v brew >/dev/null || error "brew not found; cannot write $file_display"

    _brew_mirror_write_config "$mirror" || error 'Failed to write Homebrew mirror configuration'
    _brew_mirror_ensure_profile || error "Failed to update $file_display"
    # Apply the selected mirror to this installer process immediately.
    . "$(_brew_mirror_config_file)"
    deploy_brew_mirror
    info "Configured Homebrew mirror ($mirror) in $file_display"
}

run_install_script() {
    local mirror="$1"
    local mode url

    IFS=$'\t' read -r mode url < <(node "$MANIFEST_CONFIG" mirror-install "$mirror")

    if [[ "$mode" == "git" ]]; then
        git clone --depth=1 "$url" brew-install || {
            error "Failed to download the Homebrew installer!"
        }
        /bin/bash brew-install/install.sh || {
            rm -rf brew-install
            error "Homebrew installation failed!"
        }
        rm -rf brew-install
    else
        /bin/bash -c "$(curl -fsSL "$url")" || {
            error "Homebrew installation failed!"
        }
    fi
}

install_homebrew() {
    local mirror="${1:-ustc}"

    if command -v brew &> /dev/null; then
        persist_zprofile "$mirror"
        info "Homebrew is already installed; skipping"
        return 0
    fi

    if [[ "$mirror" == "official" ]]; then
        info "Homebrew is not installed; installing from upstream..."
    else
        info "Homebrew is not installed; installing from the $mirror mirror..."
    fi

    load_mirror_env "$mirror"
    run_install_script "$mirror"
    persist_zprofile "$mirror"

    source "$(expand_path "$(manifest_get "zprofile")")"
    brew update || {
        error "Homebrew update failed!"
    }
    info "Homebrew installation complete"
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
