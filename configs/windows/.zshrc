#!/bin/zsh
# ~/.zsh/.zshrc — windows

# vp (vite+) 环境初始化
. "$HOME/.vite-plus/env"

# PATH (N == Null Glob)
typeset -U path PATH
path=(
    $HOME/.local/bin(N)  # uv tool
    $HOME/.npm_global/bin(N)
    $HOME/.opencode/bin(N)
    $path
)

[[ -r $ZSH/.zshrc_core ]] && source $ZSH/.zshrc_core
