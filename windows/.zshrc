#!/bin/zsh
# ~/.zshrc

# ======================
# 环境变量设置
# ======================
export ZSH=$HOME/.zsh
export ZSH_COMPDUMP=$ZSH/cache/.zcompdump-$HOST
export HISTFILE=$ZSH/.zsh_history
export HISTSIZE=5000
export SAVEHIST=4000
export STARSHIP_CONFIG=$HOME/.config/starship/starship.toml
# 更安全的 PATH 设置
typeset -U path PATH  # 确保 PATH 唯一性
path=(
    $HOME/.npm_global
    $path
)

# ======================
# 历史记录配置
# ======================
setopt appendhistory            # 追加而非覆盖历史文件
setopt incappendhistory         # 实时写入历史记录
unsetopt extendedhistory        # 不记录时间戳和持续时间
setopt histignorealldups        # 完全去重历史记录
setopt histignorespace          # 忽略空格开头的命令
setopt histreduceblanks         # 删除多余空白字符
setopt histverify               # 执行前确认历史命令
setopt histexpiredupsfirst      # 淘汰重复命令优先
setopt histsavenodups           # 保存时删除重复项
setopt histfindnodups           # 搜索时不显示重复项
unsetopt sharehistory           # 禁用共享历史记录

# ======================
# 插件配置
# ======================
# 插件列表 (按需加载)
plugins=(
    fast-syntax-highlighting
    zsh-autosuggestions
    zsh-hist
    incr
)

# 加载插件
for plugin ($plugins); do
    plugin_path=$ZSH/plugins/$plugin/$plugin.plugin.zsh
    [ -f $plugin_path ] && source $plugin_path || \
    source $ZSH/plugins/$plugin/$plugin.zsh
done

# zsh-hist 插件配置
zstyle ':hist:*' expand-aliases yes
zstyle ':hist:*' ignore-dups yes    # 启用插件内部去重
zstyle ':hist:*' ignore-space yes   # 忽略空格开头的命令

# 自动建议配置
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_USE_ASYNC=1      # 启用异步加载

# 补全功能
fpath=($ZSH/plugins/zsh-completions/src $fpath)
# 延迟加载补全系统
autoload -Uz compinit
if [[ -n ${ZSH_COMPDUMP} ]]; then
    compinit -i -d "${ZSH_COMPDUMP}"
else
    compinit -i
fi

# ======================
# 工具初始化
# ======================
# fnm
eval "$(fnm env --use-on-cd)"

# zoxide
eval "$(zoxide init zsh --cmd cd)"
function cdl() {
    local dir
    dir="$(zoxide query -l | fzf --reverse --height 40% \
        --preview 'ls -l {}' \
        --preview-window=right:60%)" && cd "${dir}"
}
function cdd() {
    local dir
    dir="$(find . -type d 2>/dev/null | fzf --reverse --height 40% \
        --preview 'ls -l {}' \
        --preview-window=right:60%)" && cd "${dir}"
}

# starship
eval "$(starship init zsh)"
function set_win_title(){
    echo -ne "\033]0; $(basename "$USER") \007"
}
starship_precmd_user_func="set_win_title"
precmd_functions+=(set_win_title)

# uv python 版本管理工具
eval "$(uv generate-shell-completion zsh)"
eval "$(uvx --generate-shell-completion zsh)"

# fzf
source <(fzf --zsh)

# ======================
# 别名设置
# ======================
alias cls="clear"
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'

alias nio="ni --prefer-offline"
alias s="nr start"
alias d="nr dev"
alias b="nr build"

alias gp='git push'
alias gl='git pull'
alias grt='cd "$(git rev-parse --show-toplevel)"'
alias gc='git branch | fzf | xargs git checkout' # 搜索 git 分支并切换

alias ping="gping"
alias t='tldr' # tldr 命令
alias of="onefetch"
# end
