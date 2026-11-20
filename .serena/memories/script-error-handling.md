# 脚本错误处理：既有设计 vs 本轮修改（review 必读）

## Review 方法（强制）

后续改脚本或做 code review 时：

1. **先还原「为什么旧代码这么写」**（管道/`$()`/`irm|iex`/软失败），再评新方案。
2. **禁止以「对齐 error()/exit」为唯一理由**做替换；对齐必须同时对齐调用约定（是否在 `$()`、是否 iex、是否可 catch）。
3. 改退出策略后，用手推演：失败时用户看到什么、进程/会话是否还在、父脚本会否假成功。

## 本轮已改文件与设计取舍

### `install.ps1`（引导脚本）

| 阶段     | 行为                                                                                                           | 问题                                                         |
| -------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| 更早     | `throw "[ERROR] ..."`                                                                                          | `irm\|iex` 甩 Exception 堆栈                                 |
| 中间     | `exit 1`                                                                                                       | 关掉整个 PowerShell 会话（与 `curl\|bash` 的 exit 语义不同） |
| **当前** | 打印后 `throw 'USE_FATAL'` + 顶层 catch → `Complete-UseFatal`：有 `$PSCommandPath` 则 `exit 1`，否则仅结束脚本 | 干净提示且不杀 iex 会话                                      |

另：检查 `scoop-install`/`init` 的 `$LASTEXITCODE`，避免假报「安装完成」。

**勿再改回**裸 `throw` 或引导路径无条件 `exit 1`。

### `scripts/lib/utils.ps1`

- **`Write-ErrorAndExit`**：保持 `exit 1`（给 `-File` 子脚本用），与 `install.ps1` 故意分叉。
- **`Test-InteractivePrompt`**：stdin 重定向时探测 `CONIN$`，对齐 bash `/dev/tty`；勿再只靠 `IsInputRedirected`（会让管道安装无法交互选 lite/full）。
- **`Copy-FileDataOnly`**：仍用 `throw`（供 `Backup-File` 软失败 catch）。硬路径：`Move-Item`/`Copy-Item -ErrorAction Stop` + 目标存在校验。`Invoke-ManifestSync` catch → `Write-ErrorAndExit`。
- **勿**把库内 `throw` 改成 `Write-ErrorAndExit`（会破坏 Backup 软失败）。

### `scripts/lib/utils.sh`

- **`prompt_sync_direction`**：保持 `safe_echo ... >&2` + `return 1`；调用方 `direction=$(...) || exit 1`。
- **曾误改为 `error()`**：在 `$()` 里 `exit` 只杀子 shell；若再删掉 `|| exit 1` 会静默空 direction。已回滚，并加注释「不可用 error()」。
- **`safe_echo`**：`printf '%s\n'` + 日志 stderr / 数据 stdout——不要删、不要在 `$()` 数据路径打日志到 stdout。

### `scripts/windows/scoop-install.ps1`

- 旧：`$ErrorActionPreference=Stop` 无 catch → 堆栈；装完无 scoop/git 只 Warn → 配合 install 假成功。
- 新：try/catch → `Write-ErrorAndExit`；无 scoop / git 失败硬退出。

### `scripts/windows/clink-install.ps1`

- 旧：`try { git clone } catch`——原生 git 不 throw，catch 死代码，失败仍「下载完成」。
- 新：查 `$LASTEXITCODE`（对齐 `zsh-plugins-install.ps1`）；autorun 失败不再误报已启用。

### `scripts/windows/git-extras-install.ps1`

- 拆开校验 `rev-list` / `describe`，避免嵌套命令失败时错误信息含糊。

## 有意未改（软失败 / 既有契约）

- `Backup-File` / mkdir：失败 Warn 继续。
- `github-hosts`：更新失败 Warn。
- `config-sync*.ps1` / zsh-plugins 末尾 `$global:LASTEXITCODE = 0`：成功路径清码；软失败仍 0 是当前契约，改前先定产品语义。
- bash `run_config_sync` 对 `prompt_sync_direction` 用 `|| exit 1`（不是 `|| error`），避免与函数内已打印的 `[ERROR]` 叠字；函数内也不改用 `error()`。

## 常见错误补丁（review 时拒掉）

1. 「统一成 error()/Write-ErrorAndExit」而不看是否在 `$()` / iex。
2. 「去掉 try/catch，反正有 exit」——破坏软失败或 iex 会话。
3. 「用 try/catch 包 git clone」——原生命令要查 `$LASTEXITCODE`。
4. 为对齐 macOS `set -e` 而在 PS 引导脚本里无脑 `exit`。
