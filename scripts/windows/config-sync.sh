#!/bin/bash

# 引入公共函数库
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# 检查是否在 Windows 环境运行
check_target_system "Windows"

# =========================
# 主脚本开始
# =========================

# 默认不自动选择
direction=""

# 检查是否有参数
if [ "$1" = "1" ] || [ "$1" = "2" ]; then
    direction=$1
else
    echo "请选择拷贝方向:"
    echo "1) 从本地目录拷贝到 windows 目录"
    echo "2) 从 windows 目录拷贝到本地目录"
    read -r direction
fi

case $direction in
    1)
        # 本地目录 -> windows 目录
        cp -v ~/.zshrc "$PROJECT_ROOT/configs/windows/.zshrc"
        cp -v ~/.bashrc "$PROJECT_ROOT/configs/windows/.bashrc"
        cp -v ~/.zsh/functions/utils.zsh "$PROJECT_ROOT/configs/windows/utils.zsh"
        cp -v ~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1 "$PROJECT_ROOT/configs/windows/pwsh5_profile.ps1"
        cp -v ~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1 "$PROJECT_ROOT/configs/windows/pwsh7_profile.ps1"
        ;;
    2)
        # 备份系统配置文件
        backup_file ~/.zshrc ~/.backup

        # windows 目录 -> 本地目录
        cp -v "$PROJECT_ROOT/configs/windows/.zshrc" ~/.zshrc
        cp -v "$PROJECT_ROOT/configs/windows/.bashrc" ~/.bashrc
        mkdir -p ~/.zsh/functions && cp -v "$PROJECT_ROOT/configs/windows/utils.zsh" ~/.zsh/functions/utils.zsh
        mkdir -p ~/Documents/WindowsPowerShell && cp -v "$PROJECT_ROOT/configs/windows/pwsh5_profile.ps1" ~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1
        mkdir -p ~/Documents/PowerShell && cp -v "$PROJECT_ROOT/configs/windows/pwsh7_profile.ps1" ~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo "操作完成！"
