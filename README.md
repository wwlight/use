# 个人配置

### mac
- [Brewfile](./mac/Brewfile) - 关于 [Homebrew](https://brew.sh/) 安装应用备份文件
```sh
$ brew bundle dump --force --file=~/Desktop/Brewfile  # 生成 Brewfile
$ brew bundle install --file=~/Desktop/Brewfile       # 读取 Brewfile 并安装所有依赖
$ brew bundle check                                   # 检查 Brewfile 中的软件是否已安装
```
- [.zshrc](./mac/.zshrc) - zsh 配置文件

### windows
- [scoop_backup.json](./windows/scoop_backup.json) - 关于 [Scoop](https://scoop.sh/) 安装应用备份文件
```sh
$ scoop import ./windows/scoop_backup.json     # 从备份文件恢复所有应用
```
- [.zshrc](./windows/.zshrc) - zsh 配置文件
- [utils.zsh](./windows/utils.zsh) - 自定义函数
- [_eza](./windows/_eza) - [eza](https://eza.rocks/) 自动补全配置 | [线上地址](https://github.com/eza-community/eza/tree/main/completions/zsh)
- [WinSW.xml](./windows/WinSW.xml) - 使用 [WinSW](https://github.com/winsw/winsw/) 来实现 [Nginx](https://nginx.org/) 自启动配置文件
  - 需要将文件放置到 winsw.exe 同级目录内
```sh
$ winsw start
$ winsw stop
$ winsw restart
$ winsw status
```

### 其它
- [starship.toml](./other/starship.toml) - [starship](https://starship.rs/) 配置文件
