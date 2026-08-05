#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

init_manifest common

setup_git() {
    if ! command -v git &> /dev/null; then
        warn 'Git is not installed; skipping Git configuration'
        return
    fi

    local default_branch ignorecase safe_directory credential_helper
    default_branch=$(manifest_get "git.defaultBranch")
    ignorecase=$(manifest_get "git.ignorecase")
    safe_directory=$(manifest_get "git.safeDirectory")
    credential_helper=$(manifest_get "git.credentialHelper")

    git config --global init.defaultBranch "$default_branch"
    git config --global core.ignorecase "$ignorecase"
    git config --global --replace-all safe.directory "$safe_directory"
    git config --global credential.helper "$credential_helper"

    if git config --global --get user.name &>/dev/null && git config --global --get user.email &>/dev/null; then
        info 'Git username and email are already configured; skipping'
        return
    fi

    local skip_config username email
    if ! skip_config=$(read_tty "Skip Git username and email configuration? (y/n) [default: n]: "); then
        info 'Non-interactive environment; skipping Git username and email configuration'
        return
    fi
    skip_config=${skip_config:-n}

    if [[ "$skip_config" != "y" && "$skip_config" != "Y" ]]; then
        username=$(read_tty "Enter Git username: ") || error "Git username was not provided"
        username=${username//$'\r'/}
        [ -n "$username" ] || error "Git username was not provided"
        git config --global user.name "$username"

        email=$(read_tty "Enter Git email: ") || error "Git email was not provided"
        email=${email//$'\r'/}
        [ -n "$email" ] || error "Git email was not provided"
        git config --global user.email "$email"
    fi
}

setup_git
