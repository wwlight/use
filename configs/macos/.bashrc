# ~/.bashrc
eval "$(starship init bash)"

eval "$(fzf --bash)"

eval "$(zoxide init bash --cmd cd)"

. "$HOME/.cargo/env"

# vite+ 环境初始化
[[ -r $HOME/.config/vite-plus/env ]] && . "$HOME/.config/vite-plus/env"
