#!/bin/zsh
# ~/.zshrc — macos

# docker compose
export COMPOSE_FILE=$HOME/.docker/compose.yml

# vite+ 环境初始化
[[ -r $HOME/.vite-plus/env ]] && . "$HOME/.vite-plus/env"

# PATH (N == Null Glob)
typeset -U path PATH
path=(
    $HOME/.cargo/bin(N)
    $HOME/.local/bin(N)  # uv tool
    $HOME/.opencode/bin(N)
    $path
)

# sdkman（懒加载）
export SDKMAN_DIR=$(brew --prefix sdkman-cli)/libexec
if [[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]]; then
    sdk() {
        unset -f sdk
        source "${SDKMAN_DIR}/bin/sdkman-init.sh"
        sdk "$@"
    }
fi

[[ -r $HOME/.zsh/.zshrc_core ]] && source $HOME/.zsh/.zshrc_core
