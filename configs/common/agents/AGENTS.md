# Global Rules (Discipline)

以下规则对所有会话、所有项目无条件生效。违反任何一条都算失败。

## 1. 先方案，后执行

- 任何涉及修改文件、运行命令、改动配置的任务，**输出方案（做什么、改哪些文件、影响范围）之后，必须等待用户确认，再动手**。
- 用户没有说"开始/可以"，禁止执行任何变更性操作。
- 纯咨询/问答（不涉及任何改动）不用等确认，直接回答。

## 2. 不确定就提问，不许自己试

- 遇到含义不清、方案有歧义、有多种可能做法时，**先列出选项让用户选，禁止凭猜测执行**。
- 禁止为了验证而自行"试探性"地运行命令、抓取文档、扫描源码。需要外部信息时，先说明"我打算查什么、为什么"，经允许再做。
- 禁止临时编写并运行一次性 node/python/shell 探针脚本来"验证行为是否正确"；拿不准时直接提问或让用户来验证。
- 探索永远限制在任务必需的最小范围，不做无目的的深挖。

## 3. 先讲清楚再开跑

- 执行任何非显而易见命令前，用一句话说明"这条命令是干什么的、为什么需要它"。
- 被询问"你在干什么"时，能立刻简要作答。

## 4. 最小改动

- 只动任务要求的文件与行，不顺手"优化"、不改无关代码、不重建不必要的东西。
- 改动前先读相关文件，遵循现有风格。

## 5. 透明汇报

- 任务完成后汇报：改了哪些文件、结果如何，不报喜不报忧。

## 6. 目录访问限制

- 禁止自行读取 `node_modules`、`dist`、`.output` 等依赖/构建产物目录。
- 确实需要时，必须先说明"要查什么、为什么"，征得用户授权后再读取。
- 禁止读取 `.env`、凭证文件和 `~/.config/opencode/service.json`。

## 7. 工具与技能

- 符号级操作用 `serena`：定义、引用、重命名、替换符号体、在符号前后插入代码。
- 浏览器调试用 `@browser`（chrome-devtools）。shadcn 组件用 `@ui`。MDN 文档与兼容性用 `@docs`。
- 提交用 `/commit`。评审用 `/review`。
- 涉及 git 约定或实现取舍时，用 skill 工具加载 `git-workspace`、`karpathy-guidelines`。

## 8. 非交互 Shell

OpenCode 的 shell 没有 TTY。命令必须一次跑完，不能等待确认、分页或编辑器。

- 安装和初始化带上非交互标志：`pnpm` 用已有脚本，`npm init -y`，`apt-get install -y`，`pip install --no-input`。
- 禁止 `git commit` 不带 `-m` 而打开编辑器。提交说明放在 `-m` 里。
- 设置 `GIT_PAGER=cat`、`PAGER=cat`，不要跑 `less`、`vim`、`nano`。
- 读文件、改文件用内置工具，不用 `cat`、`sed`、`echo >` 绕过去。

## 9. Homebrew 第三方 tap 信任

信任记在 `~/.homebrew/trust.json`。没有命令会自动清掉已卸载软件留下的信任。

- 只信任正在用的包：`brew trust --formula <user>/<tap>/<name>` 或 `brew trust --cask <user>/<tap>/<name>`。不要 `brew trust --tap`。整份 tap 被信任后，`brew uninstall` 不会删掉这条信任。
- `brew uninstall` 只在 tap 本身未被信任时，删掉对应 formula 或 cask 的信任。
- `brew untap` 只删本机 tap 仓库，不改 `trust.json`。先在 tap 还在时执行 `brew untrust`，再 `brew untap`。
- `brew untrust --tap <tap>` 会连带删掉以该 tap 引用开头的 formula、cask、command 信任。还在用的包要在这之后重新 `brew trust`。
- `brew trust` 和 `brew untrust` 不带参数只是列出条目，不会清理。
- 远程不是默认的 `homebrew-<repo>` 时，信任按仓库 URL 记录，例如 `https://github.com/org/repo/name`。`brew bundle dump` 只在信任条目与 `user/tap/formula` 全名完全一致时，才在 formula 或 cask 行写 `trusted: true`。URL 形式在运行时仍然算已信任。
- 只 tap 了、没有安装包的仓库不需要信任。确认没有已安装包后再 `brew untap`。
- 改完信任后，若要让 Brewfile 跟上，再执行 `brew bundle dump --file=<Brewfile> --force`。