function cdl() {
    local dir
    dir="$(zoxide query -l | fzf --reverse --height 40% \
        --preview 'eza -l --icons {}' \
        --preview-window=right:60%)" && cd "${dir}"
}

function cdd() {
    local dir
    dir="$(find . -type d 2>/dev/null | fzf --reverse --height 40% \
        --preview 'eza -l --icons {}' \
        --preview-window=right:60%)" && cd "${dir}"
}

function _clone() {
    local repo=$1 custom_dir=$2 base_dir=$3 default_user=$4

    if [[ "$repo" == git@* ]]; then
        local repo_name=$(basename "${repo#*:}" .git)
    elif [[ "$repo" == http* ]]; then
        local repo_name=$(basename "$repo" .git)
    else
        repo="https://github.com/${default_user:+$default_user/}${repo%.git}.git"
        local repo_name=$(basename "$repo" .git)
    fi

    [[ -n "$custom_dir" ]] && repo_name="$custom_dir"

    local target_dir="$base_dir/$repo_name" counter=1
    while [[ -d "$target_dir" ]]; do
        target_dir="$base_dir/${repo_name}_$((counter++))"
    done

    [[ $counter -gt 1 ]] && echo "注意：原目录名已存在，将克隆到: $target_dir"

    mkdir -p "$base_dir" || { echo "无法创建目录: $base_dir"; return 1; }

    echo "正在克隆到: $target_dir"
    if git clone "$repo" "$target_dir"; then
        echo "✅ 成功克隆到: $target_dir"
    else
        echo "克隆仓库失败: $repo"
        if [[ -d "$target_dir" ]]; then
            echo "正在移除不完整的克隆目录: $target_dir"
            rm -rf "$target_dir" && echo "已移除" || echo "移除失败，请手动检查: $target_dir"
        fi
        return 1
    fi
}

function cloneo() {
    if [[ $# -eq 0 ]]; then
        echo "用法: cloneo <仓库地址> [自定义目录名]"; return 1
    fi
    _clone "$1" "$2" "$HOME/open-source" ""
}

function cloned() {
    if [[ $# -eq 0 ]]; then
        echo "用法: cloned <仓库地址> [自定义目录名]"; return 1
    fi
    _clone "$1" "$2" "$HOME/dev-code" "wwlight"
}

# 清理历史记录：去重 + 剔除错误/简单的命令
function history_clean() {
    local tmp=$(mktemp)

    grep -v $'\ufffd' $HISTFILE | tail -r | awk '
    function is_bad(cmd) {
        if (length(cmd) <= 1) return 1
        if (cmd ~ /^(cat|node|python|python3|bash|cargo|rustc|uv|clear)$/) return 1
        if (cmd ~ /^(corepack|yarn|pnpm|fnm|ni|nr)([ \t].*)?$/) return 1
        if (cmd ~ /^history [0-9]+$/) return 1
        if (cmd ~ /^cd [0-9]+\/?$/) return 1
        if (cmd ~ /^git commit -(m|a) ["'\''\x60][0-9]+["'\''\x60]$/) return 1
        if (cmd ~ /^git commit -m \${\w+}$/) return 1
        return 0
    }
    {
        if (is_bad($0)) next
        if ($0 ~ /^: [0-9]+:[0-9]+;/) next
        if (!seen[$0]++) result[++count] = $0
    } END {
        for (i = count; i > 0; i--) print result[i]
    }' > $tmp

    if [ -s "$tmp" ]; then
        mv $tmp $HISTFILE
        echo "History cleaned: deduped, removed trivial/wrong commands"
    else
        echo "Error: output empty, history not modified"
        rm $tmp
    fi
}
