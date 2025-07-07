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

# 添加清理历史记录的函数
function history_clean() {
    # 创建临时文件
    local tmp=$(mktemp)

    # 使用 tail -r 反向读取历史文件，然后用 awk 处理
    cat $HISTFILE | tail -r | awk '
    {
        if (index($0, ";") > 0) {
            # 命令部分是分号后面的内容
            cmd = substr($0, index($0, ";") + 1);
            if (!seen[cmd]++) {
                # 第一次遇到这个命令（因为文件是反向读取的，所以是最新的）
                result[++count] = $0;
            }
        } else {
            # 处理没有分号的行（可能是没有时间戳的记录）
            if (!seen[$0]++) {
                result[++count] = $0;
            }
        }
    } END {
        # 恢复原来的顺序
        for (i = count; i > 0; i--) {
            print result[i];
        }
    }' > $tmp

    # 确保处理成功后再替换原文件
    if [ -s "$tmp" ]; then
        mv $tmp $HISTFILE
        echo "历史记录已去重，保留了最新的命令记录"
    else
        echo "处理出错，历史记录未修改"
        rm $tmp
    fi
}
