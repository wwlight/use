# 个人配置

## 一键安装

### mac · 交互选择

```sh
curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash
```

### mac · lite

```sh
curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash -s -- lite
```

### mac · full

```sh
curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash -s -- full
```

### windows · 执行策略

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### windows · 交互选择

```powershell
irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

### windows · lite

```powershell
$env:USE_PROFILE='lite'; irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

### windows · full

```powershell
$env:USE_PROFILE='full'; irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```


## 安装 [vite.plus](http://vite.plus)

```sh
# mac
curl -fsSL https://vite.plus | bash

# windows
irm https://vite.plus/ps1 | iex
```

## 通用命令

由 [scripts/_dispatch.mjs](./scripts/_dispatch.mjs) 按系统分发（mac → Homebrew，windows → Scoop）。

```sh
vpr pm            # 安装包管理器（mac: brew / win: scoop）
vpr pm -- ustc    # mac 镜像：official | ustc | tuna
vpr init          # 初始化（交互选择 lite/full）
vpr init -- lite  # 尝鲜版（mac: Brewfile.lite；win: scoop_backup.lite.json）
vpr init -- full  # 完整版
vpr backup        # 备份已装软件到仓库（win 同时更新尝鲜版）
vpr setup         # 从仓库恢复完整软件清单
vpr sync          # 交互选择同步方向
vpr sync 1        # 本地配置 → 仓库
vpr sync 2        # 仓库 → 本地配置
vpr zsh-plugin    # 安装/更新 zsh 插件（强制同步最新）
```

> [!WARNING]
> zip 下载解压后需先解除脚本封锁（git clone 可跳过）

```powershell
Get-ChildItem scripts,configs -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

## mac

```sh
vpr pm            # 官方源（默认）
vpr pm -- ustc    # 中科大镜像
vpr pm -- tuna    # 清华镜像
vpr init          # 初始化（需先装 brew；交互选择）
vpr init -- lite  # 尝鲜版
```

```text
configs/mac/
|-- Brewfile        # Homebrew 应用备份
|-- Brewfile.lite   # 尝鲜版最小依赖
|-- .zshrc          # zsh 平台配置
|-- .bashrc         # bash 配置
|-- utils.zsh       # zsh 自定义函数
`-- ghostty_config  # Ghostty 终端配置 → ~/.config/ghostty/config
```

## windows

```sh
vpr hosts         # 更新 GitHub hosts（需管理员）
vpr pm            # 安装 scoop
vpr init          # 初始化（需先装 scoop；交互选择）
vpr init -- lite  # 尝鲜版
```

### windows 专属命令

```sh
vpr zsh           # 安装 zsh 到 git（已装时可选择是否装插件）
vpr zsh-plugin    # 安装/更新 zsh 插件
vpr git-setup     # Git 全局配置
vpr git-extras    # 安装 git-extras
vpr clink         # 安装 clink 插件（cmd 扩展）
vpr hosts         # 更新 GitHub hosts（需管理员）
```

```text
configs/windows/
|-- scoop_backup.json       # Scoop 应用备份
|-- scoop_backup.lite.json  # 尝鲜版最小依赖
|-- .zshrc                  # zsh 平台配置
|-- .bashrc                 # bash 配置
|-- utils.zsh               # 自定义函数
|-- aliases.zsh             # windows 专属别名 → ~/.zsh/functions/aliases.win.zsh
|-- pwsh5_profile.ps1       # Windows PowerShell 5 profile
|-- pwsh7_profile.ps1       # PowerShell 7 profile
|-- services-manifest.json  # scoop services 服务注册配置
|-- scoop_services.zsh      # 扩展 scoop services（WinSW）；zsh → ~/.zsh/functions/，PowerShell 见 profile
`-- starship.lua            # cmd 下 clink + starship
```

### scoop services

需先 `scoop install winsw-pre`，并配置 `services-manifest.json`。

```sh
scoop services help
scoop services ls               # 列出已管理服务
scoop services install nginx    # 注册并启动
scoop services uninstall nginx  # 注销服务
scoop services start nginx      # 启动
scoop services stop nginx       # 停止
scoop services restart nginx    # 重启
scoop uninstall nginx           # 自动注销服务后卸载
```

### clink

```sh
clink info
clink autorun install -- --quiet  # 启用自动运行
clink autorun uninstall           # 禁用自动运行
clink inject                      # 临时运行
scoop hold clink                  # 禁止更新
```

## common 配置

```text
configs/common/
|-- .zshrc_core     # mac / windows 公共核心 zsh → ~/.zsh/.zshrc_core
|-- aliases.zsh     # 公共别名 → ~/.zsh/functions/aliases.zsh
|-- _eza            # eza 补全
|-- starship.toml   # starship 配置
|-- opencode.jsonc  # OpenCode 配置 → ~/.config/opencode/opencode.jsonc
`-- mihomo.yaml     # Mihomo 配置
```
