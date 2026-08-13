# git
alias gp='git push'
alias gl='git pull'
alias grt='cd "$(git rev-parse --show-toplevel)"'
alias gc='git branch | fzf | xargs git checkout'

# vite+
alias v="vp"
alias vc="vp create"
alias s="vpr start"
alias d="vpr dev"
alias b="vpr build"

# eza
alias l='eza -l --icons'
alias la='eza -la --icons'
alias ls='eza --icons'
alias lt='eza --tree --icons'

# tldr
alias t="tldr"
alias tt="tldr -L en"

# Other
alias cls="clear"
alias reload='source ~/.zshrc'
alias of="onefetch"
alias oc="opencode"
