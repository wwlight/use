# ~/.bashrc
eval "$(starship init bash)"

eval "$(fzf --bash)"

eval "$(zoxide init bash --cmd cd)"

. "$HOME/.cargo/env"

# Vite+ bin (https://viteplus.dev)
. "$HOME/.vite-plus/env"
