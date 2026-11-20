# SVG 资产修改记录

## assets/install-flow.svg

- 添加 Google Fonts 引入 (JetBrains Mono)
- `install.sh / install.ps1` 文本拆为上下两行
- `clone use-&lt;date&gt;` 改名 (原 `clone [use-timestamp]`)
- 底部 4 个块 (brew-install/scoop-install/init.sh/init.ps1) 宽度 140→175，距容器边缘 20px，中心 100/700
- 底部 4 个块相关箭头路径 (ip10/ip11/ip12/ip13) 更新

## assets/dispatch-flow.svg

- 添加 Google Fonts 引入 (JetBrains Mono)
- `pm → brew-install` 块加宽 10 (160→170)
- `pm → scoop-install` 块加宽 10 (160→170)
- `zsh-plugin / git-setup` 块加宽 10 (170→180)
- `zsh / git-extras / clink / hosts` 块加宽 20 (210→230)
- 箭头 dp2/dp3 同步

## assets/init-flow.svg

- 添加 Google Fonts 引入 (JetBrains Mono)
- `scoop_backup.lite.json` 加宽 20 (150→170)，后左移 20 再右移 5，中心最终 525
- 关联箭头 (vp9/vp14) 和标签 (lite) 同步
- `交互选择` 块左移 10，关联箭头 (vp7/vp8/vp13) 和标签 (省略) 同步

## assets/sync-flow.svg

- 添加 Google Fonts 引入 (JetBrains Mono)
- `仓库 → 本地配置` 块改为虚线边框 (dash-flow-box + stroke-dasharray)

## 全局虚线边框修正

- 所有 dash-flow-box 的 stroke-width 从 1.5 改为 2，视觉上匹配实线框
- 实线框保持 stroke-width=1.5

## 亮色主题 frontend/backend fill 对齐（2026-07-19）

- 问题：init / install / sync 的 light（及 print）里 `--frontend-fill` 与 `--backend-fill` 对调；stroke 正确
- 正确：Frontend 绿 fill `rgba(52,211,153,0.18)`；Backend 青 fill `rgba(34,211,238,0.15)`
- dispatch-flow 原本正确未改；其余三图 light + print 已对齐
- 色值约定见 `mem:diagram-preference`

## header-mask 主题对调（2026-07-19）

- 正确：**dark** 用头部遮罩盖住网格；**light / print** 不用
- dark / data-theme dark：`--header-mask: rgba(33, 37, 43, 0.92)`（对齐 `--mask`/`--grid` `#21252b`）
- light media、data-theme light、print：`--header-mask: transparent`
- 四图均已更新：install / init / dispatch / sync
