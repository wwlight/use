# ~/.bashrc
eval "$(starship init bash)"

eval "$(fnm env --use-on-cd --shell bash)"

eval "$(fzf --bash)"

eval "$(zoxide init bash --cmd cd)"
. "$HOME/.cargo/env"
