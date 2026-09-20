# 任务：把 HTML 看板整层重写成 curses TUI

2026-09-20，drover/main 交给 drover/dev-tui（Claude Code，重档：`--model 'opus[1m]' --effort xhigh`）。
路由：重 / 交叉审查不要（路由：档=重，交叉审查=拿不准；推翻：交叉审查一项路由拿不准，主控定为不要——这件活出错立刻看得见，而且验收全打在 view_model 的纯数据上，测试兜得住）。
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

1. `AGENTS.md` —— 尤其「硬规矩」「绝对不许碰」两节。**本机上还跑着老 herdsman 在推一个真实项目，那张表里的东西一个字节都不能动。**
2. `docs/ROADMAP.md` 的「看板」一节 —— 这件活的设计全在那里，包括为什么做 TUI 而不是网页、留什么删什么、测试怎么写、中文宽度怎么办。**照它做，别另起炉灶。**
3. `bin/drover-board`（1600 行）和 `tests/drover-board.sh`（15 块断言）。
4. `bin/drover` —— 它 `import` drover-board 当模块用（`B = load_board()`），`drover board …` 也转给它。
5. 本文件。

## 你在哪里干活

- worktree：`../drover-worktrees/m5-tui`，分支 `m5-tui`（已从 main 建好）。只在这里改。
- 只动 `bin/drover-board`、`tests/drover-board.sh`、`tests/browser-smoke.mjs`（删掉）、以及 `bin/drover` 里和通知有关的那一点。
- 不用装依赖：**只用 Python 标准库**，不许装第三方包。
- 同时在做的还有 `drover/dev-install`，在分支 `m5-install` 上，只动新建的 `install.sh` 和 `launchd/` 下的 plist。**你不要碰那两处**，它也不会碰你的文件。

## 要做的

### 1. `bin/drover-board` 一分为二，但仍是同一个文件

这个文件现在同时是三样东西：**数据模块**（`bin/drover` 和三个测试都 import 它）、**HTML 渲染器**、**HTTP 服务**。

- **数据模块那部分原样留着，函数名和返回值都不许改**：`collect` / `discover` / `parse_conf` / `criteria` / `find_done_mark` / `milestone_branches` / `run_check` / `task_blocks` / `task_events` / `task_fold` / `task_pending` / `task_check_cmd` / `task_view` / `wants_human` / `agents_of` / `corral*` / `loop_tick` / `close_if_done` / `read` / `mtime` / `ago` / `git`。**`bin/drover` 和 `tests/criteria.sh` 靠它们活着，改了就全塌。**
- **HTML / CSS / JS / HTTP 服务整块删掉**：`CSS`、`DRAWER`、`LIVE_DIALOG`、`LIVE_EDITOR`、页面 JS、`render*`、`cmd_serve`、`live_action`、令牌、Host/Origin 校验、`/v` `/health` `/history` `/api/*` 全部。`tests/browser-smoke.mjs` 一起删。
- 换成 curses TUI：`drover board` 就是打开它。

### 2. `view_model()` / `draw()` 两层

```python
def view_model(projects) -> dict     # 纯数据：要显示什么。不碰 curses
def draw(stdscr, vm, state)          # 只负责画。薄到几乎没有判断
```

**验收全部打在 `view_model()` 返回的字典上**，不 grep 画面。ROADMAP 原话：「断言全打在这个纯数据上，比 grep HTML 更结实（不会因为换个类名就挂）」。

### 3. 界面内容

从上到下（ROADMAP 定的，agent 那几块已经在 `f03efec` 删掉了，别加回来）：

1. 顶栏：项目名、健康提示
2. 「等你」：每条带 `corral attach <名字>`（只是给人抄的一句话，drover 自己不跑 attach）
3. **当前这件活**：分支进展（main 上几个提交、最后一次多久前）、完成判据过了几条（**依据「收尾记号」排最前**，见 `find_done_mark`）
4. 队列
5. 做完的

左边项目列表，右边详情；上下键选项目。

### 4. 按键

ROADMAP：「**推进靠按键，不靠敲命令**」。至少要有：

| 键 | 做什么 |
|---|---|
| `↑` `↓` / `j` `k` | 选项目 |
| `g` | 放行（等价 `drover go`）|
| `n` | 发下一件（`drover next`）|
| `p` | 暂停 / 恢复 |
| `a` | 加任务：直接开 `$EDITOR` 编那个项目的 `queue.md`，关掉就生效 |
| `l` | 这个项目的循环开 / 关（`drover loop on|off`）|
| `r` | 刷新 |
| `q` | 退出 |

所有写操作都**转给 `bin/drover` 这个命令**（`subprocess`），不要在 TUI 里自己改文件——判据和队列解析只能有一份实现。

### 5. 中文宽度

`curses` 按字符数排版会错位。用 `unicodedata.east_asian_width` 自己算显示宽度（`W` 和 `F` 算 2 格），写一个 `width(s)` 和 `trunc(s, n)`，所有排版都过它们。**一开始就做对，不要最后再补。**

### 6. 系统通知挪位置

通知现在挂在看板的静态生成路径上（`--notify`）。ROADMAP：「系统通知跟着守护进程走，**和界面无关**」。挪到 `bin/drover` 的 `cmd_loop_run` 里，每跳发一次；看板不再管通知。`board-notified.json` 那套「同一条只提醒一次、消失后再回来要再提醒」的逻辑照搬，别重写。

## 验收（先写测试，确认因为功能没实现而失败，再实现）

- `bash tests/drover-board.sh`、`bash tests/drover.sh`、`bash tests/criteria.sh` 三个套件全过。**后两个一行都不许改**——它们是数据模块没被改坏的证据。
- `tests/drover-board.sh` 现有 15 块里，渲染相关的改成断言 `view_model()` 的返回值；serve / HTTP / 令牌那几块整块删掉；「等你」通知那块跟着挪到 `tests/drover.sh`？**不要挪**，留在 drover-board.sh 里，只是改成调 `drover loop --once` 触发。
- 加一条 `draw()` 的冒烟：`curses.newpad` 或者把 `stdscr` 换成假对象，**画进一个很窄的屏幕（比如 40 列 10 行）不崩、不越界**。
- 加一条中文宽度的测试：`width("把 CSS 导入改成流式")` 要等于 16 不是 11；`trunc()` 截断后的显示宽度不超过给的格数。
- 失败必须是因为目标行为还没实现；导入报错、测试数据坏了不算。
- 测试不许依赖真的 corral、不许依赖真的 agent、不许花钱：沿用现有的假 `corral` 命令和合成 git 仓库。

## 不要做

- **不要碰 `AGENTS.md`「绝对不许碰」那张表里的任何东西**：真的 jb-finetune、`~/.review/`、`~/wt/`、herdr、`dev.herdsman.*` 的 launchd 任务、`~/.local/bin/` 里那几个老命令、`~/.config/review/`。
- 不要往 `~/.local/bin` 拷任何文件，不要 `launchctl` 任何东西，不要改 PATH。
- 不要改 `bin/drover` 里除通知以外的东西；不要改 `tests/drover.sh`、`tests/criteria.sh`。
- 不要动 `install.sh` 和 `launchd/`（`drover/dev-install` 在做）。
- 不要按项目名或路径批量杀进程（`pkill -f drover` 这类）：主控和别的 agent 的进程命令行里都带着项目名和工作目录，一条命令能把它们全杀掉。停自己起的服务用起的时候记下的 PID，或者固定端口后 `lsof -ti:<端口>`。
- 拿主意的地方写进本文件末尾的「实现时的取舍」，并在回复里列出。
- **遇到「必须改数据模块的函数签名才能做下去」，停下来报告，等决定，不要自己换别的办法。**
- 不合并到 main，不推送。只在 `m5-tui` 上提交。

## 记录要求

做完在本文件末尾追加「## 完成记录」（在你的分支里提交）：做了什么、测试命令和结果、遇到的问题、没做的事、实现时的取舍。

## 回复

回复里只写：做完了哪些、测试结果、取舍各一句话、有没有要主控决定的事。命令都在前台跑完，全部做完后，回复最后一行写 DONE。
