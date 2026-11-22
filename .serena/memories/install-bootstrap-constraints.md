# install.sh / install.ps1 bootstrap 限制

## 入口形态

- macOS: `curl -fsSL .../install.sh | bash`（及 `bash -s -- lite|full`）
- Windows: `irm .../install.ps1 | iex`（及 `$env:USE_PROFILE=lite|full`）

此时只有安装脚本本身在跑，本地还没有仓库，读不到 `manifests/`、`src/`、`runtime/`。

## 顺序

两边相同：

1. 解析 help / `lite|full`（脚本内写死）。
2. 准备 Node.js >= 18（没有则走 vite-plus）。这一步在拉仓库之前。
3. 拉仓库：先 zip，失败再 `git clone`。全新安装不要求本机已有 Git；更新已有检出才要求 Git。
4. 进入检出后执行 `node src/cli.js pm`，再执行 `node src/cli.js init`。`pm` 已部署过的 helper 不进入随后的 config sync（`USE_INSTALLER=1`）。

Windows 的 Scoop 安装发生在第 4 步，由 `src/pm/scoop` 调用 `runtime/scoop/bootstrap/entry.ps1`。macOS 的 Homebrew 同样在第 4 步，由 `src/pm/brew` 完成。引导脚本本身不在克隆前安装 Scoop 或 Git。

## 规则

1. **仓库落地之前**（usage、参数解析、`resolve_profile` / `$InstallProfile`、加速前缀、Node、zip/git 拉取）：必须自包含。不要读 manifest，也不要调用 `src/` 或 `runtime/`。
2. **profile id 有两处，标签只有一处。** `lite` 和 `full` 在引导脚本里写死，因为那时还没有 `manifests/common.json`。菜单和 `vpr init` 的中文标签只来自该文件的 `profiles`。包列表路径在 `manifests/macos.json` 与 `manifests/windows.json` 的 `profileArtifacts`。新增 id 时三处一起改。引导脚本的 help 保持静态英文，不要在 `curl|bash` / `irm|iex` 下动态读 manifest 再回退。
3. **不要恢复 install 与 init 共用的步数计数。** `USE_STEP_*` 和 `initStepCount` 已删除。`src/commands/init.js` 里的 `step()` 只是日志。
4. **仓库落地之后**只通过 `node <checkout>/src/cli.js` 进入后续命令。没有 `scripts/**`、`init.sh`、`init.ps1`。
5. **Windows 一键安装传 `init <profile>`，不传 `--`。** PowerShell 5.1 会吃掉 `.ps1` shim 上的裸 `--`。`install.ps1` 的 `Invoke-UseCli` 会丢掉 `--`，并优先调用 `node.exe`。macOS 传 `init -- <profile>`。`src/core/args.js` 两边都能解析，不要改成只接受其中一种。
