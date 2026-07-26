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

info '正在安装 zsh 插件...'
plugins_json=$(manifest_get "zshPlugins")
plugins_dir=$(expand_path "$(node "$SCRIPT_DIR/lib/manifest-config.mjs" zsh-plugins-dir)")
mkdir -p "$plugins_dir"

while IFS=$'\t' read -r repo plugin_name; do
    [ -n "$plugin_name" ] || continue
    sync_git_repo_plugin "$repo" "$plugins_dir/$plugin_name" "$plugin_name" "$UPDATE_MODE"
done < <(node -e "
    const plugins = JSON.parse(process.argv[1]);
    for (const plugin of plugins) {
        process.stdout.write(plugin.repo + '\t' + plugin.name + '\n');
    }
" "$plugins_json")
