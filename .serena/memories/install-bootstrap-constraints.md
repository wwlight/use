# install.sh / install.ps1 bootstrap 限制

## 入口形态

- macOS: `curl -fsSL .../install.sh | bash`（及 `bash -s -- lite|full`）
- Windows: `irm .../install.ps1 | iex`（及 `$env:USE_PROFILE=...`）

此时**只有安装脚本本身在跑**，本地还没有仓库，也读不到 `scripts/**/_manifest.json`。

## 规则

1. **clone 之前**（usage/help、参数解析、`resolve_profile`）：必须自包含。不要依赖仓内 manifest 或其它脚本；文案与 `lite|full` 写在脚本内即可。
2. **`ensure_repo` / clone 之后**：可以读 manifest、调用 `scripts/...` 子脚本——这与后续 `init` / `brew-install` 同一前提。
3. **不要为了「与 init 同步」把 `initStepCount` 抽进 manifest**：`install` 主路径若继续硬编码步数，单侧提取无法防漂移；用注释约定两边的 `4` 即可。
4. **profiles 标签的单一来源**留给仓内脚本（如 `init.sh` / `init.ps1` 读 `common/_manifest.json` 的 `profiles`）；bootstrap 的 help 保持静态，避免 curl/iex 下无效的动态读取 + 回退双轨。

## 对照

| 阶段                             | 可否读仓内文件 |
| -------------------------------- | -------------- |
| help / 参数                      | 否（通常）     |
| clone 后 install_macos / 调 init | 是             |
