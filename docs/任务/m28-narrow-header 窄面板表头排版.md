# 任务：窄面板三行 header 排版与配色

2026-09-24，主控 drover/main 委派给 drover/dev-narrow-header（Claude Code，常规档 opus[1m] / high；实例名以 corral start 返回为准）。
路由：常规 / 交叉审查不要（路由：常规 0.94，交叉审查不要；无推翻）
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

1. AGENTS.md、HANDOFF.md、README.md。
2. docs/ROADMAP.md「窄面板三行 header」及 T7、T12、显示细化、生命周期状态配色；docs/QUICKSTART.md 第 6 节。
3. bin/drover-board 的 draw、task_heading、task_metrics、颜色与文本宽度辅助函数；tests/board-layout.py、tests/board-demo.py。
4. 本任务文件。用图片读取工具看用户截图 `/Users/firegnu/Desktop/SCR-20260924-pwam.png`，只读查看，不拷入仓库。

## 工作目录和范围

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/m28-narrow-header`，分支 `m28-narrow-header`，从主控记录设计后的 main 建立。无需安装依赖，只用标准库和现有 `/opt/anaconda3/bin/python3`。
- 允许修改：`bin/drover-board`，必要的 header 定向测试（优先 `tests/board-layout.py`，需要时新增 `tests/board-header.py`）、`tests/board-demo.py` 的合成录制支持，以及本文件末尾完成记录。既有相关测试如确因旧 header 布局断言需更新，可最小调整并记录缘由，不删无关覆盖。
- 不改 HANDOFF.md、AGENTS.md、ROADMAP.md、QUICKSTART、bin/drover；不碰主仓库已有 HANDOFF 未提交更新，无其他开发任务并行。

## 要做的

按 ROADMAP 已批准方案实现。用户最后强调：「这个 header 一定要排版，配色一定要优雅。其他部分我觉得我暂时可以接受」。只改 header，不顺手改底栏、历史、正文或宽屏。

52 列空闲示意（示意不是死字符串，按实际列宽分配）：

```text
drover ▸ demo-shop 1/3          Manual · loop off
○ Queue empty
HEAD a1f3c2 · corral connected
──────────────────────────────────────────────────
```

- 20–99 列且 h>=12 时固定三行加分隔线；宽屏与 h<12 的既有布局保持。
- 去掉窄屏独立黄色项目切换行、相邻项目名，以及任务区重复的 Idle/添加提示。当前项目只在产品标识旁出现；单项目不显示 1/1。↑↓/jk 原映射不变，序号等要可理解。
- 优雅具体指：对齐、显示列宽预算、左右明确分工、灰色分隔符、蓝色箭头与模式、克制粗体、深灰选中底，避免黄条和整行同等强调。只有暂停/待处理用琥珀、错误用红。复用现有色板，不新增主题、配置或框架。
- 不丢信息：第一行优先保护异常、Paused、待处理数；Manual/模式与 loop 开关各保留，尤其 Paused 不能替代 loop。正常连接和 HEAD 可退让；当前任务的耗时/提交/main/路由等保持。所有受 header 排版影响而未完整显示的内容，在现有可翻页详情中提供完整展示副本，包括连接错误全文、模式、loop、项目全名、待处理数。不可只靠颜色表达状态。超窄时可以有明确的短标签，原文仍须可达。
- 保持默认逻辑文本与 VM 契约，优先仅在 draw 的展示副本中实现。不要为视觉去改状态逻辑或共享解析器。保留任务标题、正文和所有原始 Unicode，不修改 VM。

## 验证与交付

- 纯视觉任务不制造虚假 RED；先记录现有合成画面/相关检查，再实施。对去重、信息完整可达、优先级等新增显示契约添加自动检查，旧版预期失败要记录真实原因。
- 合成覆盖 20/32/40/52/80/99/100/120 列；空队列、有待办无进行中、进行中、待放行、暂停+loop on/off、连接失败+长错误+待处理、单多项目与无项目；长项目名/中英文/组合字符/Tab、少色和无色、来回缩放、全量详情翻页可达、VM 不变。
- 重跑相关看板 Python 测试及四个 shell 套件（criteria/drover/install/drover-board），使用 `/opt/anaconda3/bin` 优先 PATH，PYTHONDONTWRITEBYTECODE=1。不跑真实安装，仅 tests/install.sh 的临时 HOME 测试。
- 用真实 PTY 录制至少 52 列下空闲/进行中/待放行/暂停+连接异常、单多项目和缩放。交付 ANSI 与屏幕文本/属性证据到 `/private/tmp/drover-m28-*`，告知主控路径和查看方式；确保实际运行生产 draw，不能只交手写示意。对比宽屏与 header 之外内容保持（窄屏因少一行产生整体上移和多一行空间可接受）。
- 已知既有问题：board-history-pty.py 的旧中文「放弃：」断言、board-mouse-decode.py 不带 --record 的运行方式，别当本任务去修。若其他真实回归，先报告并处理本改动引起的部分。
- 主控会审查和重跑，给用户看结果。完成记录包含实现取舍、测试结果、证据路径和遗留限制。

## 禁止事项

- 不改或读取 corral 源码/内部状态，不改 corral-dispatch；不操作真实队列、done/go/next/loop、后台服务、launchd、PATH 安装、其他项目或旧 herdsman。
- 不合并 main、不推送、不清理分支/worktree、不关任何 agent、不按项目名批量杀进程。只在本分支提交允许的文件。
- 设计冲突或需要扩大范围时报告主控，不自行扩展。常规绘制细节可自行做最小取舍并记录。

## 回复

命令都在前台跑完。完成后提交本分支，回复概括改动、检查、视觉证据与需要决定的事项；最后一行写 DONE。

## 完成记录（drover/dev-narrow-header，2026-09-24）

### 改了什么

- `bin/drover-board`：新增 `narrow_header()`（及小工具 `joined()`），只在 draw 里用；20–99 列且 h>=12 时画三行 header + 分隔线，宽屏（>=100）和 h<12 走原路径。去掉窄屏黄色切换行、相邻项目预览；`task_heading`/`task_metrics`/`detail_sections`/`detail_lines`/VM 一字未动。`init_colors` 多两个色对 `chip`(默认前景/237 底)、`chip_dim`(245/237 底)，不加粗，只在 256 色可用。
  - 第一行：左 `drover`(粗) `▸`(蓝) 项目名(默认色) 序号(灰)，多项目时「▸ 项目 序号」落在深灰 237 底上（少色回退成无底色 + 蓝箭头，不反色）；单项目不显示 1/1。右：`! Needs you N`(琥珀) · `corral unavailable`(红) · 模式(`Manual` 蓝 / `Looping` 青 / `Paused` 琥珀) · `loop on`(绿)/`loop off`(灰，不加粗)，点号线条灰。
  - 宽度分配：先试全称、再试短标签（`!N`、`corral ✗`）与完整项目标识并排；不行就给左侧只留 `drover ▸ ` + 项目名前 5 格，先让出同义的常规模式词（Manual≡loop off、Looping≡loop on；Paused 不让），再从低优先级丢：待处理 > 连接异常 > Paused > loop 开关 > 常规模式词。内容区不足 32 列时，只有告警能挤掉项目名。
  - 第二行：有当前任务时沿用原标题（状态词着色、标题粗体）；否则只写 `○ Queue empty` / `○ No active task` / `○ No task queue` / `○ No registered projects`（蓝，不加粗），不再重复 Idle 和添加提示。
  - 第三行：进行中/待放行沿用原指标（Hold 琥珀），空闲为 `HEAD xxx`；正常连接放得下就接在后面（绿）。
  - 完整副本：项目全名/序号、模式与 loop、待处理数（全属当前项目时详情原有「Needs you · N」即副本，不重复）、连接错误全文、放不下的第二行，放在详情开头 `Status` 块；进行中标题/指标截断时沿用原有的详情开头副本；让出去的正常连接放详情末尾 `Connection` 块（不把正文往下挤）。全部放得下就不出现这些块。
- `tests/board-header.py`（新）：20/32/40/52/80/99 × 全部合成场景（新增 paused/alert/noqueue、长名+中英文+组合字符+Tab、无项目）× 单/多项目，翻完所有详情页（含正文/历史局部视口）核对：三行+分隔线、去重（无 Idle/press a/›/↑↓/jk/[ /1/1、无反色）、项目名只在第一行、第一行优先级单调、52 列以上告警与 loop 全在、全部原文可达、VM 不变；100/120 列与 h<12 仍是旧顶栏；52 列空闲示意三行逐字；256/8/无色三档配色；52→120→20→40x10→99→52 缩放后与新画一帧一致。已接进 `board-layout.py` 末尾，所以 `tests/drover-board.sh` 会跑它。
- `tests/board-layout.py`：三处写死旧窄屏 header 的断言改为新 header：80 列空闲标题 `○ Idle`→`○ No active task`(蓝)；40 列历史用例 `○ Idle` 粗体 → 第二行 `○ Queue empty`；多项目 `[1/3]` 在第 1 行 → `1/3` 在第 0 行。其余覆盖不删。
- `tests/board-demo.py`：新增 paused / alert（暂停 + loop on + 长连接错误 + 待处理）/ noqueue 场景；`--sizes` 录制尺寸参数（默认不变）；缩放步骤加两次 52x24；`--capture` 时额外写 `.attrs.json`（代理 addstr 记录生产 draw 实际下发的属性——inch 对非 ASCII 字符会把码位漏进色对位，不可靠）。

### 检查

- RED（旧版跑新测试）：`DROVER_BOARD_BIN=<HEAD 版> tests/board-header.py` 在 working/20 列首个断言失败：`corral connected (synthetic)` 在 header 和详情里都读不到。旧版全量探查（新场景 × 6 宽度 × 单多项目）：连接文字不可达 92 帧、`Needs you` 不可达 77 帧、项目全名不可达 20 帧、连接错误全文不可达 16 帧；header 里重复 `Idle` 66 帧、`press a` 18 帧、`›` 相邻项目 61 帧、黄色反色条 78 帧。新版全部为 0。
- GREEN（/opt/anaconda3/bin 优先，PYTHONDONTWRITEBYTECODE=1）：board-header、board-layout、board-body-scroll(10)、board-history(13)、check-result(21)、list-output、board-body-pty、board-tab-pty、board-mouse-decode --record 通过；criteria.sh、drover.sh、install.sh(临时 HOME)、drover-board.sh 通过。
- 已知旧问题照旧失败、未修：board-history-pty.py 找中文「放弃：」；board-mouse-decode.py 不带 --record 断言失败。
- 前后逐帧（合成 Screen，12 场景 × 单多 × 11 尺寸，每帧翻完所有页）：宽屏 72 组、h<12 的 48 组与改动前完全一致；窄屏 144 组全部不同，差异只在 header、去掉的空闲重复提示、新增 Status/Connection 副本，以及随之移动的分页/历史局部视口边界。
- 真实 PTY：`board-demo.py --record` 默认 48 组 + 窄屏 168 组（52/20/32/40/80/99/100 × 12 场景 × 单多）全部 PASS。

### 证据

`/private/tmp/drover-m28-evidence/README.md` 写了全部路径和查看方式。要点：`/private/tmp/drover-m28-narrow/<场景>-<single|multi>-52x24/terminal.ansi`（调到 52x24 后 `cat`）、同目录 `.txt` 屏幕文本和 `.attrs.json` 属性；`/private/tmp/drover-m28-evidence/sheet-52-{single,multi}.png` 为 52 列八场景拼图；改动前录制在 `/private/tmp/drover-m28-before/`。

### 取舍与遗留

- Paused 时模式位显示 `Paused`（同宽屏原规则），loop 开关始终独立一项；Paused 不替代 loop。常规模式词和 loop 开关同义，是第一行最先让出的一项，原文在 Status 块。
- 短标签 `!N`、`corral ✗` 带符号和数字，不只靠颜色；原文都在 Status 块。
- 52 列下告警全亮时（待处理+连接异常+Paused+loop），项目名截到 `demo-s…`，全名在 Status 块。
- 宽屏顶栏的项目名 Tab 原本就没展开（旧行为，不在本任务范围），新测试只断言窄屏 header 无 Tab。
- 用户常用终端的实际观感待用户目视。
