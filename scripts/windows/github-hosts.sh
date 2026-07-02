#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v pwsh &> /dev/null; then
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/github-hosts.ps1"
else
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/github-hosts.ps1"
fi
