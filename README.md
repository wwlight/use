# 个人配置

### 同步命令
```sh
$ sh ./bash/init_mac.sh            # 初始化 mac 软件安装
$ sh ./bash/init_win.sh            # 初始化 windows 软件安装
$ nr mac:backup                    # 备份 mac brew 安装软件
$ nr mac:setup                     # 安装 mac brew 软件
$ nr mac:sync 1                    # 同步本地 mac zsh 配置文件到仓库
$ nr win:backup                    # 备份 windows scoop 安装软件
$ nr win:setup                     # 安装 windows scoop 软件
$ nr win:sync 1                    # 同步本地 windows zsh 配置文件到仓库
$ nr other:sync 1                  # 同步本地其它配置文件到仓库
$ nr setup:clink                   # 安装 clink 插件
$ nr setup:git                     # 安装 git-extras 插件
```

### mac
- [Brewfile](./mac/Brewfile) - 关于 [Homebrew](https://brew.sh/) 安装应用备份文件
- [.zshrc](./mac/.zshrc) - zsh 配置文件

### windows
- [scoop_backup.json](./windows/scoop_backup.json) - 关于 [Scoop](https://scoop.sh/) 安装应用备份文件
- [.zshrc](./windows/.zshrc) - zsh 配置文件
- [utils.zsh](./windows/utils.zsh) - 自定义函数
- [WinSW.xml](./windows/WinSW.xml) - 使用 [WinSW](https://github.com/winsw/winsw/) 来实现 [Nginx](https://nginx.org/) 自启动配置文件
```sh
$ cp ./windows/WinSW.xml D:/DevelopApplication/Scoop/apps/winsw/current
$ winsw install
$ winsw uninstall
$ winsw start
$ winsw stop
$ winsw restart
$ winsw status
```

### 其它
- [starship.toml](./other/starship.toml) - [starship](https://starship.rs/) 配置文件
- [_eza](./other/_eza) - [eza](https://eza.rocks/) 自动补全配置 | [官方地址](https://github.com/eza-community/eza/tree/main/completions/zsh)
