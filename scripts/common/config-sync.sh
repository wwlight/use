#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

init_manifest common

direction=$(prompt_sync_direction "$1" \
    "示例: npm run common:sync -- 2 或 vpr common:sync 2" \
    "1) 从本地目录拷贝到 common 目录" \
    "2) 从 common 目录拷贝到本地目录") || exit 1

case $direction in
    1)
        while IFS=$'\t' read -r local_path repo_path; do
            mkdir -p "$(dirname "$repo_path")"
            cp -v "$local_path" "$repo_path"
        done < <(manifest_sync_pairs)
        ;;
    2)
        while IFS=$'\t' read -r local_path repo_path; do
            mkdir -p "$(dirname "$local_path")"
            cp -v "$repo_path" "$local_path"
        done < <(manifest_sync_pairs)
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo "操作完成！"
