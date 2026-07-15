# ~/.bashrc
eval "$(starship init bash)"

eval "$(fzf --bash)"

eval "$(zoxide init bash --cmd cd)"

. "$HOME/.cargo/env"

# vite+ 环境初始化
[[ -r $HOME/.vite-plus/env ]] && . "$HOME/.vite-plus/env"
