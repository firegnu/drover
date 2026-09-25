# T22：待办详情页实现

2026-09-25，主控 drover/main 委派给新开的 drover/dev-pending-page（名称以 corral start 返回为准），Claude Code 常规档：opus[1m] / high。四项取舍已定。
路由：常规 / 交叉审查不要 / 影响面：改行为（路由：tier 常规，cross_review 不要，impact 改行为；模型 jev-1.13.0；无推翻）
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 目标
按 m32 的方案实现待办详情页

## 先读

- AGENTS.md；`docs/任务/m32-pending-details 队列待办详情交互设计.md` 的方案。
- `bin/drover-board` 的待办数据、绘制、按键处理与帮助页。

## 范围

- 待办详情页的数据与界面、帮助页和底栏提示、直接相关测试及本文件完成记录。
- 已定取舍：u 进入；只认正文显式引用；只用 PgUp/PgDn 翻页；帮助页和底栏均加 u 提示。

## 怎么算做完
- 看板按 u 打开待办详情整屏页，↑↓/jk 切换待办，Esc 返回，项目选择和滚动位置不变。
- 显示待办正文；正文写了「任务文件：<路径>」的，接着显示任务单全文，找不到显示 Task file not found。
- PgUp/PgDn 翻页；详情页里 g/n/p/a/l 等操作键不触发队列操作。
- ? 帮助页加一行 u，底栏也加 u 的提示。

## 执行与边界

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/m33-pending-details`；分支：`m33-pending-details`，从 main 创建。无需安装依赖。
- 只改 `bin/drover-board`、直接相关测试及本文件完成记录；不改其他任务文件、HANDOFF、ROADMAP 或 QUICKSTART。
- 验证预算：定向入口 `python3 tests/board-pending.py` 先 RED 后 GREEN；标准回归 `bash tests/drover.sh`、`python3 tests/board-header.py`、`python3 tests/board-help.py` 各一次，加 `git diff --check`。预算不足时在回复中报告，不自行扩大。
- 不运行会间接录屏的 `tests/drover-board.sh`、`tests/board-layout.py` 等入口，不做覆盖矩阵或缺陷注入；m32 的验证建议仅参考，以本任务预算为准。
- 行为改动先 RED 后 GREEN；使用合成数据和轻量检查，不录屏，不间接运行会录屏的测试。
- 不改队列推进、完成判据、引擎或 corral / corral-dispatch；不操作真实队列推进、loop、服务、安装或其他项目，不推送。
- 被委派的 agent 不再委派，不合并 main；只在自己的分支提交，并在本文件追加完成记录。主控按项目规则审查、本地合并与收尾，做完等用户放行。

命令都在前台跑完，全部做完后，回复最后一行写 DONE。
