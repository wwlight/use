#!/bin/zsh
# ~/.zshrc — windows

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

[[ -r $HOME/.zsh/.zshrc_core ]] && source $HOME/.zsh/.zshrc_core
