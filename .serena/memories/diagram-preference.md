SVG 规范存储在 `.serena/svg-specs.md`，已精简为当前项目通用规范。

## 主题（archify dual-theme SVG）
- 默认暗色：`:root, svg { dark vars }`；`--bg` = One Dark Pro `#282c34`，`--mask` = `#21252b`（侧栏色，描述标签底需与 bg 区分），`--grid` = `#21252b`
- 系统亮色：`@media (prefers-color-scheme: light) { :root, svg { light vars } }` — GitHub README 嵌入靠这个切换
- 手动覆盖：`svg[data-theme="light|dark"]` / `[data-theme="light|dark"]`
- 背景：`rect.c-bg-rect` + `fill: var(--bg)`，再叠 grid
- 颜色走 CSS 变量 + `.c-*` / `.t-*` / `.a-*`；光点 `fill` 可内联写死（绿#34d399 / 橙#f97316）

## 关键数值
- viewBox: `"10 0 780 {h}"` — 偏移 10px 右，宽度 780
- 外边框: `rect x="10" y="0" width="780" height="100%" stroke-width="3" rx="6"`
- 标题 x=30, Legend text x=770 — 距外边框内侧各 20px
- 分割线 y=52, 全宽 x1=0 x2=800, stroke-width=1.5
- diagram transform: `translate(0, 42)`
- viewBox 高度 = 42 + max(transform 内块 bottom) + 20

## 行间距（统一）
- **无描述**: gap=**40**（行间无水平总线标签）
- **有水平线描述**: gap=**56**（行间有水平汇聚/分发总线 + 边缘标签）
- 水平线默认 above≈16–20（从上一行 bottom 起算），标签在水平线上方 gap=6（rect.y=line.y-18）

## Header 区域
- 主标题 x=30 y=24, 14px bold, t-primary
- 副标题 x=30 y=40, 10px, t-muted
- Legend "Legend" x=770 y=19, 9px semibold, text-anchor=end
- Legend 子项 y=31, rect 14×9 rx=2, text-anchor=end, [text][4px][rect]
- 项间距 50px（两项时 70）, 右起: Security → Backend → Frontend
- 色值约定（四图统一，勿对调）:
  - **Frontend = 绿**: dark fill `rgba(6,78,59,0.4)` / stroke `#34d399`；light fill `rgba(52,211,153,0.18)` / stroke `#059669`
  - **Backend = 青**: dark fill `rgba(8,51,68,0.4)` / stroke `#22d3ee`；light fill `rgba(34,211,238,0.15)` / stroke `#0891b2`
  - **Security = 橙/玫**: dark stroke `#f97316`；light stroke `#e11d48`
  - 亮色主题曾出现 fill 对调（stroke 正确、fill 反了）；以 dark 语义 + dispatch-flow 为准，light/print 的 fill 必须与 stroke 同色系

## 块规范
- 每块两个 rect: 先 `c-mask`（透明遮罩，z-index 在后），后 `c-{role}` 带 `stroke-width="1.5"`
- 文字默认 `t-primary` 11px semibold，副文 `t-muted` 9px
- 标注用色（如 macOS/Windows 标签）: `t-frontend` 8px
- 块 rx=6, 中心块 160×56, 侧边块按内容自适应
- 虚线出口块: `dash-flow-box` + `stroke-dasharray="4,4"`（动画 offset -8）

## 连线
- stroke-width 1.2
- 分支 emphasis（绿 #34d399）, 汇聚 default（绿 #34d399）, 异常 security（橙 #f97316, 虚线 stroke-dasharray:5,5）
- 标签在线条上方 gap=6px（rect.y=line.y-18, text.y=rect.y+10）
- 标签色同步线条：绿=`t-frontend`, 橙=`t-security`

## 动画
- 光点 `<circle r="3" fill="#色值">` + `<animateMotion><mpath href="#id"/></animateMotion>`
- fill 内联写死（不通过 CSS）：绿线#34d399, 橙线#f97316
- 虚线（security）：CSS dash-flow + 橙色光点
