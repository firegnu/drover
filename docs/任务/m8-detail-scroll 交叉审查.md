# 交叉审查：TUI 详情区翻页滚动

2026-09-21，drover/main 交给 drover/review-detail-scroll（Codex，重档：`-m gpt-6-astra -c 'model_reasoning_effort="xhigh"'`）。
你是被委派的审查者：只读审查，照本文件做，不要再开别的 agent。

## 背景

`bin/drover-board` 是 drover 的 curses 看板。右边详情区原先**超出窗口高度就截断**，末行写「… 还有 N 行，窗口再高些」，队列一长就不够用。`drover/dev-detail-scroll-1` 在 `m8-detail-scroll` 分支上给它加了翻页。

这件活的设计张力写在原任务书里，是它唯一需要拿主意的地方：

> `key_action` 是纯函数、`draw()` 只排版没有判断（ROADMAP 写死的不变量）。但滚动要夹住边界，就得知道「详情一共几行」和「一屏放得下几行」——**这两个数只有 `draw()` 拿到窗口尺寸之后才知道**。

它选的方案：抽出纯函数 `detail_viewport(total, room, offset, pages)` 统一算夹限和翻页；`draw()` 每帧把项目身份 / 行数 / 可视高度 / 归一后的偏移写回进程内 `state`；`key_action()` 读这些值算新偏移，保持纯函数。被否掉的两条（夹限埋进 `draw()`、由 `tui()` 算）它写了理由。

**主控已经审过的，不必重复**：

- 范围只动了 `bin/drover-board`、`tests/drover-board.sh`、任务文件；`draw` / `key_action` 签名没变；没加配置项、没落盘、没碰 `detail_lines()` 的内容、没动那 21 个被依赖的数据函数。
- 四个套件我自己重跑全绿（`drover-board` 从 10 块到 13）。
- **我往实现里植入了三个缺陷验证测试不是空转**：翻页不动 → 红；提示行盖到正文 → 红；**切项目不归零 → 当时照样绿**。第三条是我打回返工的原因：它原先两条「切项目归零」的断言都切到 `short_pv`（`queue: None`，详情只有两行），`limit` 算出来是 0，**任何偏移都会被夹限顺带压成 0**，断言分不出是归零逻辑起作用还是夹限压平的。返工提交 `65aa0d1` 补了等长项目（`equal_pv`）的断言，我重新植入同一个缺陷，这次确实红了。

所以**测试有效性这一项我已经用植入法查过**，请把力气放在下面「重点看」。

## 先读

1. `AGENTS.md`（「硬规矩」「技术约束」「测试」三节）
2. `docs/ROADMAP.md` D1 第 5 步第 3 小节（看板改 TUI 那段），特别是两句不变量：「不存自己的状态，刷新等于重跑」、`key_action` 纯函数 / `draw()` 只排版
3. `/Users/firegnu/Developer/personal_projs/drover/docs/任务/m8-detail-scroll 详情区滚动.md`（原任务书 + 实现时的取舍 + 完成记录）
4. 本文件

## 要审查的代码

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/review-m8-detail-scroll`（**detached HEAD**，指向被审提交 `65aa0d1`）。这是你自己的 worktree，dev agent 在另一个目录，别去碰它。
- 改动：在该 worktree 里跑 `git diff main...HEAD`。三个文件：`bin/drover-board`、`tests/drover-board.sh`、任务文件。
- **只读：不改、不提交、不切分支、不合并、不推送。** 要试验就在 `$(mktemp -d)` 里造合成数据，把 `bin/drover-board` 当模块 import 来跑（`tests/drover-board.sh` 里有现成写法；注意手搓 `pv` 会和真结构走散，用 `view_model` 造）。
- 可以跑：`bash tests/criteria.sh`、`tests/drover.sh`、`tests/install.sh`、`tests/drover-board.sh`（只用合成仓库和假 corral，不花钱）。
- **不能碰**：真的 `~/Developer/personal_projs/jb-finetune`、`~/.review/`、`~/wt/`、herdr、`dev.herdsman.*` 的 launchd 任务、`~/.local/bin/` 里那六个老命令、`~/.config/review/`。不要 `launchctl` 任何东西，不要往 `~/.local/bin` 拷东西。也不要碰靶场 `drover-sandbox`。
- **不要动真的交接目录** `~/.drover/`：看板默认会读 `~/.drover/projects`，要跑真界面就用 `--projects` 指向你自己造的清单。
- 不要按项目名或路径批量杀进程（`pkill -f drover` 这类）：主控和别的 agent 的命令行里都带着项目名和工作目录，一条命令能全杀掉。

## 重点看

1. **`draw()` 每帧写 `state` 这个耦合有没有失效的窗口。** `key_action` 读的是上一帧 `draw` 留下的 `detail_total` / `detail_room` / `detail_offset`。第一帧之前、窗口刚 resize、`tui()` 里 `refresh` 之后重新 `collect` 导致行数突变、连按两次翻页键之间没有重画——这些时刻读到的是不是陈旧值？会不会算出越界或者「翻了但没动」的偏移？
2. **`detail_viewport` 的边界算术**。`page = max(0, room - (1 if total > room else 0))`、`limit = max(0, total - page) if page else 0`。请自己枚举临界组合（`total == room`、`total == room + 1`、`room == 0`、`room == 1`、`total == 0`），看有没有：翻不动、跳过行、重复显示某一行、或者最后一页显示不满却还说能往下翻。
3. **提示行和正文会不会打架**。正文画在 `top + i`（`top = 2`），提示行固定画在 `bot`（`h - 2`）。`shown = lines[offset:offset + page]`。请验证任何 `h`（尤其 `h = 5`、`h = 6`）下提示行都不会盖住正文最后一行、也不会留下空行；窄屏 `rail = 0` 和有侧栏两条路都要看。
4. **切项目归零用 `repo` 做身份** 够不够。项目列表增删、重排、`sel` 越界被夹、同一个 `repo` 出现两次、`ps` 为空（`project = None`）这些情形下，归零和沿用分别对不对。注意 `ps` 为空时 `project` 是 `None`，而 `state` 初始也没有 `detail_project`——这两个 `None` 撞在一起有没有问题。
5. **中文宽度**。详情行里有中文（任务标题）。翻页之后 `put()` / `trunc()` 的宽度计算还对吗？提示行 `PgUp↑N PgDn↓N` 在窄屏（20 列）下会不会被截断成看不懂、或者越界。
6. **有没有把 UI 状态漏到进程外**。硬约束是「看板不存自己的状态，刷新等于重跑」。请确认偏移只活在 `state` 字典里，没有写文件、没有进环境变量、`REFRESH_MS` 的语义没被改。
7. **测试本身还有没有别的「夹限顺带让断言通过」的假绿点**。上面背景里那个洞是我用植入法抓到的；同一类问题可能还在别处（比如某条断言期望的 0 或边界值，其实无论实现对错都成立）。挑你觉得可疑的，用植入法自己验一遍。

## 输出

追加到**本文件**末尾「## 审查意见」。用绝对路径写：`/Users/firegnu/Developer/personal_projs/drover/docs/任务/m8-detail-scroll 交叉审查.md`——它在**主仓库工作区**里，不在你的 worktree 里；**只写这一个文件，别的什么都不要改**。

先写一句结论（**可以合并** / **改完再合并**），然后每条意见写：级别（必须改 / 建议改 / 可以不改）、位置（文件:行）、问题、改法。最后对完成记录里「实现时的取舍」那四条逐条表态（同意 / 不同意 + 理由）。

## 回复

只写结论和各级别的条数。全部做完后，回复最后一行写 DONE。
