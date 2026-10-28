#!/bin/zsh
# ~/.zshrc — windows

# Local-only variables, not tracked in git
[[ -f $HOME/.zshrc.local ]] && source $HOME/.zshrc.local

# vite+ environment init
[[ -r $HOME/.vite-plus/env ]] && . "$HOME/.vite-plus/env"

# PATH (N == Null Glob)
# Strip bare "/" — MSYS resolves //cmd as UNC and stalls command lookup.
typeset -U path PATH
path=(
    $HOME/.local/bin(N)  # uv tool
    ${path:#/}
)

[[ -r $HOME/.zsh/.zshrc_core ]] && source $HOME/.zsh/.zshrc_core

# mise — shims only; 'mise activate zsh' fails under MSYS
(( $+commands[mise] )) && {
    mise reshim >/dev/null 2>&1
    _ms="$(cygpath -u "$LOCALAPPDATA/mise/shims" 2>/dev/null)"
    [[ -n "$_ms" && -d "$_ms" ]] && path=("$_ms" $path)
}

# Dynamic proxy toggle (Clash)
proxy_on() {
  export http_proxy="http://127.0.0.1:7890"
  export https_proxy="http://127.0.0.1:7890"
  export all_proxy="socks5://127.0.0.1:7890"
  export no_proxy="localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,*.local"
}

proxy_off() {
  unset http_proxy https_proxy all_proxy no_proxy \
        HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
}

# Probe Clash port 7890 on every new shell; enable proxy if it is listening
if nc -z -w 1 127.0.0.1 7890 2>/dev/null; then
  proxy_on
fi
