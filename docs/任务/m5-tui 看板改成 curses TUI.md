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

## 完成记录

2026-09-20，drover/dev-tui 做完，在 `m5-tui` 上。

### 做了什么

1. **`bin/drover-board` 1598 → 927 行**。数据模块那部分（`collect` / `discover` / `parse_conf` /
   `criteria` / `find_done_mark` / `task_*` / `wants_human` / `agents_of` / `corral*` / `loop_tick` /
   `close_if_done` …）原样留着，一个函数名、一个返回值都没动。删掉的：`CSS`、`DRAWER`、
   `LIVE_DIALOG`、`LIVE_EDITOR`、页面 JS、`render*`、`serve`、`live_action`、`live_version`、
   `health(started, port)`、`launchd_job`、`span_text`、`notify_new`、`esc`、`state_badge`、
   `tilde`、`task_body_html`、`task_desc`、`task_history`、令牌 / Host / Origin 校验、
   `/v` `/health` `/history` `/api/*`，以及 `hashlib` 之外的 HTTP 相关 import。
   `tests/browser-smoke.mjs`（168 行）一起删了。
2. **`view_model()` / `draw()` 两层**。`view_model(projects) → dict`（顶栏健康、跨项目「等你」
   汇总、每个项目的 waits / card / todo / finished / counts / mode），不碰 curses；
   `draw(stdscr, vm, state)` 只排版，内容判断一个没有。验收全打在 `view_model()` 上。
3. **界面**：顶栏（项目数 + corral 健康 + 等你几条）→ 左边项目列表 / 右边详情，详情从上到下是
   等你（每条带 `corral attach <名字>`）→ 当前这件活（分支进展 + 判据，**收尾记号排最前**）→
   队列 → 做完的。深色（`use_default_colors`，只设前景色）。
4. **按键**：`↑↓`/`jk` 选项目、`g` 放行、`n` 发下一件、`p` 暂停 / 恢复、`a` 开 `$EDITOR` 编
   `queue.md`、`l` 循环开 / 关、`r` 刷新、`q` 退出。所有写操作走 `run_drover()`，`subprocess`
   转给 `bin/drover`，TUI 自己不碰交接文件；drover 的第一行输出显示在最底下那条消息栏里。
5. **中文宽度**：`cell()` / `width()` / `trunc()`（`unicodedata.east_asian_width`，`W`/`F` 算两格，
   组合字符不占格），所有排版都过 `put()` → `trunc()`。
6. **系统通知挪到 `bin/drover`**：`NOTIFY_BIN` / `applescript_str` / `notify_new` 照搬过去，
   新增 `tick()`，`cmd_loop_run` 每跳先 `B.loop_tick` 再通知。记录文件仍是
   `~/.drover/board-notified.json`（名字没改，老记录接着用）。看板里现在一个 notify 字样都没有。

### 测试

```
bash tests/drover-board.sh   PASS（8 块）
bash tests/drover.sh         PASS（一行没改）
bash tests/criteria.sh       PASS（一行没改）
```

`tests/drover-board.sh` 632 行改动：渲染相关的 15 块断言改成打在 `view_model()` 的返回值上
（`q`/`is` 两个辅助函数把 JSON 化的 vm 拿来求表达式）；serve / HTTP / 令牌 / 加任务 / 调顺序 /
history / hold / health 那几块整块删掉；并发写临时文件那块删掉（没有文件输出了）；
「等你」通知那块留在本文件里，改成 `drover loop --once` 触发、`HOME` 指到临时目录；
循环开关那块改成走 CLI（`drover loop on|off` / `pause` / `resume`），原来它是拿 HTTP 驱动的
——顺手修掉一个老 bug：那块拿 `/api/pause {"on":false}` 当恢复用，实际那个端点只会暂停，
返回 409 被 `|| true` 吃掉了，于是「循环关掉后不发」其实是靠「还暂停着」才通过的。
新增三块：HTML / HTTP 层删干净了（对源码 grep 一串关键字）、`width()` / `trunc()`、
`draw()` 画进 40x10 / 20x6 / 12x3 假屏幕不崩不越界（假屏幕连 curses「右下角那一格写不得」
也一起守着）。

先写测试、确认红（`AttributeError: module 'rb' has no attribute 'view_model'`）再实现。
另外真开了一次 TUI 验收：pty 里跑起来、按 `l` 和 `p`，交接目录里确实出现了 `loop` 和
`paused` 文件，消息栏显示 drover 的回话，按 `q` 正常退出。

### 遇到的问题

- 任务书里「`width("把 CSS 导入改成流式")` 要等于 16 不是 11」这两个数字对不上：那串是
  **12 个字符、19 格**（7 个汉字 ×2 + `CSS` + 两个空格）。16/11 是 ROADMAP 里算岔了的，
  意思（宽度 ≠ 字符数）没错。测试按真值断言 19 和 12。
- `criteria(do_check=False)` 第 3 条的 `why` 里那句「没在页面上跑」现在没有页面了。
  主控审查时定了改法，已改成「没在刷新时跑（可能是整套测试）；drover done 时才跑」，
  `tests/drover-board.sh` 里加了一条断言钉住这个说法。`tests/criteria.sh` 没断言过它，
  确认过之后一行没动。
- `README.md` 第 24 行还写着「只读看板（HTML，深色）」、第 46 行还把「看板改 TUI」列在待办里。
  文件不在本任务的改动范围内（而且 `drover/dev-install` 可能也要动 README），**没动**。
- `docs/ROADMAP.md` D1 第 5 步第 3 项「看板改 TUI」还没标做完——改 ROADMAP 要先问人，留给主控。

- 头一版测试漏了一处隔离：`drover loop --once` 现在每跳都发通知，而通知记录写
  `~/.drover/board-notified.json`、通知命令默认是 `osascript`——几个不带 `HOME` / 
  `DROVER_NOTIFY_BIN` 的调用因此写到了真的家目录、真的弹了几条 macOS 通知。已经修掉
  （所有 `drover loop` 调用统一走 `loop()` 这个辅助函数，两个变量都指进临时目录，
  并加了「跑完 mtime 不变」的核对）。**留下的痕迹**：真实家目录里多出一个
  `~/.drover/`，里面只有一个 `board-notified.json`，内容是合成仓库的条目。
  没删——AGENTS.md 里删东西要先问人。下次真的循环一跑就会被覆盖掉，留着也无害。

### 主控审查之后补的

**按键映射拆成纯函数 `key_action(k, pv, state)`**（审查意见：推进靠按键是新的主操作面，
不能只埋在 `tui()` 里跟 `getch` 缠着，而且 `p` / `l` 认当前状态，切反了就是真 bug）。

- `key_action` 不碰 curses、不跑命令、不改 `state`，只读 `state` 里的 `sel` 和 `n`，
  返回 `("sel", 新下标)` / `("run", [drover 参数…])` / `("edit",)` / `("quit",)` /
  `("refresh",)` / `None`。`tui()` 只剩 `getch` 和执行。
- 新测试（先写、确认红 `no attribute 'key_action'` 再实现）盖住：`g`→go、`n`→next、
  `p` 没暂停→pause / 暂停中→resume、`l` 循环关→loop on / 开着→loop off、没接队列的项目按
  没暂停没循环算、`a`→edit、`q`→quit、`↑↓jk` 在第一个 / 最后一个 / 空列表都不越界、
  `r` / `-1`（getch 超时）/ `KEY_RESIZE`→refresh、生键→`None`（不动也不重跑）、
  以及「不许改 state」。`pv` 直接取自真的 `view_model()`，字段名跟着一起验，
  免得手搓的 fixture 和真结构悄悄走散。
- 顺带的行为变化：消息栏在每次「刷新」时还原成按键提示，所以命令的回话最多留到下一次
  自动刷新（30 秒）。以前只有按 `r` 才还原。
- 重新用 pty 验了一遍：`j` `k` 选项目、回到 alpha 再按 `l` `p`，只有 alpha 的交接目录里出现
  `loop` / `paused`，beta 没被误操作，`q` 退出码 0。

**通知加了节流 `NOTIFY_EVERY = 60`**（审查意见：看一眼要跑一整趟 `collect()`——每个项目十来个
git 子进程外加一次 corral status——而引擎默认 5 秒一跳，常驻一天一万七千多趟，是实打实的退化）。

- 节流记在内存里的 `_looked_at`（引擎是常驻进程，不用落文件，也没新建配置项）；照
  `close_if_done` 的 `CHECK_EVERY` 那个样子来。`--once` 每次都是新进程，手动跑一跳照样会看。
- 节流的是**多久看一次有没有新的等你**：`board-notified.json` 那套去重一个字没动，
  循环推进（`B.loop_tick`）也照旧每跳都跑。
- 新测试（先写、确认红「连着两跳看了 2 次」再实现）：把 `B.collect` 换成计数的假函数，断言
  连着两跳只看一次、把 `_looked_at` 倒回去之后会再看一次、两种情况下 `loop_tick` 都每跳都跑、
  `NOTIFY_EVERY` 不许退回成 0。
- 另外真开了一次常驻引擎核对：`--interval 1` 跑 8 秒（约 8 跳），假 corral 只被叫了 2 次、
  集中在同一秒里——也就是八跳里只看了一趟。停进程用的是起的时候记下的 PID。

### 没做的事

- 详情区不滚动：内容超出窗口时截断，最后一行显示「… 还有 N 行，窗口再高些」。任务书的按键表
  里没有滚动键，没有自作主张加。
- 长行（判据的 `why`、「等你」那句）按显示宽度截断，不折行。
- 「做完的」那一栏仍然不显示「派了几个 agent、返工几轮」，最底下的「记账」也仍然没有——
  这两样在 ROADMAP 里等待定项 3，不在本任务范围。

### 实现时的取舍

1. **通知节流 `NOTIFY_EVERY = 60`**（主控审查时定的，见下面「主控审查之后补的」）。
   头一版是照任务书「每跳发一次」写的，但引擎默认 5 秒一跳，而看一眼要跑一整趟 `collect()`。
   现在节流的是「多久看一次」，去重仍旧全靠 `board-notified.json`，循环推进不跟着节流。
2. **健康提示只剩 corral 一项**。老的 `/health` 有五项（本机服务、launchd 托管、看板定时生成、
   出错记录、corral），前四项全是围着 HTTP 服务和 launchd 定时生成转的，那两样都没了；
   ROADMAP 也写着「健康检查留，数据源换成 `corral ls`」。「引擎 `drover loop` 在不在跑」没做成
   一项：要靠扫进程认，而 AGENTS.md 明确不许按项目名匹配进程。
3. **`wait_items()` 的返回值从三元组改成二元组**（丢掉 HTML 锚点那一项）。它不在任务书的保护
   名单里，锚点是网页独有的东西。用它的两处（看板、通知）都跟着改了。
4. **`a` 键直接开 `$EDITOR` 编 `queue.md`**（`shell=True`，因为 `EDITOR` 可能带参数）。这是
   任务书和 ROADMAP 都写明的做法：队列本来就是人的 markdown 文件，「写操作转给 drover」那条
   规矩管的是判据和队列**解析**，编辑文件本身不经解析。
5. **窄屏退化**：宽度不够（`w < rail + 16`）时不画左边的项目列表，只画选中项目的详情；
   `h < 5` 或 `w < 20` 时只写「窗口太小」。
6. **顶栏不显示主控状态**，只有项目数 + 健康 + 等你几条。主控状态块在 `f03efec` 已经删了，
   是 corral board 的活，没加回来。
