# ~/.bashrc
eval "$(starship init bash)"

eval "$(fzf --bash)"

eval "$(zoxide init bash --cmd cd)"
. "$HOME/.cargo/env"
