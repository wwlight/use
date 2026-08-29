#!/bin/zsh
# ~/.zshrc — macos

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

# mise
if (( $+commands[mise] )); then
    eval "$(mise activate zsh)"
fi
