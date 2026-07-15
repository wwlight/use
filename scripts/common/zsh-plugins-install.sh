#!/bin/bash
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

init_manifest common

info '正在安装 zsh 插件...'
plugins_json=$(manifest_get "zshPlugins")
plugins_dir=$(expand_path "~/.zsh/plugins")
mkdir -p "$plugins_dir"

node -e "
    const plugins = JSON.parse(process.argv[1]);
    for (const plugin of plugins) {
        process.stdout.write(plugin.repo + '\t' + plugin.name + '\n');
    }
" "$plugins_json" | while IFS=$'\t' read -r repo plugin_name; do
    target_dir="$plugins_dir/$plugin_name"

    if [ ! -d "$target_dir" ]; then
        info "正在下载插件: $plugin_name..."
        git clone "$repo" "$target_dir" || {
            warn "$plugin_name 下载失败，跳过此插件"
            continue
        }
        info "$plugin_name 下载完成"
    else
        info "插件 $plugin_name 已存在，跳过"
    fi
done
