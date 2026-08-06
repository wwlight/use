#!/bin/bash
# Apply the active Homebrew mirror, then run brew.
# Used by init / setup / backup so bash entry points honor the selected mirror.

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/../.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HELPER_DEPLOYED="${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/manage.zsh"
HELPER_REPO="$PROJECT_ROOT/scripts/macos/brew/mirror/manage.zsh"

if [[ -r "$HELPER_DEPLOYED" ]]; then
    # shellcheck disable=SC1090
    . "$HELPER_DEPLOYED"
elif [[ -r "$HELPER_REPO" ]]; then
    # shellcheck disable=SC1090
    . "$HELPER_REPO"
else
    echo "run: brew mirror helper not found" >&2
    exit 1
fi

_brew_mirror_apply_env || {
    echo "run: failed to apply Homebrew mirror environment" >&2
    exit 1
}

# Resolve the real binary; `command -v brew` is poisoned by the brew() wrapper.
brew_bin=$(_brew_mirror_find_brew) || {
    echo "run: brew not found; run vpr pm first" >&2
    exit 1
}

exec "$brew_bin" "$@"
