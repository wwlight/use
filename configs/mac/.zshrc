#!/bin/zsh
# ~/.zshrc

# ======================
# 环境变量设置
# ======================
export ZSH=$HOME/.zsh
export ZSH_COMPDUMP=$ZSH/cache/.zcompdump-$HOST
export STARSHIP_CONFIG=$HOME/.config/starship/starship.toml
export SDKMAN_DIR=$(brew --prefix sdkman-cli)/libexec
export EZA_CONFIG_DIR=$HOME/.config/eza

# PATH 设置 (N == Null Glob)
typeset -U path PATH
path=(
    $HOME/.npm_global/bin(N)
    $path
)

# ======================
# zsh 基础选项设置
# ======================
# 历史记录选项
export HISTFILE=$ZSH/.zsh_history
export HISTSIZE=5000
export SAVEHIST=4000

# ======================
# 历史记录配置
# ======================
setopt append_history           # 追加写入（非覆盖）
setopt inc_append_history       # 实时增量写入
setopt hist_ignore_all_dups     # 忽略所有重复命令
setopt hist_expire_dups_first   # 淘汰重复记录优先
setopt hist_save_no_dups        # 保存时删除重复项
setopt hist_find_no_dups        # 搜索时不显示重复项
setopt hist_reduce_blanks       # 压缩多余空格
setopt hist_ignore_space        # 忽略空格开头的命令
setopt hist_verify              # 执行前确认历史命令
unsetopt extended_history       # 不记录时间戳和持续时间
unsetopt share_history          # 禁用会话间共享历史
# 其它
setopt auto_cd                  # 输入目录名自动cd
setopt correct                  # 命令纠错
setopt complete_in_word         # 在单词中间也能补全
setopt always_to_end            # 补全后光标移到末尾

# ======================
# 补全系统初始化
# ======================
# 设置 fpath
fpath=(
    $ZSH/plugins/zsh-completions/src
    $ZSH/zfunc
    $fpath
)
# 加载自定义函数
autoload -Uz $ZSH/zfunc/*(:t)
# 初始化补全系统
autoload -Uz compinit
if [[ -n $ZSH_COMPDUMP(#qN.mh+24) ]]; then
    compinit -C -d $ZSH_COMPDUMP
else
    compinit -i -d $ZSH_COMPDUMP
fi
# 补全样式设置
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# ======================
# 插件配置
# ======================
plugins=(
    fast-syntax-highlighting
    zsh-autosuggestions
)

for plugin ($plugins); do
    plugin_path=$ZSH/plugins/$plugin/$plugin.plugin.zsh
    [ -f $plugin_path ] && source $plugin_path || \
    source $ZSH/plugins/$plugin/$plugin.zsh
done

# 插件配置
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_USE_ASYNC=1
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#53555c"

# ======================
# 工具初始化
# ======================
# Node.js 版本管理 (fnm)
eval "$(fnm env --use-on-cd --shell zsh)"

# 模糊搜索 (fzf)
source <(fzf --zsh)

# 智能目录跳转 (zoxide)
eval "$(zoxide init zsh --cmd cd)"

# Python 包管理器和虚拟环境工具 (uv)
eval "$(uv generate-shell-completion zsh)"
eval "$(uvx --generate-shell-completion zsh)"

# sdkman sdk 版本管理工具
[[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]] && source "${SDKMAN_DIR}/bin/sdkman-init.sh"

# starship
eval "$(starship init zsh)"
function set_win_title(){
    echo -ne "\033]0; $(basename "$USER") \007"
}
starship_precmd_user_func="set_win_title"
precmd_functions+=(set_win_title)

# ======================
# 别名设置
# ======================
alias cls="clear"
alias reload="source ~/.zshrc"
alias ls='eza --icons'
alias l='eza -l --icons'
alias la='eza -la --icons'
alias lt='eza --tree --icons'
# @antfu/ni 别名
alias nio="ni --prefer-offline"
alias s="nr start"
alias d="nr dev"
alias b="nr build"
# Git 别名
alias gp='git push'
alias gl='git pull'
alias grt='cd "$(git rev-parse --show-toplevel)"'
alias gc='git branch | fzf | xargs git checkout' # 搜索 git 分支并切换
# 其它
alias ping="gping"
alias of="onefetch"
alias oc="opencode"

# ======================
# 自定义函数加载
# ======================
CUSTOM_FUNCTIONS_DIR="$ZSH/functions"
if [[ -d "$CUSTOM_FUNCTIONS_DIR" ]]; then
    for func_file in "$CUSTOM_FUNCTIONS_DIR"/*.zsh; do
        if [[ -r "$func_file" ]]; then
            source "$func_file"
        fi
    done
fi
# end
