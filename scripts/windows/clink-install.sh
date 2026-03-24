#!/bin/bash

# 引入公共函数库
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ==============================
# 主安装函数
# ==============================
install_clink_plugins() {
    # 插件配置数组
    declare -A PLUGINS=(
        ["https://github.com/vladimir-kotikov/clink-completions"]="clink-completions"
        ["https://github.com/chrisant996/clink-gizmos"]="clink-gizmos"
    )

    # 1. 检查 scoop 安装
    info "步骤1/4: 检查 scoop 安装..."
    if ! command -v scoop &> /dev/null; then
        error "未检测到 scoop 安装，请先安装 scoop"
    fi
    info "scoop 已安装"

    # 2. 检查/安装 clink
    info "步骤2/4: 检查 clink 安装..."
    if ! command -v clink &> /dev/null; then
        warn "未检测到 clink，正在通过 scoop 安装..."
        scoop install clink || {
            error "clink 安装失败"
        }
        info "clink 安装成功"
    else
        info "clink 已安装"
    fi

    # 获取 clink 路径
    local clink_path=$(scoop prefix clink)
    if [ -z "$clink_path" ] || [ ! -d "$clink_path" ]; then
        error "获取 clink 安装路径失败"
    fi
    local scripts_path="$clink_path\\scripts"
    info "Clink 安装路径: "
    echo "$clink_path"

    # 3. 下载并配置插件
    info "步骤3/4: 处理插件..."
    for repo in "${!PLUGINS[@]}"; do
        plugin_dir="${PLUGINS[$repo]}"
        target_path="$scripts_path\\$plugin_dir"

        if [ ! -d "$target_path" ]; then
            info "正在下载插件: $plugin_dir..."
            git clone "$repo" "$target_path" || {
                warn "$plugin_dir 下载失败，跳过此插件"
                continue
            }
            info "$plugin_dir 下载完成"
        else
            info "插件 $plugin_dir 已存在，跳过下载"
        fi
    done

    # 复制 starship 启动插件，借助 clink 在 cmd 中使用
    info "复制 starship.lua 启动插件..."
    cp -v "$PROJECT_ROOT/configs/windows/starship.lua" "$scripts_path\\starship.lua"

    # 注册插件
    info "注册插件: $scripts_path..."
    clink installscripts "$scripts_path" || {
        warn "$scripts_path 注册失败"
    } && {
        info "$scripts_path 注册成功"
    }
    echo

    # 4. 启用自动运行
    info "步骤4/4: 启用 clink 自动运行..."
    clink set tips.enable false
    clink autorun install -- --quiet || {
        warn "clink 自动运行启用失败"
    }
    info "clink 自动运行已启用"

    info "🎉 所有配置已完成！"
}

# ==============================
# 主执行流程
# ==============================
main() {
    info "===== Clink 插件安装脚本 ====="
    check_target_system "Windows"

    install_clink_plugins
}

# 执行主函数
main
