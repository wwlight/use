# 个人配置

<!-- BEGIN GENERATED GITHUB ACCEL DOCS -->
## 一键安装

### macos · 交互选择

```sh
curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash
```

```sh
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghfast bash
```

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghproxy bash
```

### macos · 尝鲜版

```sh
curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash -s -- lite
```

```sh
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghfast bash -s -- lite
```

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghproxy bash -s -- lite
```

### macos · 完整版

```sh
curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash -s -- full
```

```sh
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghfast bash -s -- full
```

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.sh | USE_ACCEL=ghproxy bash -s -- full
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
$env:USE_ACCEL='ghfast'; irm https://ghfast.top/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

```powershell
$env:USE_ACCEL='ghproxy'; irm https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

### windows · 尝鲜版

```powershell
$env:USE_PROFILE='lite'; irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

```powershell
$env:USE_PROFILE='lite'; $env:USE_ACCEL='ghfast'; irm https://ghfast.top/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

```powershell
$env:USE_PROFILE='lite'; $env:USE_ACCEL='ghproxy'; irm https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

### windows · 完整版

```powershell
$env:USE_PROFILE='full'; irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

```powershell
$env:USE_PROFILE='full'; $env:USE_ACCEL='ghfast'; irm https://ghfast.top/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

```powershell
$env:USE_PROFILE='full'; $env:USE_ACCEL='ghproxy'; irm https://gh-proxy.com/https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```


## 安装 [vite.plus](https://viteplus.dev/)

仓库：https://github.com/voidzero-dev/vite-plus

### macos

```sh
curl -fsSL https://vite.plus | bash
```

```sh
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli/install.sh | bash
```

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli/install.sh | bash
```

### windows

```powershell
irm https://vite.plus/ps1 | iex
```

```powershell
irm https://ghfast.top/https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli/install.ps1 | iex
```

```powershell
irm https://gh-proxy.com/https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli/install.ps1 | iex
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
vpr sync 1                        # 备份配置 → 仓库
vpr sync 2                        # 恢复配置 → 本地
vpr zsh-plugin                    # 安装/更新 zsh 插件
vpr git-setup                     # Git 全局配置
```

### 其他命令

```sh
vpr generate:github-accel         # 从 manifest 更新 GitHub 加速配置与 README
vpr check:github-accel            # 检查生成内容是否需要更新
vpr generate:homebrew             # 从 manifest 更新 Homebrew 镜像目录与 Brewfile.lite
vpr check:homebrew                # 检查 Homebrew 生成内容是否需要更新
vpr test                          # 运行项目检查
```

> [!TIP]
> zip 下载解压后需先解除脚本封锁

```powershell
Get-ChildItem scripts,configs -Recurse -Include *.ps1,*.psm1 | Unblock-File
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
brew-mirror                       # 交互选择（fzf / 编号；Esc/Ctrl+C 取消；回车选中当前 * 则直接退出）
brew-mirror status                # 显示当前镜像
brew-mirror ustc                  # 中科大镜像
brew-mirror tuna                  # 清华镜像
brew-mirror official              # 恢复官方源
```

```text
configs/macos/
├── .bashrc                       # bash 配置
├── .zshrc                        # zsh 平台配置
├── Brewfile                      # Homebrew 应用备份
├── Brewfile.lite                 # 尝鲜版（由 Brewfile + brewLiteItems 生成）
├── brew-mirror.zsh               # Homebrew 镜像切换逻辑
├── brew-mirrors.tsv              # 镜像目录（由 _manifest.json 生成）
├── ghostty_config                # Ghostty 终端配置
└── utils.zsh                     # zsh 自定义函数
```

运行时文件：

```text
~/.config/homebrew/
├── mirrors.tsv                   # 本地镜像目录
├── mirror.zsh                    # 当前镜像环境变量
└── brew-mirror.zsh               # brew-mirror 命令
```



## windows

```sh
vpr pm                            # 安装 scoop，交互选加速镜像
vpr pm -- ghfast                  # ghfast.top 加速镜像
vpr pm -- ghproxy                 # gh-proxy.com 加速镜像
vpr pm -- official                # 官方源
vpr init                          # 初始化（会启用已选加速）
vpr init -- lite                  # 尝鲜版
vpr init -- full                  # 完整版
```

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
│   ├── scoop.ps1                 # PowerShell：scoop mirror / services
│   ├── scoop.zsh                 # zsh：scoop mirror / services
│   └── services/
│       └── manifest.json         # → $SCOOP/config/scoop-services/manifest.json
├── starship.lua                  # cmd 下 clink + starship
└── utils.zsh                     # 自定义函数
```


### scoop mirror

一键同步切换 Scoop 仓库、GitHub bucket 远端及后续安装、更新使用的下载镜像。

```text
scripts/windows/scoop/
├── install.ps1(.sh)              # vpr pm 入口
├── accel.ps1                     # 镜像 / aria2 / hook 编排
├── deploy.ps1                    # 部署 scoop-mirror / scoop-services 到 $SCOOP/config
├── lite-backup.mjs               # 生成 backup.lite.json
├── mirror/
│   ├── hook.ps1                  # → $SCOOP/config/scoop-mirror/hook.ps1
│   ├── shared.ps1                # → $SCOOP/config/scoop-mirror/shared.ps1
│   ├── manage.ps1                # → $SCOOP/config/scoop-mirror/manage.ps1
│   ├── cli.mjs                   # → $SCOOP/config/scoop-mirror/cli.mjs
│   └── test.mjs
├── services/
│   └── manage.ps1                # → $SCOOP/config/scoop-services/manage.ps1
└── import-backup.ps1             # vpr setup：按当前镜像 import
```

运行时在 `$SCOOP/config/scoop-mirror/` 生成 `config.json`；菜单依赖同步到同目录 `lib/`。

```sh
scoop mirror                      # 交互选择（↑↓ / Enter；Esc/Ctrl+C 取消；回车选中当前 * 则直接退出）
scoop mirror status               # 显示当前镜像
scoop mirror ghfast               # 直接切换到 ghfast.top
scoop mirror ghproxy              # 直接切换到 gh-proxy.com
scoop mirror official             # 恢复官方源
```

### scoop services

需先 `scoop install winsw-pre`，并配置 `configs/windows/scoop/services/manifest.json`。

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
