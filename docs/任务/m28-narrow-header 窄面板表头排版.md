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

## 主控审查（2026-09-24，首轮）

结论：修复下列标题完整性问题后再合并。审查对象为 `3c502ca`。

- 必须改：52 列、内容宽 50 时，合成任务标题为 `'X' * 25 + '\tEND'`（26/27 个 X 同样复现），原 task_heading 宽 48，四空格展开后宽 51。新 header 按展开副本绘制并截断，但 draw 判定是否补完整标题仍用未展开的宽度，导致翻完所有详情仍读不到完整标题。需先补临界宽度 RED，再仅修窄屏展示宽度判定；不改变 VM 或宽屏/矮屏。对同类展开/预算不一致做定向核对。
- 已独立通过：criteria、drover、install、drover-board 四个 shell 套件；其中包含 layout/header 测试。主控另录制 52×24、12 场景×单多项目的 24 组真实 PTY，全部通过，证据 `/private/tmp/drover-m28-review-pty/`。普通套件未覆盖上述 Tab 临界案例，不能据此认定信息完整。
- 视觉核对：看过 52 列单/多项目属性渲染拼图和 PTY 文本。接受深灰项目标识、蓝箭头、状态对齐、普通信息次级灰；告警优先导致项目名缩短、完整名在 Status 中的取舍符合已批准方案。Paused 沿用原模式位、loop 独立；宽屏 Tab 旧问题不在此次范围。底栏等其他区域不扩展。
- 生命周期：开发回复末行为 DONE、提交和记录已落盘，但 corral 随后仍报 working / ScheduleWakeup；返工 send 返回 not_idle，尚未送达。此时不合并、不删 worktree、不关闭 agent。
