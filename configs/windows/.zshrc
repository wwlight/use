#!/bin/zsh
# ~/.zshrc — windows

# vite+ environment init
[[ -r $HOME/.vite-plus/env ]] && . "$HOME/.vite-plus/env"

# PATH (N == Null Glob)
# Strip bare "/" — MSYS resolves //cmd as UNC and stalls command lookup.
typeset -U path PATH
path=(
    $HOME/.local/bin(N)  # uv tool
    $HOME/.opencode/bin(N)
    ${path:#/}
)

[[ -r $HOME/.zsh/.zshrc_core ]] && source $HOME/.zsh/.zshrc_core

# mise — shims only; 'mise activate zsh' fails under MSYS
(( $+commands[mise] )) && {
    mise reshim >/dev/null 2>&1
    _ms="$(cygpath -u "$LOCALAPPDATA/mise/shims" 2>/dev/null)"
    [[ -n "$_ms" && -d "$_ms" ]] && path=("$_ms" $path)
}
