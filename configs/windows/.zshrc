#!/bin/zsh
# ~/.zsh/.zshrc — windows

# vp (vite+) 环境初始化
. "$HOME/.vite-plus/env"

# PATH (N == Null Glob)
typeset -U path PATH
path=(
    $HOME/.opencode/bin(N)
    $HOME/.npm_global/bin(N)
    $path
)

[[ -r $ZSH/.zshrc_core ]] && source $ZSH/.zshrc_core
