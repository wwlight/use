#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$PROJECT_ROOT/configs/macos/brew-mirror.zsh"

init_manifest macos
check_target_os "macos"

run_config_sync macos "$@"

# sync 2 restores ~/.config/homebrew/* but does not create the .zprofile block.
# Always drop the legacy functions override so it cannot shadow the new helper.
_brew_mirror_remove_legacy || true
