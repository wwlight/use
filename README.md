# 个人配置

<!-- BEGIN GENERATED GITHUB ACCEL DOCS -->
使用需要 Node.js 环境。

## 前置：安装 [vite.plus](https://viteplus.dev/)

### macos

```sh
curl -fsSL https://vite.plus | bash
```

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli/install.sh | bash
```

```sh
curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli/install.sh | bash
```

### windows

```powershell
irm https://vite.plus/ps1 | iex
```

```powershell
irm https://gh-proxy.com/https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli/install.ps1 | iex
```

```powershell
irm https://ghproxy.net/https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli/install.ps1 | iex
```


## 一键安装

### macos · 交互选择

```sh
curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash
```

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghproxy bash
```

```sh
curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghproxy-net bash
```

### macos · 尝鲜版

```sh
curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash -s -- lite
```

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghproxy bash -s -- lite
```

```sh
curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghproxy-net bash -s -- lite
```

### macos · 完整版

```sh
curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash -s -- full
```

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghproxy bash -s -- full
```

```sh
curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghproxy-net bash -s -- full
```

### windows · 执行策略

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### windows · 交互选择

```powershell
irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

```powershell
$env:USE_ACCEL='ghproxy'; irm https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

```powershell
$env:USE_ACCEL='ghproxy-net'; irm https://ghproxy.net/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

### windows · 尝鲜版

```powershell
$env:USE_PROFILE='lite'; irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

```powershell
$env:USE_PROFILE='lite'; $env:USE_ACCEL='ghproxy'; irm https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

```powershell
$env:USE_PROFILE='lite'; $env:USE_ACCEL='ghproxy-net'; irm https://ghproxy.net/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

### windows · 完整版

```powershell
$env:USE_PROFILE='full'; irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

```powershell
$env:USE_PROFILE='full'; $env:USE_ACCEL='ghproxy'; irm https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

```powershell
$env:USE_PROFILE='full'; $env:USE_ACCEL='ghproxy-net'; irm https://ghproxy.net/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```
<!-- END GENERATED GITHUB ACCEL DOCS -->

## 通用命令

```sh
vpr pm                            # 安装包管理器（brew / scoop），交互选镜像
vpr init                          # 初始化
vpr init -- lite                  # 尝鲜版
vpr init -- full                  # 完整版
vpr backup                        # 备份已装软件到仓库
vpr setup                         # 从仓库恢复完整软件清单
vpr sync                          # 交互选择同步方向
vpr sync backup                   # 备份配置 → 仓库
vpr sync restore                  # 恢复配置 → 本地
vpr zsh-plugin                    # 安装/更新 zsh 插件
vpr git-setup                     # Git 全局配置
```

### 其他命令

> [!NOTE]
> `vpr generate` 只更新仓库内派生文件；运行时文件需再执行 `vpr sync restore`（或 `vpr pm`）部署到本地

```sh
vpr generate                      # 交互选择要生成的产物（改 manifest 后执行）
vpr generate all                  # 生成全部产物
vpr generate github-accel         # 更新 GitHub 加速配置与 README
vpr generate brew-mirror          # 更新 Homebrew 镜像目录 mirrors.tsv
vpr test                          # 运行项目检查
```

> [!TIP]
> zip 下载解压后需先解除脚本封锁

```powershell
Get-ChildItem runtime,configs -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

## 目录结构

`src/`：Node 可移植业务（CLI / sync / brew pm 编排）。
`runtime/`：部署到本机、或必须原生壳执行的 brew/scoop 运行时（Scoop 安装与 download hook 在此）。

```text
.
├── install.sh / install.ps1      # 一键安装（拉仓库 → Node CLI）
├── package.json                  # vpr / npm → src/cli.js
├── manifests/                    # SSOT：镜像、Brewfile/Scoop 备份路径、sync 清单
│   ├── common.json
│   ├── macos.json
│   └── windows.json
├── configs/                      # 用户配置（vpr sync 源）
│   ├── common/                   # 跨平台公共配置
│   ├── macos/                    # macOS + brew 备份 / mirrors.tsv
│   └── windows/                  # Windows + scoop 备份 / shell 扩展
├── runtime/                      # 原生壳 / 本机载荷（非可移植业务）
│   ├── brew/
│   │   ├── mirror-cli.zsh        # → ~/.config/homebrew/mirror-cli.zsh
│   │   ├── mirror-menu.js        # → ~/.config/homebrew/lib/mirror-menu.js
│   │   └── mirror.test.mjs
│   └── scoop/                    # → ~/.config/scoop/（本机载荷；bootstrap/ 仅仓库内）
│       ├── scoop.ps1             # 与 scoop.zsh 成对：mirror / services / winsw
│       ├── contract.test.mjs     # scoop.ps1 ↔ bootstrap 契约测试
│       ├── mirror/               # cli / hook / shared
│       ├── services/             # cli.ps1 + manifest
│       └── bootstrap/            # 安装阶段（不进 src、不部署）
├── src/                          # Node CLI（可移植业务逻辑，仅 JS）
│   ├── cli.js
│   ├── commands/                 # init / backup / setup / sync / generate / git-setup / zsh-plugin / windows-extras
│   ├── core/                     # manifest / paths / platform / args / usage / log / git / spinner / dirs / exec
│   ├── generate/                 # brew-mirror / github-accel
│   ├── lib/                      # ↑↓ 菜单（部署到 brew/scoop lib）
│   ├── pm/
│   │   ├── brew/                 # macOS：编排（JS）
│   │   ├── scoop/                # Windows：编排（JS；调用 runtime/scoop/bootstrap）
│   │   └── restore.js
│   └── sync/                     # 配置同步引擎
└── assets/                       # README 流程图
```

## macos

```sh
vpr pm                            # 安装 brew，交互选镜像
vpr pm -- ustc                    # 中科大镜像
vpr pm -- tuna                    # 清华镜像
vpr pm -- official                # 官方源
vpr init                          # 初始化
vpr init -- lite                  # 尝鲜版（Brewfile.lite）
vpr init -- full                  # 完整版（Brewfile）
vpr backup                        # 导出 Brewfile，并生成 Brewfile.lite
vpr setup                         # 从 Brewfile 恢复完整软件清单
```

初始化后可用独立命令切换镜像（读取本地 `~/.config/homebrew/mirrors.tsv`）：

```sh
brew mirror                       # 交互 ↑↓ 选择（Esc/Ctrl+C 取消；回车选中当前 * 则直接退出）
brew mirror status                # 显示当前镜像
brew mirror ustc                  # 中科大镜像
brew mirror tuna                  # 清华镜像
brew mirror official              # 恢复官方源
```

```text
configs/macos/
├── .bashrc                       # bash 配置
├── .zshrc                        # zsh 平台配置
├── brew/
│   ├── Brewfile                  # Homebrew 应用备份
│   ├── Brewfile.lite             # 尝鲜版（由 Brewfile + brewLiteItems 生成）
│   └── mirrors.tsv               # 镜像目录（由 manifests/macos.json 生成）
├── ghostty_config                # Ghostty 终端配置
└── utils.zsh                     # zsh 自定义函数
```

本机 brew 镜像运行时（由 `vpr pm / sync` 部署）：

```text
~/.config/homebrew/
├── mirrors.tsv                   # 本地镜像目录
├── mirror.zsh                    # 当前镜像环境变量
├── mirror-cli.zsh                # brew mirror 子命令 + brew() wrapper
└── lib/
    ├── mirror-menu.js            # 交互选镜像入口
    ├── menu-select.js            # ↑↓ 菜单（共用）
    ├── string-width.js
    └── tty-term.js
```



## windows

<!-- BEGIN GENERATED GITHUB ACCEL WINDOWS PM -->
```sh
vpr pm                            # 安装 scoop，交互选加速镜像
vpr pm -- ghproxy                 # gh-proxy.com 加速镜像
vpr pm -- ghproxy-net             # ghproxy.net 加速镜像
vpr pm -- official                # 官方源
vpr init                          # 初始化（会启用已选加速）
vpr init -- lite                  # 尝鲜版
vpr init -- full                  # 完整版
```
<!-- END GENERATED GITHUB ACCEL WINDOWS PM -->

> [!NOTE]
> `vpr pm` / `vpr init` 会配置 GitHub URL 镜像与 aria2 多线程下载。

### windows 专属命令

```sh
vpr zsh                           # 安装 zsh 到 git
vpr git-extras                    # 安装 git-extras
vpr clink                         # 安装 clink 插件（cmd 扩展）
```

```text
configs/windows/
├── .bashrc                       # bash 配置
├── .zshrc                        # zsh 平台配置
├── aliases.zsh                   # windows 专属别名
├── pwsh5_profile.ps1             # Windows PowerShell 5 profile
├── pwsh7_profile.ps1             # PowerShell 7 profile
├── scoop/
│   ├── backup.json               # Scoop 应用备份
│   ├── backup.lite.json          # 尝鲜版最小依赖
│   └── scoop.zsh                 # zsh：scoop mirror / services
├── starship.lua                  # cmd 下 clink + starship
└── utils.zsh                     # 自定义函数
```

### scoop mirror

<!-- BEGIN GENERATED GITHUB ACCEL SCOOP MIRROR -->
一键同步切换 Scoop 仓库、GitHub bucket 远端及下载镜像。

```sh
scoop mirror                      # 交互选择（↑↓ / Enter；Esc/Ctrl+C 取消；回车选中当前 * 则直接退出）
scoop mirror status               # 显示当前镜像与下载规则
scoop mirror ghproxy              # 直接切换到 gh-proxy.com
scoop mirror ghproxy-net          # 直接切换到 ghproxy.net
scoop mirror official             # 恢复官方源
```
<!-- END GENERATED GITHUB ACCEL SCOOP MIRROR -->

### scoop services

需先 `scoop install winsw-pre`，并配置 `runtime/scoop/services/manifest.json`。

```sh
scoop services help
scoop services ls                 # 列出已管理服务
scoop services install nginx      # 注册并启动
scoop services uninstall nginx    # 注销服务
scoop services start nginx        # 启动
scoop services stop nginx         # 停止
scoop services restart nginx      # 重启
scoop uninstall nginx             # 自动注销服务后卸载
scoop update nginx                # 版本变更且服务原在运行 → 自动 restart（类 brew :changed）
```

> [!NOTE]
> `scoop update` / `scoop update *` 会对 manifest 中已注册且更新前在运行的服务，在版本号变化后自动重启。
> 清单项可设 `"restartOnUpdate": false` 退出该行为；缺省为启用。

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
├── .zshrc_core                   # macos / windows 公共核心 zsh
├── _eza                          # eza 补全（只恢复）
├── aliases.zsh                   # 公共别名
├── github-accel.zsh              # GitHub 加速函数（生成，只恢复）
├── mihomo.yaml                   # Mihomo 配置
├── opencode.jsonc                # OpenCode 配置
└── starship.toml                 # starship 配置
```

## 脚本逻辑

![install-flow](assets/install-flow.svg)

![init-flow](assets/init-flow.svg)

![sync-flow](assets/sync-flow.svg)

![vpr-dispatch](assets/dispatch-flow.svg)
