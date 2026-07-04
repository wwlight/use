#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

direction=$(prompt_sync_direction "$1" \
    "示例: vpr sync 2" \
    "1) 备份本地配置 -> 仓库" \
    "2) 从仓库恢复配置 -> 本地") || exit 1

echo "$direction"
