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

# 克隆到 "$HOME/open-source"
function cloneo() {
    # 参数检查
    if [ $# -eq 0 ]; then
        echo "错误：未提供仓库地址参数"
        echo "用法: cloned <仓库地址> 或 cloned <用户名/仓库名>"
        echo "支持格式:"
        echo "  - HTTPS: https://github.com/user/repo.git"
        echo "  - SSH: git@github.com:user/repo.git"
        echo "  - 简写: user/repo"
        return 1
    fi

    local repo="$1"
    local custom_dir="$2"
    local base_dir="$HOME/open-source"
    local repo_name
    local target_dir

    # 地址类型判断和转换
    if [[ "$repo" == git@* ]]; then
        # SSH地址处理
        repo_name=$(basename "${repo#*:}" .git)
    elif [[ "$repo" == http* ]]; then
        # HTTPS地址处理
        repo_name=$(basename "$repo" .git)
    else
        # 简写格式处理 (user/repo)
        repo="https://github.com/${repo%.git}.git"
        repo_name=$(basename "$repo" .git)
    fi

    # 使用自定义目录名（如果提供了第二个参数）
    if [ -n "$custom_dir" ]; then
        repo_name="$custom_dir"
    fi

    target_dir="$base_dir/$repo_name"
    local counter=1

    # 自动处理重名目录
    while [ -d "$target_dir" ]; do
        target_dir="$base_dir/${repo_name}_$counter"
        ((counter++))
    done

    if [ $counter -gt 1 ]; then
        echo "注意：原目录名已存在，将克隆到: $target_dir"
    fi

    # 创建父目录（如果不存在）
    mkdir -p "$base_dir" || {
        echo "无法创建目录: $base_dir"
        return 1
    }

    # 执行克隆
    echo "正在克隆到: $target_dir"
    git clone "$repo" "$target_dir" || {
        echo "克隆仓库失败: $repo"

        if [ -d "$target_dir" ]; then
            echo "正在移除不完整的克隆目录: $target_dir"

            # 尝试解除占用
            if lsof +D "$target_dir" &>/dev/null; then
                echo "检测到目录被占用，正在尝试解除..."
                lsof +D "$target_dir" | awk 'NR>1 {print $2}' | xargs kill -9
            fi

            # 重试删除
            sleep 1  # 稍等片刻
            rm -rf "$target_dir" && echo "已移除" || {
                echo "移除失败，请手动检查: $target_dir"
                echo "可能原因: 文件被锁定或无权限"
            }
        fi

        return 1
    }

    echo "✅ 成功克隆到: $target_dir"
}

# 克隆到 "$HOME/dev-code"
function cloned() {
    # 参数检查
    if [ $# -eq 0 ]; then
        echo "错误：未提供仓库地址参数"
        echo "用法: cloned <仓库地址> 或 cloned <仓库名>"
        echo "支持格式:"
        echo "  - HTTPS: https://github.com/user/repo.git"
        echo "  - SSH: git@github.com:user/repo.git"
        echo "  - 简写: user/repo"
        return 1
    fi

    local repo="$1"
    local custom_dir="$2"
    local base_dir="$HOME/dev-code"
    local repo_name
    local target_dir

    # 地址类型判断和转换
    if [[ "$repo" == git@* ]]; then
        # SSH地址处理
        repo_name=$(basename "${repo#*:}" .git)
    elif [[ "$repo" == http* ]]; then
        # HTTPS地址处理
        repo_name=$(basename "$repo" .git)
    else
        # 简写格式处理 (user/repo)
        repo="https://github.com/wwlight/${repo%.git}.git"
        repo_name=$(basename "$repo" .git)
    fi

    # 使用自定义目录名（如果提供了第二个参数）
    if [ -n "$custom_dir" ]; then
        repo_name="$custom_dir"
    fi

    target_dir="$base_dir/$repo_name"
    local counter=1

    # 自动处理重名目录
    while [ -d "$target_dir" ]; do
        target_dir="$base_dir/${repo_name}_$counter"
        ((counter++))
    done

    if [ $counter -gt 1 ]; then
        echo "注意：原目录名已存在，将克隆到: $target_dir"
    fi

    # 创建父目录（如果不存在）
    mkdir -p "$base_dir" || {
        echo "无法创建目录: $base_dir"
        return 1
    }

    # 执行克隆
    echo "正在克隆到: $target_dir"
    git clone "$repo" "$target_dir" || {
        echo "克隆仓库失败: $repo"

        if [ -d "$target_dir" ]; then
            echo "正在移除不完整的克隆目录: $target_dir"

            # 尝试解除占用
            if lsof +D "$target_dir" &>/dev/null; then
                echo "检测到目录被占用，正在尝试解除..."
                lsof +D "$target_dir" | awk 'NR>1 {print $2}' | xargs kill -9
            fi

            # 重试删除
            sleep 1  # 稍等片刻
            rm -rf "$target_dir" && echo "已移除" || {
                echo "移除失败，请手动检查: $target_dir"
                echo "可能原因: 文件被锁定或无权限"
            }
        fi

        return 1
    }

    echo "✅ 成功克隆到: $target_dir"
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
