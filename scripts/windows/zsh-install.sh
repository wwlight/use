#!/bin/bash
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS_CMD="powershell.exe"
command -v pwsh.exe &>/dev/null && PS_CMD="pwsh.exe"
exec "$PS_CMD" -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_PATH/zsh-install.ps1" "$@"
