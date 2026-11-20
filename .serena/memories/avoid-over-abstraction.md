# 不要过度提取 / 封装

对本仓库改脚本时优先 **对齐现有实现**，不要为了「单一来源」发明新层。

## 原则

1. **几行重复 ≠ 值得抽库**：`normalize_repo_url` 这类 5～10 行的字符串处理，bash/ps1 各留一份（或 utils + install bootstrap 副本）即可；不要再套 `.mjs`、CLI、专项单测。
2. **抽公共模块要有真实调用面**：若「权威实现」只被测试引用、或仓内脚本仍要内联副本（如 `install.sh` bootstrap），则提取失败——删掉中间层。
3. **manifest / helper 抽取要克制**：只抽已在多处使用、且改动频繁的数据（如 `brewMirrors.label`、`profiles`）；不要为一次性硬编码建框架。
4. **单测跟复杂度匹配**：有分支逻辑的共享模块（如 `menu-select`、`manifest-config`）值得测；纯字符串规范化的内联函数不值得单独测试文件。
5. **bootstrap 约束优先**：`install.sh` / `install.ps1` 在 clone 前必须自包含——见 `mem:install-bootstrap-constraints`。不要为对齐 install 与 utils 而强迫 install 依赖仓内模块。

## 注释规范

只标注**核心行为**（做什么、关键参数/分支），不要写实现同步类说明。

**不要写：**
- 「与 utils.ps1 / Sync-GitRepoPlugin 对齐」
- 「须与 install.sh 保持一致」
- 「zsh / clink 共用」
- 「bootstrap 不能依赖仓内文件」
- 「避免散落的硬编码」「供 shell/ps1 与单测共用」这类目的陈述

**可以写：**
- 「规范化 git remote，便于比较是否同一仓库」
- 「安装或更新 git 仓库型插件」+ 用法/分支说明
- 「进度：入口完成第 1 步，总数含后续 init 步数」

跨文件一致性靠 review / 实现，不靠注释提醒。

## 反例（勿再犯）

- 为对齐 `normalize_repo_url` 新建 `.mjs` + 专项测试再 `node` 调用——过度封装，已删。
- 注释里写「须与…保持一致」「与…对齐」——冗余，已去掉。

## 正例

- `install.*` 与 utils 各留同算法副本（bootstrap）；注释只写功能。
- `manifest-config.mjs`、`Sync-GitRepoPlugin` / `sync_git_repo_plugin`：有真实多调用面——抽取合理。
