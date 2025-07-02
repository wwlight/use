# 个人配置

## mac

#### 操作命令

```sh
$ bash ./scripts/mac-init.sh             # 初始化 mac 软件安装（支持自动安装 brew）
$ nr mac:backup                          # 备份 mac brew 安装软件
$ nr mac:setup                           # 安装 mac brew 软件
$ nr mac:sync 1                          # 同步本地 mac 配置文件到仓库
```

<details>
<summary>文件说明</summary>

- [Brewfile](./mac/Brewfile) - 关于 [Homebrew](https://brew.sh/) 安装应用备份文件
- [.zprofile](./mac/.zprofile) - brew 及镜像配置文件
- [.zshrc](./mac/.zshrc) - zsh 配置文件
- [util.zsh](./mac/utils.zsh) - zsh 自定义函数

</details>

## windows

> [!NOTE]
> 在 powershell 中安装 scoop
> ```sh
> $env:SCOOP='D:\DevelopApplication\Scoop'
> [Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> iex "& {$(irm get.scoop.sh)} -RunAsAdmin"
> ```
> ```sh
> scoop install git
> ```

#### 操作命令

```sh
$ bash ./scripts/win-init.sh             # 初始化 windows 软件安装（基于 scoop 和 git）
$ nr win:backup                          # 备份 windows scoop 安装软件
$ nr win:setup                           # 安装 windows scoop 软件
$ nr win:sync 1                          # 同步本地 windows 配置文件到仓库
$ nr win:zsh                             # 安装 zsh 到 git
$ nr win:clink                           # 安装 clink 插件
$ nr win:git-extras                      # 安装 git-extras 插件
```

<details>
<summary>文件说明</summary>

- [scoop_backup.json](./windows/scoop_backup.json) - 关于 [Scoop](https://scoop.sh/) 安装应用备份文件
- [.zshrc](./windows/.zshrc) - zsh 配置文件
- [utils.zsh](./windows/utils.zsh) - 自定义函数
- [starship.lua](./windows/starship.lua) - 在 cmd 中，基于 [clink](https://chrisant996.github.io/clink/) 来使用 [starship](https://starship.rs/)
- [fnm_init.cmd](./windows/fnm_init.cmd) - 在 cmd 中，使用 [fnm](https://github.com/Schniz/fnm#zsh) 相关配置
- [WinSW.xml](./windows/WinSW.xml) - 使用 [WinSW](https://github.com/winsw/winsw/) 来实现 [Nginx](https://nginx.org/) 自启动配置文件
```sh
$ cp ./windows/WinSW.xml "$(scoop prefix winsw | tr -d '\r')\\WinSW.xml"
$ winsw install
$ winsw uninstall
$ winsw start
$ winsw stop
$ winsw restart
$ winsw status
```
```sh
# hyper
$ hyper install hyper-dracula
$ hyper install hyperborder
$ hyper install hyperpower
```
```sh
# clink
$ clink info
$ clink autorun install    # 启用自动运行
$ clink autorun uninstall  # 禁用自动运行
$ clink inject             # 临时运行

$ scoop hold clink         # 禁止更新
```
```sh
# starship 关于 powershell 配置
# code $PROFILE 打开配置文件，将下面内容填入

Invoke-Expression (&starship init powershell)
# Invoke-Expression (& "$env:SCOOP\\apps\\starship\\current\\starship.exe" init powershell)
$ENV:STARSHIP_CONFIG = "$HOME\\.config\\starship\\starship.toml"
```

</details>

## other

#### 操作命令

```sh
$ nr other:sync 1                        # 同步本地其它配置文件到仓库
$ nr other:sync 2                        # 同步仓库其它配置文件到本地
```

<details>
<summary>文件说明</summary>

- [_eza](./other/_eza) - [eza](https://eza.rocks/) 自动补全配置 | [官方地址](https://github.com/eza-community/eza/tree/main/completions/zsh)
- [starship.toml](./other/starship.toml) - [starship](https://starship.rs/) 配置文件

</details>


> [!NOTE]
> ```sh
> # 自定义 npm 全局包安装位置
> $ npm config set prefix ~/.npm_global
> ```
