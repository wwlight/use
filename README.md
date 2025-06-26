# 个人配置

- [Brewfile](./config/Brewfile) - 关于 [Homebrew](https://brew.sh/) 安装应用备份文件
```sh
$ brew bundle dump --force --file=~/Desktop/Brewfile  # 生成 Brewfile
$ brew bundle install --file=~/Desktop/Brewfile       # 读取 Brewfile 并安装所有依赖
$ brew bundle check                                   # 检查 Brewfile 中的软件是否已安装
```
- [scoop_backup.json](./config/scoop_backup.json) - 关于 [Scoop](https://scoop.sh/) 安装应用备份文件
```sh
$ scoop export > scoop_backup.json   # 导出已安装 Scoop 应用
$ scoop import scoop_backup.json     # 从备份文件恢复所有应用
```
- [WinSW.xml](./config/WinSW.xml) - 关于 [WinSW](https://github.com/winsw/winsw/) 来实现 [Nginx](https://nginx.org/) 自启动配置文件
> 需要将文件放置到 winsw.exe 同级目录内
```sh
$ winsw start
$ winsw stop
$ winsw restart
$ winsw status
```
