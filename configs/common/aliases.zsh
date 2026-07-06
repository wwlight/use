# eza
alias ls='eza --icons'
alias l='eza -l --icons'
alias la='eza -la --icons'
alias lt='eza --tree --icons'

# vp (vite+)
alias v="vp"
alias vc="v create"
alias vr="v run"
alias s="vr start"
alias d="vr dev"
alias b="vr build"

# git
alias gp='git push'
alias gl='git pull'
alias grt='cd "$(git rev-parse --show-toplevel)"'
alias gc='git branch | fzf | xargs git checkout'

# 其它
alias cls="clear"
alias reload='source "$HOME/.zshenv" 2>/dev/null; source "${ZDOTDIR:-$HOME/.zsh}/.zshrc"'
alias ping="gping"
alias of="onefetch"
alias oc="opencode"
