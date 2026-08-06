#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$PROJECT_ROOT/scripts/macos/brew/mirror/manage.zsh"

init_manifest macos
check_target_os "macos"

run_config_sync macos "$@"

_brew_mirror_remove_legacy || true
