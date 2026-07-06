#!/bin/zsh
# ~/.zsh/.zshrc — mac

# docker compose
export COMPOSE_FILE=$HOME/.docker/compose.yml

# PATH (N == Null Glob)
typeset -U path PATH
path=(
    $HOME/.local/bin(N)
    $HOME/.vite-plus/bin(N)
    $HOME/.opencode/bin(N)
    $HOME/.cargo/bin(N)
    $path
)

# sdkman
export SDKMAN_DIR=$(brew --prefix sdkman-cli)/libexec
[[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]] && source "${SDKMAN_DIR}/bin/sdkman-init.sh"

[[ -r $ZSH/.zshrc_core ]] && source $ZSH/.zshrc_core
