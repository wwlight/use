#!/bin/bash
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

init_manifest common

UPDATE_MODE=0
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --update) UPDATE_MODE=1; shift ;;
        --) shift; break ;;
        *) error "未知参数: $1（支持 --update）" ;;
    esac
done

normalize_repo_url() {
    local u="${1%.git}"
    u="${u%/}"
    u="${u#https://}"
    u="${u#http://}"
    u="${u#ssh://git@}"
    u="${u#git@}"
    u="${u/://}"
    printf '%s' "$u"
}

is_same_remote_repo() {
    local dir="$1"
    local expected="$2"
    [ -d "$dir/.git" ] || return 1
    local remote
    remote=$(git -C "$dir" remote get-url origin 2>/dev/null) || return 1
    [ "$(normalize_repo_url "$remote")" = "$(normalize_repo_url "$expected")" ]
}

update_repo_to_latest() {
    local dir="$1"
    git -C "$dir" fetch --prune origin || return 1

    local branch
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
    if [ "$branch" = "HEAD" ]; then
        branch=$(git -C "$dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
        branch="${branch#origin/}"
        [ -n "$branch" ] || return 1
    fi

    git -C "$dir" reset --hard "origin/$branch"
}

clone_plugin() {
    local repo="$1"
    local target_dir="$2"
    local plugin_name="$3"

    info "正在下载插件: $plugin_name..."
    git clone "$repo" "$target_dir" || {
        warn "$plugin_name 下载失败，跳过此插件"
        return 1
    }
    info "$plugin_name 下载完成"
}

sync_existing_plugin() {
    local repo="$1"
    local target_dir="$2"
    local plugin_name="$3"

    if is_same_remote_repo "$target_dir" "$repo"; then
        info "插件 $plugin_name 已是线上仓库，正在拉取最新..."
        if update_repo_to_latest "$target_dir"; then
            info "$plugin_name 已更新到最新"
        else
            warn "$plugin_name 拉取最新失败，跳过此插件"
        fi
        return
    fi

    info "插件 $plugin_name 同名但非目标仓库，正在删除并重新克隆..."
    rm -rf "$target_dir"
    clone_plugin "$repo" "$target_dir" "$plugin_name"
}

info '正在安装 zsh 插件...'
plugins_json=$(manifest_get "zshPlugins")
plugins_dir=$(expand_path "~/.zsh/plugins")
mkdir -p "$plugins_dir"

while IFS=$'\t' read -r repo plugin_name; do
    [ -n "$plugin_name" ] || continue
    target_dir="$plugins_dir/$plugin_name"

    if [ ! -d "$target_dir" ]; then
        clone_plugin "$repo" "$target_dir" "$plugin_name"
        continue
    fi

    if [ "$UPDATE_MODE" -eq 1 ]; then
        sync_existing_plugin "$repo" "$target_dir" "$plugin_name"
    else
        info "插件 $plugin_name 已存在，跳过"
    fi
done < <(node -e "
    const plugins = JSON.parse(process.argv[1]);
    for (const plugin of plugins) {
        process.stdout.write(plugin.repo + '\t' + plugin.name + '\n');
    }
" "$plugins_json")
