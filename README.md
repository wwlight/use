# 个人配置

## mac

> [!NOTE]
> 首次安装
>
> ```sh
> bash ./scripts/mac/brew-install.sh              # 官方源（默认）
> bash ./scripts/mac/brew-install.sh ustc         # 中科大镜像
> bash ./scripts/mac/brew-install.sh tuna         # 清华镜像
> bash ./scripts/mac/init.sh                      # 初始化（需先安装 brew）
> ```
>
> `brew-install` / `init` 会自动检测并安装 [vite.plus](https://vite.plus/)（`vpr`）。

#### 操作命令

```sh
$ vpr mac:backup                              # 备份 mac brew 安装软件
$ vpr mac:setup                               # 安装 mac brew 软件
$ vpr mac:sync 1                              # 同步 mac 本地配置文件到仓库
$ vpr mac:sync 2                              # 同步仓库配置文件到本地
$ vpr mac:sync                                # 交互选择同步方向
```

文件说明

- [Brewfile](./configs/mac/Brewfile) - 关于 [Homebrew](https://brew.sh/) 安装应用备份文件
- [.zshrc](./configs/mac/.zshrc) - zsh 配置文件
- [util.zsh](./configs/mac/utils.zsh) - zsh 自定义函数



## windows

> [!NOTE]
> 首次安装
> 建议使用管理员 PowerShell 运行。
>
> ```sh
> # zip 下载解压后需先解除脚本封锁（git clone 可跳过）
> powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath './scripts' -Recurse -Include *.ps1,*.psm1 | Unblock-File -ErrorAction SilentlyContinue"
> powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/windows/github-hosts.ps1
> powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/windows/scoop-install.ps1
> powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/windows/init.ps1
> # Git Bash 备选：
> # bash ./scripts/windows/github-hosts.sh
> # bash ./scripts/windows/scoop-install.sh
> # bash ./scripts/windows/init.sh
> ```
>
> `scoop-install` / `init` 会自动检测并安装 [vite.plus](https://vite.plus/)（`vpr`）。



#### 操作命令

```sh
$ vpr win:backup                              # 备份 windows scoop 安装软件（chcp 65001）
$ vpr win:setup                               # 安装 windows scoop 软件
$ vpr win:sync 1                              # 同步 windows 本地配置文件到仓库
$ vpr win:sync 2                              # 同步仓库配置文件到本地
$ vpr win:zsh                                 # 安装 zsh 到 git（已装 zsh 时可选择跳过插件）
$ vpr win:git-extras                          # 安装 git-extras 插件
$ vpr win:clink                               # 安装 clink 插件（cmd 扩展）
```

文件说明

- [scoop_backup.json](./configs/windows/scoop_backup.json) - 关于 [Scoop](https://scoop.sh/) 安装应用备份文件
- [.zshrc](./configs/windows/.zshrc) - zsh 配置文件
- [utils.zsh](./configs/windows/utils.zsh) - 自定义函数
- [services-manifest.json](./configs/windows/services-manifest.json) - `scoop services` 服务注册配置文件
- [scoop_services.zsh](./configs/windows/scoop_services.zsh) - 扩展 `scoop services`，基于 [WinSW](https://github.com/winsw/winsw/) 管理 Windows 服务；zsh 加载于 `~/.zsh/functions/`，PowerShell 见 `pwsh5_profile.ps1` / `pwsh7_profile.ps1`
- [starship.lua](./configs/windows/starship.lua) - 在 cmd 中，基于 [clink](https://chrisant996.github.io/clink/) 来使用 [starship](https://starship.rs/)

```sh
# scoop services（需先 scoop install winsw-pre，并配置 services-manifest.json）
$ scoop services help
$ scoop services ls                     # 列出已管理服务
$ scoop services install nginx          # 注册并启动
$ scoop services uninstall nginx        # 注销服务
$ scoop services start nginx            # 启动
$ scoop services stop nginx             # 停止
$ scoop services restart nginx          # 重启
$ scoop uninstall nginx                 # 自动注销服务后卸载
```

```sh
# clink
$ clink info
$ clink autorun install -- --quiet     # 启用自动运行
$ clink autorun uninstall              # 禁用自动运行
$ clink inject                         # 临时运行
$ scoop hold clink                     # 禁止更新
```

```text
Q：隐藏 powershell/cmd 启动时的提示信息
A：在 powershell 目标路径后追加 -NoLogo 或者 -nologo
A：在 cmd 目标路径后追加 -NoLogo /k 或者 -nologo /k
```



## common

> `vpr common:*` 会通过分发器按当前 shell 自动选择 `.ps1` 或 `.sh`。



#### 操作命令

```sh
$ vpr common:sync 1                           # 同步本地配置文件到仓库
$ vpr common:sync 2                           # 同步仓库配置文件到本地
$ vpr common:setup                            # Git 全局配置
```

文件说明

- [_eza](./configs/common/_eza) - [eza](https://eza.rocks/) 自动补全配置 | [官方地址](https://github.com/eza-community/eza/tree/main/completions/zsh)
- [starship.toml](./configs/common/starship.toml) - [starship](https://starship.rs/) 配置文件

