#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/../.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$PROJECT_ROOT/scripts/macos/brew/mirror/manage.zsh"

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

    # USE_BREW_MIRROR is install-time only; USE_HOMEBREW_MIRROR is the runtime marker.
    if [[ -z "$mirror" && -n "${USE_BREW_MIRROR:-}" ]]; then
        mirror="${USE_BREW_MIRROR}"
    fi

    if [[ -n "$mirror" ]]; then
        node "$MANIFEST_CONFIG" has-mirror "$mirror" || {
            usage >&2
            error "Unknown argument: ${arg:-$mirror}"
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

    # Do not capture node stdout; keep the TTY so the ↑↓ menu is visible.
    local out choice=""
    out=$(mktemp) || error 'Could not create temp file for mirror selection'
    if MENU_SELECT_OUT="$out" node "$SCRIPT_DIR/lib/menu-select.mjs" \
        "Choose a Homebrew mirror" \
        "${menu_args[@]}"; then
        choice=$(tr -d '\r\n' <"$out" 2>/dev/null || true)
    fi
    rm -f "$out"

    if [[ -z "$choice" ]]; then
        usage >&2
        error "Pass an argument in non-interactive environments (example: vpr pm -- ustc)"
    fi

    node "$MANIFEST_CONFIG" has-mirror "$choice" || {
        error "Invalid selection: ${choice}"
    }
    echo "$choice"
}

deploy_homebrew_runtime() {
    local target_dir catalog_repo helper_repo menu_cli_src menu_src width_src tty_src
    target_dir="${XDG_CONFIG_HOME:-$HOME/.config}/homebrew"
    catalog_repo="$PROJECT_ROOT/$(manifest_get brewMirrorCatalog)"
    helper_repo="$PROJECT_ROOT/scripts/macos/brew/mirror/manage.zsh"
    menu_cli_src="$PROJECT_ROOT/scripts/macos/brew/mirror/menu.mjs"
    menu_src="$PROJECT_ROOT/scripts/lib/menu-select.mjs"
    width_src="$PROJECT_ROOT/scripts/lib/string-width.mjs"
    tty_src="$PROJECT_ROOT/scripts/lib/tty-term.mjs"

    [[ -f "$catalog_repo" ]] || error "Homebrew mirror catalog not found: $catalog_repo"
    [[ -f "$helper_repo" ]] || error "Homebrew mirror helper not found: $helper_repo"
    [[ -f "$menu_cli_src" ]] || error "brew mirror menu.mjs not found: $menu_cli_src"
    [[ -f "$menu_src" ]] || error "menu-select.mjs not found: $menu_src"
    [[ -f "$width_src" ]] || error "string-width.mjs not found: $width_src"
    [[ -f "$tty_src" ]] || error "tty-term.mjs not found: $tty_src"

    mkdir -p "$target_dir/lib" || error "Failed to create $target_dir/lib"
    cp "$catalog_repo" "$target_dir/mirrors.tsv" || error 'Failed to deploy Homebrew mirror catalog'
    cp "$helper_repo" "$target_dir/manage.zsh" || error 'Failed to deploy brew mirror manage.zsh'
    cp "$menu_cli_src" "$target_dir/lib/menu.mjs" || error 'Failed to deploy brew mirror menu.mjs'
    cp "$menu_src" "$target_dir/lib/menu-select.mjs" || error 'Failed to deploy menu-select.mjs'
    cp "$width_src" "$target_dir/lib/string-width.mjs" || error 'Failed to deploy string-width.mjs'
    cp "$tty_src" "$target_dir/lib/tty-term.mjs" || error 'Failed to deploy tty-term.mjs'
    _brew_mirror_remove_legacy || warn "Could not remove legacy brew-mirror helper"
}

apply_selected_mirror() {
    local mirror="$1"
    local file_display
    file_display=$(manifest_get "zprofile")

    _brew_mirror_write_config "$mirror" || error 'Failed to write Homebrew mirror configuration'
    _brew_mirror_ensure_profile || error "Failed to update $file_display"
    _brew_mirror_apply_env || error 'Failed to apply Homebrew mirror environment'
    info "Configured Homebrew mirror ($mirror) in $file_display"
}

load_mirror_env_for_install() {
    local mirror="$1"
    _brew_mirror_write_config "$mirror" || error 'Failed to write Homebrew mirror configuration'
    # shellcheck disable=SC1090
    . "$(_brew_mirror_config_file)" || error 'Failed to load Homebrew mirror configuration'
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
    local mirror="$1"

    deploy_homebrew_runtime

    # Do not use `command -v brew`: manage.zsh defines brew(), which would
    # always look installed even when the Homebrew binary is missing.
    if _brew_mirror_find_brew >/dev/null 2>&1; then
        apply_selected_mirror "$mirror"
        info "Homebrew is already installed; skipping"
        return 0
    fi

    if [[ "$mirror" == "official" ]]; then
        info "Homebrew is not installed; installing from upstream..."
    else
        info "Homebrew is not installed; installing from the $mirror mirror..."
    fi

    load_mirror_env_for_install "$mirror"
    run_install_script "$mirror"
    apply_selected_mirror "$mirror"

    local brew_bin
    brew_bin=$(_brew_mirror_find_brew) || error "Homebrew binary not found after install"
    "$brew_bin" update || {
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
