# 任务：看板增加快捷键帮助页

2026-09-25，主控 drover/main 委派给新开的 drover/dev-keyboard-help（名称以 corral start 返回为准），Claude Code 常规档：opus[1m] / high。
路由：常规 / 交叉审查不要 / 影响面：改行为（路由：tier 常规，cross_review 不要，impact 改行为；模型 jev-1.13.0；无推翻）
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 目标

用户在看板中按 `?`，即可查看现有快捷键和滚动操作说明，不必离开终端查文档。

## 范围

- `bin/drover-board` 的绘制与输入处理、直接相关的轻量测试。
- 沿用英文界面、深色和沙色强调，不重做现有页面布局。

## 怎么算做完

- 按 ? 显示现有快捷键、用途和滚动操作说明。
- 按 Esc 返回，原来的项目选择和滚动位置不变。
- 帮助页打开时，g/n/p 等操作键不触发队列操作。
- 沿用当前英文界面和沙色风格，窄终端也能读全。

## 执行安排

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/m30-keyboard-help`；分支：`m30-keyboard-help`，从 main 创建。
- 先读 AGENTS.md，以及 `bin/drover-board` 的 draw、key_action、tui 和 `tests/board-header.py` 的轻量屏幕用法。
- 只改 `bin/drover-board`、直接相关的轻量测试及本文件完成记录，不改 QUICKSTART、ROADMAP、HANDOFF 或其他任务文件。
- 验证预算：新增一条定向测试入口 `python3 tests/board-help.py`，先确认因缺少目标行为而 RED，再实现到 GREEN；标准回归运行一次 `bash tests/drover.sh` 和一次 `python3 tests/board-header.py`，另做 `git diff --check`。预算不足时在回复中报告，不自行扩大。
- 不做 PTY 录屏、截图拼图、覆盖矩阵或缺陷注入；不运行会间接录屏的 `tests/drover-board.sh`、`tests/board-layout.py` 等入口。
- 不需要安装依赖；只用 Python 标准库。完成记录写做了什么、验证结果、取舍和未做事项。

## 边界

- 不改队列语义、完成判据、引擎、corral 或 corral-dispatch，不新增快捷键所对应的业务功能。
- 不操作真实队列推进、服务、安装或其他项目，不推送。
- 与 `m31-list-json` 是两件独立任务，各自触发、验收和收尾；共享文档如有改动，后执行者基于最新 main 接续。
- 开发 agent 不再委派，不合并 main；只在自己的分支提交，并在本文件追加完成记录。主控依项目规则审查、本地合并和收尾。

命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 完成记录（drover/dev-keyboard-help，2026-09-25）

**做了什么**（只改 `bin/drover-board`，新增 `tests/board-help.py`）

- 按 `?` 进入整屏帮助页：标题 `Keyboard help`，`Keys` 一节列出 ↑↓/jk、g、n、p、a、l、r、?、Esc、q 及用途；`Scrolling` 一节说明 PgUp/PgDn 翻详情、鼠标滚轮在正文/历史区域按 3 行滚动。底栏 `Esc Back`。
- `Esc` 或再按 `?` 返回。帮助页只写 `help_*` 状态，`draw` 进帮助页时直接返回，不碰 `sel`、`detail_offset`、正文/历史偏移，所以返回后画面与打开前逐格一致。
- 帮助页打开时 `key_action` 只认 Esc/?、PgUp/PgDn（翻帮助页）、r/超时/缩放（刷新）和 q（退出）；g/n/p/a/l、j/k/↑↓、鼠标一律不产生动作。
- 配色沿用现有样式：标题、节名 `h2`，按键 `key`（沙色加粗），说明 `bar`，分隔线 `line`，没有反色。窄屏时说明悬挂换行；再窄就改成按键一行、说明缩进另起；一屏放不下时 PgUp/PgDn 翻页，带位置条和 `PgUp↑ PgDn↓` 提示。
- `tui` 启动时 `set_escdelay(25)`（有这个函数时），不然 Esc 要等 1 秒才生效。

**验证**

- `python3 tests/board-help.py`：实现前 RED（`key_action('?')` 没有返回 `('help', True)`）；实现后 GREEN。覆盖纯按键层；用假屏幕驱动真实 `tui()`：选第二个项目、翻一页 → ? → 连按 gnpaljk/↑↓/PgUp/PgDn/超时 → Esc，`run_drover`/`edit_queue` 一次都没调，返回后的画面与打开前完全相同；20–120 列、8–32 行共 9 种尺寸下翻完帮助页，检查全部说明可读、按键为沙色、无反色。
- 回归：`bash tests/drover.sh` 通过；`python3 tests/board-header.py` 通过；`git diff --check` 通过。
- 途中两次失败都出在测试自身，已改测试：打桩的 `init_colors` 递归调用了自己；前置断言没考虑 `billing-api` 和 `2/3` 是分两次写屏的。另外有一条调试命令因多写了一个空 `cat` 挂起，已停掉，没有影响。

**取舍与未做**

- 底栏按键提示和启动消息 `HELP` 里没有加 `? Help`：验收没要求，加了会改现有底栏布局。要不要加，由主控/用户决定。
- 没改 QUICKSTART、ROADMAP、HANDOFF。没有运行 `tests/drover-board.sh`、`tests/board-layout.py`，没有录屏。实际终端观感待用户目视。

## 主控审查

- 通过。核对 `6dd2b5e` 的实现、定向测试与完成记录，四条用户原话验收均落实；只改绘制/输入、轻量测试及本任务记录，未扩展业务逻辑或产品文档。
- 主控重跑 `bash tests/drover.sh`、`python3 tests/board-header.py` 均通过，`git diff --check main...m30-keyboard-help` 通过；开发侧定向测试的 RED/GREEN 记录与测试内容一致。本次无交叉审查，不录屏、不额外跑套件。
- 同意整屏帮助、独立帮助页翻页、Esc/? 返回、保留 q 退出及缩短 Esc 等待的取舍。接受底栏暂不加 `? Help`；入口可发现性作为后续建议，不扩大本任务。真实终端观感由用户目视。
- 已本地合并；随后清理该分支/worktree 和自开的开发 agent，打收尾记号。未推送，未操作真实任务推进、loop、服务或安装；等待用户放行。
