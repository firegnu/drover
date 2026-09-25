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

## 完成记录（drover/dev-pending-page，2026-09-25）

- 按已定四项取舍实现：`u` 进入；只认正文显式的「任务文件：」行；只用 PgUp/PgDn 翻页；`?` 帮助页加 `u  View pending tasks and their task files`，看板底栏加 `u Up next`。
- 数据：`queue_vm` 的每件待办多带 `body`（行列表）和 `task_file`（`{path, text}`，找不到时 `text` 为 None，没写那一行为 None）。任务单只读、相对仓库解析，读在 view_model 层，draw 只排版。
- 界面：`draw_pending` 整屏覆盖，顶栏 `Up next i/n · ▸ Next · 编号 标题 · Hold`，下面 `Queue entry` 正文，有引用时接 `Task file · <路径>` 全文或 `Task file not found: <路径>`；窗口太小显示 `Window too small`。
- 按键：详情页里 ↑↓/jk 换一件（到头不动），PgUp/PgDn 翻页，Esc 返回；g/n/p/a/l/u/? 和鼠标都不生效，r / 自动刷新 / q 照常。只写自己的 `pending_*` 状态，项目选择和各处滚动位置不变。正在看的那件按编号（没编号按标题）记住，刷新后没了就停在原序号。没有待办时按 `u` 不打开，消息栏显示 `No pending tasks`。
- 验证：新增 `tests/board-pending.py`，先 RED（`queue_vm` 待办没有 `body`），实现后 GREEN。回归 `bash tests/drover.sh`、`python3 tests/board-header.py`、`python3 tests/board-help.py` 各一次全部通过，`git diff --check` 通过。没有运行 `tests/drover-board.sh`、`tests/board-layout.py` 等会录屏的入口，没有录屏。
- 只改了 `bin/drover-board`、新增 `tests/board-pending.py` 和本文件；没动 HANDOFF、ROADMAP、QUICKSTART、队列推进、判据、引擎或 corral。

## 返工记录（drover/dev-pending-page，2026-09-25）

- 修主控审查的必须项：同名未编号的两件待办，选中第二件后再重绘会跳回第一件（`keys.index` 总取第一个重名）。
- 最小修复：`draw_pending` 先看原序号上那件的 key 还是不是记住的 key，是就不动；不是（刷新后顺序变了）才按 key 找，找不到仍停在原序号。队列语义和其他功能不变。
- `tests/board-pending.py` 加回归：两件 `id=""`、`title="same title"`，正文 first/second，`pending_sel=1` 连调两次 `draw_pending`，修复前第二次变成 0（RED），修复后两次都停在第二件并显示 second（GREEN）。
- 返工验证只跑了 `python3 tests/board-pending.py` 和 `git diff --check`，都通过；没有重跑 CLI/header/help，没有录屏。

## 主控审查

- 通过。首轮 `56b0aa2` 核对四条验收与范围，CLI/header/help 三项主控回归均退出码 0；定向发现同名未编号待办切换后重绘跳回第一件，按第一条验收交回修复。
- 复核 `2461b97` 仅看返工差异：保留原位置优先的修复正确，新增回归明确检查第二件正文。主控运行 `python3 tests/board-pending.py` 和 `git diff --check 56b0aa2..HEAD` 通过，未重跑其他回归、未录屏。
- 同意复用现有整屏与翻页交互、显式引用全文展示、缺文件提示、无待办提示及刷新后原序号回退的取舍；帮助页与底栏均已加 u。四项用户取舍没有改变，未扩展队列推进或完成判据。
- 已本地合并，随后清理开发 worktree/分支及自开 agent，打收尾记号。未推送、未操作真实任务推进、loop、服务或安装；等待用户目视与放行。
