# 个人配置

## 安装 [vite.plus](http://vite.plus)

```sh
# mac / Git Bash
$ bash ./scripts/common/vite-plus-install.sh

# zip 下载解压后需先解除脚本封锁（git clone 可跳过）
$ powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath './scripts' -Recurse -Include *.ps1,*.psm1 | Unblock-File -ErrorAction SilentlyContinue"
# windows PowerShell
$ powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/common/vite-plus-install.ps1
```

## 通用命令

```sh
$ vpr pm                                         # 安装包管理器（mac: brew / win: scoop）
$ vpr pm -- ustc                                 # mac 可选镜像：official | ustc | tuna
$ vpr init                                       # 初始化系统软件（目录、依赖、插件、配置同步等）
$ vpr backup                                     # 备份已安装软件到仓库
$ vpr setup                                      # 从仓库恢复软件（Brewfile / scoop_backup.json）
$ vpr sync 1                                     # 同步本地配置到仓库
$ vpr sync 2                                     # 从仓库恢复配置到本地
$ vpr sync                                       # 交互选择同步方向
```
- 命令会通过 [scripts/_dispatch.mjs](./scripts/_dispatch.mjs) 按当前操作系统自动分发（`mac` → `Homebrew`，`windows` → `Scoop`）。



## mac

> [!NOTE]
> 首次安装
>
> ```sh
> $ vpr pm                                         # 官方源（默认）
> $ vpr pm -- ustc                                 # 中科大镜像
> $ vpr pm -- tuna                                 # 清华镜像
> $ vpr init                                       # 初始化（需先安装 brew）
> ```

文件说明

- [Brewfile](./configs/mac/Brewfile) - 关于 [Homebrew](https://brew.sh/) 安装应用备份文件
- [.zshrc](./configs/mac/.zshrc) - zsh 平台配置
- [utils.zsh](./configs/mac/utils.zsh) - zsh 自定义函数



## windows

> [!NOTE]
> 首次安装
>
> ```sh
> $ vpr hosts                                      # 更新 GitHub hosts（需管理员）
> $ vpr pm                                         # 安装 scoop
> $ vpr init                                       # 初始化系统软件
> ```



#### windows 专属命令

```sh
$ vpr zsh                                        # 安装 zsh 到 git（已装 zsh 时可选择跳过插件）
$ vpr git-setup                                  # Git 全局配置
$ vpr git-extras                                 # 安装 git-extras 插件
$ vpr clink                                      # 安装 clink 插件（cmd 扩展）
$ vpr hosts                                      # 更新 GitHub hosts（需管理员）
```

文件说明

- [scoop_backup.json](./configs/windows/scoop_backup.json) - 关于 [Scoop](https://scoop.sh/) 安装应用备份文件
- [.zshrc](./configs/windows/.zshrc) - zsh 平台配置
- [utils.zsh](./configs/windows/utils.zsh) - 自定义函数
- [aliases.zsh](./configs/windows/aliases.zsh) - Windows 专属别名（sync 到 `~/.zsh/functions/aliases.win.zsh`）
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

```text
Q：隐藏 powershell/cmd 启动时的提示信息
A：在 powershell 目标路径后追加 -NoLogo 或者 -nologo
A：在 cmd 目标路径后追加 -NoLogo /k 或者 -nologo /k
```



## common 配置

## 文件说明

- [.zshenv](./.zshenv) - 设置 `ZDOTDIR`，**必须** sync 到 `~/.zshenv`（home 根目录，不在 `~/.zsh/` 内）
- [.zshrc_core](./.zshrc_core) - mac / windows 公共核心 zsh 配置，sync 到 `~/.zsh/.zshrc_core`
- [aliases.zsh](./aliases.zsh) - 公共别名，sync 到 `~/.zsh/functions/aliases.zsh`
- [_eza](./_eza) - [eza](https://eza.rocks/) 自动补全配置 | [官方地址](https://github.com/eza-community/eza/tree/main/completions/zsh)
- [starship.toml](./starship.toml) - [starship](https://starship.rs/) 配置文件
