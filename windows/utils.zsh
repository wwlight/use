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

# 添加清理历史记录的函数
function history_clean() {
    # 创建临时文件
    local tmp=$(mktemp)

    # Windows 上没有 tail -r，使用 awk 逆序读取
    awk '
    {
        # 保存所有行
        lines[NR] = $0;
    }
    END {
        # 反向处理每一行
        for (i = NR; i >= 1; i--) {
            line = lines[i];
            if (index(line, ";") > 0) {
                # 命令部分是分号后面的内容
                cmd = substr(line, index(line, ";") + 1);
                if (!seen[cmd]++) {
                    # 第一次遇到这个命令（因为是反向处理的，所以是最新的）
                    result[++count] = line;
                }
            } else {
                # 处理没有分号的行（可能是没有时间戳的记录）
                if (!seen[line]++) {
                    result[++count] = line;
                }
            }
        }

        # 恢复原来的顺序（再次反转）
        for (i = count; i > 0; i--) {
            print result[i];
        }
    }' $HISTFILE > $tmp

    # 确保处理成功后再替换原文件
    if [ -s "$tmp" ]; then
        cp $HISTFILE "$HISTFILE.bak"  # 创建备份
        mv $tmp $HISTFILE
        echo "历史记录已去重，保留了最新的命令记录"
    else
        echo "处理出错，历史记录未修改"
        rm $tmp
    fi
}
