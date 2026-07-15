# eza
alias ls='eza --icons'
alias l='eza -l --icons'
alias la='eza -la --icons'
alias lt='eza --tree --icons'

# vite+
alias v="vp"
alias vc="vp create"
alias s="vpr start"
alias d="vpr dev"
alias b="vpr build"

# git
alias gp='git push'
alias gl='git pull'
alias grt='cd "$(git rev-parse --show-toplevel)"'
alias gc='git branch | fzf | xargs git checkout'

# 其它
alias cls="clear"
alias reload='source ~/.zshrc'
alias of="onefetch"
alias oc="opencode"
alias t="tldr"
