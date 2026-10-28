#!/bin/zsh
# ~/.zshrc — macos

# Homebrew: skip auto-update, quiet env hints, include auto_updates / :latest casks
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_UPGRADE_GREEDY=1
# Local-only variables, not tracked in git
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# docker compose
export COMPOSE_FILE=$HOME/.docker/compose.yml

# vite+ environment init
[[ -r $HOME/.vite-plus/env ]] && . "$HOME/.vite-plus/env"

# PATH (N == Null Glob)
typeset -U path PATH
path=(
    $HOME/.cargo/bin(N)
    $HOME/.local/bin(N)  # uv tool
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
