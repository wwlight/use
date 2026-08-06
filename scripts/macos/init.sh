#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$PROJECT_ROOT/configs/macos/brew-mirror.zsh"

init_manifest macos

MANIFEST_CONFIG="$SCRIPT_DIR/lib/manifest-config.mjs"
RUN_BREW="$SCRIPT_PATH/run-brew.sh"

usage() {
    node "$MANIFEST_CONFIG" usage-init
}

# Resolve the installation profile and print it to stdout.
resolve_brew_profile() {
    local arg="${1:-}"
    local profile=""

    case "$arg" in
        "" ) ;;
        --*) profile="${arg#--}" ;;
        *) profile="$arg" ;;
    esac

    if [[ -n "$profile" ]]; then
        node "$MANIFEST_CONFIG" has-profile "$profile" || {
            usage >&2
            error "Unknown argument: $arg"
        }
        echo "$profile"
        return 0
    fi

    if ! has_tty; then
        error "Pass an argument in non-interactive environments (example: vpr init -- lite)"
    fi

    local menu_args=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        menu_args+=("$line")
    done < <(node "$MANIFEST_CONFIG" menu-profiles)

    local choice=""
    choice=$(node "$SCRIPT_DIR/lib/menu-select.mjs" \
        "Choose the Homebrew installation profile" \
        "${menu_args[@]}") || choice=""
    choice=${choice//$'\r'/}
    choice=${choice//$'\n'/}

    if [[ -z "$choice" ]]; then
        error "Pass an argument in non-interactive environments (example: vpr init -- lite)"
    fi

    node "$MANIFEST_CONFIG" has-profile "$choice" || {
        error "Invalid selection: ${choice}"
    }
    echo "$choice"
}

setup_directories() {
    next_step "Creating directory structure..."
    local dir path
    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        path=$(expand_path "$dir")
        mkdir -p "$path" || warn "Directory could not be created or already exists: $path"
    done < <(manifest_directories)
}

install_or_restore_brew() {
    local profile="$1"
    local label brewfile
    label=$(node "$MANIFEST_CONFIG" profile-label "$profile")
    next_step "Restoring Homebrew dependencies (${label})..."

    brewfile=$(node "$MANIFEST_CONFIG" profile-artifact macos "$profile")
    local BREWFILE="$PROJECT_ROOT/$brewfile"

    _brew_mirror_apply_env || error 'Failed to apply Homebrew mirror environment'
    # Do not use `command -v brew`: brew-mirror.zsh defines brew() as a wrapper.
    if ! _brew_mirror_find_brew >/dev/null 2>&1; then
        error "Homebrew is not installed. Run: vpr pm"
    fi

    if [ -f "$BREWFILE" ]; then
        info "Installing dependencies from $(basename "$BREWFILE")..."
        bash "$RUN_BREW" bundle install --file="$BREWFILE" || {
            error "Brewfile dependency installation failed!"
        }
        info "Brewfile dependencies installed"
    else
        error "Brewfile not found: $BREWFILE"
    fi
}

install_zsh_plugins() {
    next_step "Installing Zsh plugins..."
    bash "$SCRIPT_DIR/common/zsh-plugins-install.sh" || error "Zsh plugin installation failed!"
}

sync_configurations() {
    local profile="$1"
    next_step "Syncing configuration..."
    local CONFIG_SCRIPT="$SCRIPT_DIR/macos/config-sync.sh"
    local BASE_SCRIPT="$SCRIPT_DIR/common/git-setup.sh"

    if [ -f "$CONFIG_SCRIPT" ]; then
        SYNC_PROFILE="$profile" SYNC_SELECT_ALL=1 bash "$CONFIG_SCRIPT" 2 || error "Configuration sync failed!"
    else
        error "Configuration sync script not found: $CONFIG_SCRIPT"
    fi

    # Defense in depth: config-sync also removes this; keep init resilient if an
    # older sync script is still on disk.
    _brew_mirror_remove_legacy || true

    if [ -f "$BASE_SCRIPT" ]; then
        bash "$BASE_SCRIPT" || error "Base configuration initialization failed!"
    else
        warn "Base configuration initialization script not found: $BASE_SCRIPT"
    fi
}

main() {
    check_target_os "macos"

    while [[ "${1:-}" == "--" ]]; do shift; done

    case "${1:-}" in
        -h|--help|help) usage; exit 0 ;;
    esac

    local profile
    profile=$(resolve_brew_profile "${1:-}") || exit $?

    local INIT_STEP_COUNT=4
    init_step_progress "$INIT_STEP_COUNT"

    setup_directories
    install_or_restore_brew "$profile"
    install_zsh_plugins
    sync_configurations "$profile"

    info "All operations complete. The system is ready."
}

main "$@"
