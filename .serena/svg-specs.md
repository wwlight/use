# SVG 流程图规范

## 项目
`assets/install-flow.svg` — Use 一键安装流程
`assets/dispatch-flow.svg` — Use 命令分发流程

## 生成方式
```bash
# 1. 写 use.json（architecture 模式）
# 2. 渲染
node archify/bin/archify.mjs render architecture assets/use.json assets/use.html
# 3. 从 HTML 提取 SVG，清理
# 4. 添加 header 区域（title + legend + 分割线）
# 5. 将 diagram 主体包裹 <g transform="translate(0, 42)">
```

## 画布与边框

- viewBox: `"10 0 780 {height}"` — 偏移 10px 右，宽度 780
- 外边框: `<rect x="10" y="0" width="780" height="100%" stroke="var(--frontend-stroke)" stroke-width="3" rx="6" />`
- **所有可见内容距外边框内侧 20px**（viewBox 左=10 → 内容左=30；viewBox 右=790 → 内容右界=770；viewBox 底须留 20px padding）
- 背景 grid: `<rect x="10" y="0" width="780" height="100%" fill="url(#grid)" />`

## Header 区域（外边框内、分割线上方）

### 分割线
y=52，全宽 x1=0 x2=800，stroke="var(--frontend-stroke)" stroke-width=1.5

### 标题（左上角，距外边框左 20px）
- 主标题: x=30 y=24, 14px bold, class="t-primary"
- 副标题: x=30 y=40, 10px, class="t-muted"

### Legend（右上角，右对齐，距外边框右 20px）
- "Legend" 文字: x=770 y=19, 9px semibold, text-anchor="end"
- 子项水平排列，y=31，rect 14×9 rx=2，text-anchor="end"，格式 `[text][4px][rect]`
- 项间距（rect_right → next_rect_left）= 50px，每项 text x 比 rect x 小 4px
- 右起第一项（Security）rect 右边缘 = 770
- **SVG 代码顺序 = 视觉从左到右**：Frontend → Backend → Security
  （渲染在前的先写，Security 最后写保证在右端最上层）

### Legend 色值（默认约定）
| 角色 | 深色 fill | 深色 stroke | 浅色 fill | 浅色 stroke |
|------|-----------|-------------|-----------|-------------|
| Frontend | rgba(8,51,68,0.4) | #22d3ee | rgba(34,211,238,0.15) | #0891b2 |
| Backend  | rgba(6,78,59,0.4)  | #34d399  | rgba(52,211,153,0.18) | #059669 |
| Security | rgba(180,70,20,0.35) | #f97316 | rgba(249,115,22,0.15) | #e11d48 |

> dispatch-flow.svg 中 Frontend↔Backend 色值互换（Frontend=绿 #34d399, Backend=青 #22d3ee）

## Diagram 主体（分割线下方）

- 包裹在 `<g transform="translate(0, 42)">` 中
- 块、路径、标签全部用该 transform 内的坐标

### 行间距
- 主流程行间: 40px

### 块尺寸
- 中心节点: 160×56
- 侧边节点: 按内容自适应（110~150×56）

### viewBox 高度计算
viewBox height = 42 + max(transform 内所有块 bottom) + 20

## 连线
| 场景 | variant | 颜色 | 说明 |
|------|---------|------|------|
| 分支（中心→两侧） | emphasis | 绿 #34d399 |  |
| 汇聚（两侧→中心） | default | 绿 #34d399 |  |
| 异常退出 | security | 橙 #f97316 | 虚线 stroke-dasharray: 5,5 |

- stroke-width 统一 1.2

## 动画

### 实线（a-emphasis / a-default）
- **流动光点** `<circle r="3">` + `<animateMotion>`，通过 `<mpath href="#路径id"/>` 跟随路径
- 光点色值（内联 fill，不通过 CSS）：绿线 fill="#34d399"，橙线 fill="#f97316"
- 持续时间：短垂直路径 1.5s，水平短 2s，长/曲线 2.5s，汇聚长路径 3s

### 虚线（a-security）
- `stroke-dashoffset` 动画：`@keyframes dash-flow { to { stroke-dashoffset: -10; } }`
- path 上附加 `class="a-security dash-flow"`
- 仍然添加同色光点（`fill="#f97316"`）跟随路径运动

## 标签（水平线描述）
- 线条上方，gap=6px（rect.y = line.y - 20, text.y = rect.y + 10）
- 标签颜色与线条同步：绿线用 `t-frontend`，橙线用 `t-security`

## Q 曲线
- 拐角半径统一 8px
- 水平线在拐角前停止（距离 = 半径），切线方向与来向一致
- 禁止水平线越过拐角后折返

## 箭头颜色（SVG 直接替换）
- `m-default` / `m-emphasis` → `#34d399`
- `m-security` → `#f97316`

## 渲染后手动处理
1. 添加 header 区域：title + subtitle + legend + 分割线（y=52）
2. 将所有 diagram 内容包裹 `<g transform="translate(0, 42)">`
3. 替换 CSS var 为 hex 色值
4. 删除 HTML（仅保留 SVG）
5. 计算 viewBox 高度 = 42 + max(transform 内块 bottom) + 20
6. 确认 grid rect 和 border rect 带 x="10" width="780"
