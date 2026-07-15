# 个人配置

## 一键安装

mac（省略参数则交互选尝鲜/完整）

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh)"
```

mac 尝鲜版

```sh
curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash -s -- lite
```

mac 完整版

```sh
curl -fsSL https://raw.githubusercontent.com/wwlight/use/main/install.sh | bash -s -- full
```

windows（省略参数则交互选尝鲜/完整）

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

windows 尝鲜版

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
$env:USE_PROFILE='lite'; irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

windows 完整版

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
$env:USE_PROFILE='full'; irm https://raw.githubusercontent.com/wwlight/use/main/install.ps1 | iex
```

## 安装 [vite.plus](http://vite.plus)

mac

```sh
curl -fsSL https://vite.plus | bash
```

windows

```powershell
irm https://vite.plus/ps1 | iex
```

## 通用命令

```sh
$ vpr pm                                         # 安装包管理器（mac: brew / win: scoop）
$ vpr pm -- ustc                                 # mac 可选镜像：official | ustc | tuna
$ vpr init                                       # 初始化系统软件（交互选尝鲜/完整）
$ vpr init -- lite                               # 尝鲜版（mac: Brewfile.lite；win: scoop_backup.lite.json）
$ vpr init -- full                               # 完整版
$ vpr backup                                     # 备份已安装软件到仓库（win 同时更新尝鲜版）
$ vpr setup                                      # 从仓库恢复完整软件清单
$ vpr sync                                       # 交互选择同步方向
$ vpr sync 1                                     # 同步本地配置到仓库
$ vpr sync 2                                     # 从仓库恢复配置到本地
$ vpr zsh-plugin                                 # 安装/更新 zsh 插件
```

- 命令会通过 [scripts/_dispatch.mjs](./scripts/_dispatch.mjs) 按当前操作系统自动分发（`mac` → `Homebrew`，`windows` → `Scoop`）。

> [!WARNING]
> zip 下载解压后需先解除脚本封锁（git clone 可跳过）
>
> ```powershell
> Get-ChildItem scripts,configs -Recurse -Include *.ps1,*.psm1 | Unblock-File
> ```

## mac

> [!NOTE]
> 首次安装
>
> ```sh
> $ vpr pm                                         # 官方源（默认）
> $ vpr pm -- ustc                                 # 中科大镜像
> $ vpr pm -- tuna                                 # 清华镜像
> $ vpr init                                       # 初始化（需先安装 brew；交互选尝鲜/完整）
> $ vpr init -- lite                               # 尝鲜版
> ```

文件说明

- [Brewfile](./configs/mac/Brewfile) - 关于 [Homebrew](https://brew.sh/) 安装应用备份文件
- [Brewfile.lite](./configs/mac/Brewfile.lite) - 尝鲜版最小依赖
- [.zshrc](./configs/mac/.zshrc) - zsh 平台配置
- [utils.zsh](./configs/mac/utils.zsh) - zsh 自定义函数

## windows

> [!NOTE]
> 首次安装
>
> ```sh
> $ vpr hosts                                      # 更新 GitHub hosts（需管理员）
> $ vpr pm                                         # 安装 scoop
> $ vpr init                                       # 初始化（需先安装 scoop；交互选尝鲜/完整）
> $ vpr init -- lite                               # 尝鲜版
> ```

#### windows 专属命令

```sh
$ vpr zsh                                        # 安装 zsh 到 git（已装 zsh 时可选择跳过插件）
$ vpr zsh-plugin                                 # 安装/更新 zsh 插件
$ vpr git-setup                                  # Git 全局配置
$ vpr git-extras                                 # 安装 git-extras 插件
$ vpr clink                                      # 安装 clink 插件（cmd 扩展）
$ vpr hosts                                      # 更新 GitHub hosts（需管理员）
```

文件说明

- [scoop_backup.json](./configs/windows/scoop_backup.json) - 关于 [Scoop](https://scoop.sh/) 安装应用备份文件
- [scoop_backup.lite.json](./configs/windows/scoop_backup.lite.json) - 尝鲜版最小依赖
- [.zshrc](./configs/windows/.zshrc) - zsh 平台配置
- [utils.zsh](./configs/windows/utils.zsh) - 自定义函数
- [aliases.zsh](./configs/windows/aliases.zsh) - windows 专属别名（sync 到 `~/.zsh/functions/aliases.win.zsh`）
- [services-manifest.json](./configs/windows/services-manifest.json) - `scoop services` 服务注册配置文件
- [scoop_services.zsh](./configs/windows/scoop_services.zsh) - 扩展 `scoop services`，基于 [WinSW](https://github.com/winsw/winsw/) 管理 windows 服务；zsh 加载于 `~/.zsh/functions/`，PowerShell 见 `pwsh5_profile.ps1` / `pwsh7_profile.ps1`
- [starship.lua](./configs/windows/starship.lua) - 在 cmd 中，基于 [clink](https://chrisant996.github.io/clink/) 来使用 [starship](https://starship.rs/)

```sh
# scoop services（需先 scoop install winsw-pre，并配置 services-manifest.json）
$ scoop services help
$ scoop services ls                              # 列出已管理服务
$ scoop services install nginx                   # 注册并启动
$ scoop services uninstall nginx                 # 注销服务
$ scoop services start nginx                     # 启动
$ scoop services stop nginx                      # 停止
$ scoop services restart nginx                   # 重启
$ scoop uninstall nginx                          # 自动注销服务后卸载
```

```sh
# clink
$ clink info
$ clink autorun install -- --quiet               # 启用自动运行
$ clink autorun uninstall                        # 禁用自动运行
$ clink inject                                   # 临时运行
$ scoop hold clink                               # 禁止更新
```

## common 配置

文件说明

- [.zshrc_core](./.zshrc_core) - mac / windows 公共核心 zsh 配置，sync 到 `~/.zsh/.zshrc_core`，由平台 `.zshrc` source
- [aliases.zsh](./aliases.zsh) - 公共别名，sync 到 `~/.zsh/functions/aliases.zsh`
- [_eza](./_eza) - [eza](https://eza.rocks/) 自动补全配置 | [官方地址](https://github.com/eza-community/eza/tree/main/completions/zsh)
- [starship.toml](./starship.toml) - [starship](https://starship.rs/) 配置文件
