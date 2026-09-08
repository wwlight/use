#!/bin/zsh
# ~/.zshrc — macos

# Homebrew: skip auto-update, quiet env hints
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1

# docker compose
export COMPOSE_FILE=$HOME/.docker/compose.yml

# vite+ environment init
[[ -r $HOME/.vite-plus/env ]] && . "$HOME/.vite-plus/env"

# PATH (N == Null Glob)
typeset -U path PATH
path=(
    $HOME/.cargo/bin(N)
    $HOME/.local/bin(N)  # uv tool
    $HOME/.opencode/bin(N)
    $path
)

[[ -r $HOME/.zsh/.zshrc_core ]] && source $HOME/.zsh/.zshrc_core

fpath+=(
    ${HOMEBREW_PREFIX:-${commands[brew]:h:h}}/share/zsh/site-functions(N)
)

# mise
if (( $+commands[mise] )); then
    eval "$(mise activate zsh)"
fi
