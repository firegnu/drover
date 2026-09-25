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
