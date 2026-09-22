# 任务：T6 把完成核对和记 done 折进 go

2026-09-22，drover/main 交给 drover/dev-go-done（Codex，常规档：gpt-6-astra / high）。
路由：常规 / 交叉审查要（路由：tier 拿不准，轻 0、常规 0.48、重 0.52；cross_review 拿不准，core_rules 0.54；主控判断：设计已定、实现局部，常规开发；涉及完成与放行核心规则，独立交叉审查）

你是被委派的 agent：照本文件做，不要再开别的 agent。用户临时指定只派 Codex，不派 Claude。

## 先读

1. AGENTS.md、HANDOFF.md、README.md。
2. docs/ROADMAP.md「记 done 折进 drover go」「完成判据」及档位相关设计。
3. bin/drover 的 check_done、cmd_done、cmd_go、cmd_next，bin/drover-board 的 task_fold、key_action、loop_tick、close_if_done。
4. tests/drover.sh、tests/drover-board.sh、tests/criteria.sh；docs/QUICKSTART.md、docs/手册.md。
5. 本文件。

## 你在哪里干活

- worktree：/Users/firegnu/Developer/personal_projs/drover-worktrees/m15-go-done，分支 m15-go-done，从 main 建好。
- 只用 Python 标准库，无需安装依赖。
- 允许修改 bin/drover、tests/drover.sh；确有必要时修改 bin/drover-board、tests/drover-board.sh、tests/criteria.sh；同步本次操作流程相关的 README.md、docs/QUICKSTART.md、docs/手册.md、docs/ROADMAP.md，以及本任务文件。
- 不修改 HANDOFF.md，由主控收尾。没有并行开发任务。

## 要做的

用户要在任务做完后只按 g，省去手动 drover done。

- cmd_go 遇到进行中任务：核对一次 check_done；失败时输出与现有 done 相同的原因并拒绝放行，不追加 done/go；通过时记录 done 再记录 go，返回成功。
- 已经 done、正在等放行：照旧只记 go，不重新核对、不再记 done。
- 保留判据、工作区检查、收尾依据报告，以及原有手动与自动判断的区别。当前手动 done 没看到收尾记号但门全过时允许人确认，并明确警告；本任务不偷偷改成强制记号，也不移除警告。自动循环仍必须看到记号。
- start → done → go 的事件数据和看板记账不变；档 2、档 3、hold、pause 的既有语义不回退。
- go 本身不调用 cmd_next、不发送下一件；手动流程下一件仍由 n 派发，开启循环时由引擎推进。
- CHECK_CMD 每次核对只能执行一次，报告复用已有结果，不能复发 m11 的重复核对问题；缓存仍只作显示。
- 保留 drover done 命令：供兼容、单独核对并记完成以及引擎现有路径使用；日常操作文档改成按 g / drover go。把该取舍写进 ROADMAP 对应小节和完成记录。
- 确认 TUI 的 g 实际到达 go（目前 key_action 已无条件映射，不要为修改而修改）。必要的提示文字应引导人直接 g/go，而非先去手敲 done。
- 只做本任务必要的小幅复用，避免把 cmd_done 的返回 8 或自动 next 行为带进 go。不要顺手重构其它队列操作。

## 验收：先 RED，再 GREEN

用假的 corral 和临时合成 git 仓库，绝不操作真实队列或真实 agent。

1. 进行中且已满足条件，直接 go 成功，事件精确为 start/done/go；完成字段和记账保留，无额外 start、无 corral send。
2. 至少覆盖 main 未前进、未合入分支、验收命令失败、工作区不干净各自阻挡 go；错误原因与 done 同口径，事件不变。失败修好后 go 能成功。
3. CHECK_CMD 计数器断言每次 go 核对恰好一次；已 done 等放行时 go 不再执行验收。
4. 没收尾记号时保留手动警告和允许确认的既有语义；自动循环缺记号仍不自动记 done。
5. 已 done 放行、空状态拒绝、重复 go 不重复记账、TASK_GATE=0/1、hold 与循环档位相关回归通过；不要引入下一任务提前派发。
6. TUI g 操作到达 go；看板对直接 start/done/go 事件流的显示与既有账目一致。
7. 先跑新增检查，确认失败原因是 go 尚不支持进行中任务，不是 fixture 或语法问题；记录命令、输出关键行与退出码，再实现。
8. 四套回归：for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done。安装测试只用其隔离临时 HOME，绝不真实安装。git diff --check。
9. 做聚焦缺陷植入：绕过 go 核对、重复执行验收、漏写 done 或 go 至少选两项，证明断言能抓住。只改临时副本，DROVER_BIN / DROVER_BOARD_BIN 用绝对路径；两个脚本复制到同一目录。

## 不要做

- 不动 corral 或 corral-dispatch，不读 corral 源码和内部状态；需要契约仅读 corral/docs/CONTRACT.md。
- 不碰真的 jb-finetune、herdsman、~/.review/、~/wt/、herdr、dev.herdsman.*、~/.config/review/ 和老安装命令。
- 不真实安装、不动 launchctl、不改 PATH、不装第三方包；不处理 T4。
- 不操作 ~/.drover 的真实队列，不跑真实项目 drover done/go/next/loop on；用户本人验收 T6。
- 不修既有并发重复 done、短 main 与同名 tag、代理码 list 等其它欠账；新引入的回退需修。
- 不按项目名或路径批量杀进程。停自己起的服务只用记录的 PID。
- 不删既有断言，不扩大任务，不合并 main、不推送、不打收尾记号。只在 m15-go-done 提交具体文件，禁止 git add -A。
- 遇到必须改已定设计、或上述语义彼此冲突，停下来报告。

## 记录要求

在本文件末尾追加「## 完成记录」并在分支提交：实现摘要，RED/GREEN 与缺陷植入证据，四套结果，取舍，问题和未做事项。

## 回复

只写完成内容、测试结果、取舍各一句话，以及是否需要主控决定。命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 完成记录

2026-09-22，Codex，在 `m15-go-done` 分支完成。

### 实现与取舍

- `go` 对进行中任务复用 `record_done`：一次 `check_done`，失败返回 9、原因与 `done` 一致、不写完成或放行事件；通过则报告依据与三条门，依次写 `done` / `go`，返回 0。已完成等放行时仅写 `go`，不重新验收；空状态及重复放行返回 2。
- `record_done` 只核对、报告和记完成；`done` 自己保留原有返回 8、按 gate/hold 等放行或调用 `next` 的路径。`go` 不调用 `done` 或 `next`，不发送下一件。
- 复用原来的 `.loop-wait` 原子写入逻辑：循环开启时直接 `go` 留下推进标记，下一跳由引擎派发；循环关闭时仍由人按 `n`。pause 仍挡住引擎派发，resume 后继续。
- 缺收尾记号的手动警告与允许人确认的语义不变；自动循环仍先查记号。`CHECK_CMD` 每次核对恰好一次，报告复用结果，缓存只供显示。
- `key_action` 无需改动，新增用例从进行中的真实 view model 按 `g` 得到 `go` 并执行；看板仅调整帮助与核对提示。README、QUICKSTART、手册和 ROADMAP 同步日常 `n → g → n` 流程；保留 `done` 供兼容、单独记完成和引擎使用。

### RED → GREEN

1. 先只加直接 `go` 用例，运行 `bash tests/drover.sh`，退出 1：CLI `go` 实际退出 2，预期 0，关键输出 `ERROR: 没有在等放行的任务`。随后才提取共用核对逻辑并实现 `go`。
2. 首次 GREEN 尝试暴露测试配置问题：配置解析器裁掉行尾引号，验收 shell 退出 2；给合成 `CHECK_CMD` 补尾分号后，`bash tests/drover.sh` 退出 0。该 fixture 失败不算 RED；最终还将 `HEAD:bin/drover` 放进临时副本，用修正后的测试重跑，仍在直接 `go` 处以同样的退出 2 / 预期 0 失败，确认目标缺陷。
3. 再加拒绝/重试、计数器、记账、档位和引擎用例，`bash tests/drover.sh` 退出 1：循环下一跳后仍只有 `start/done/go`，没有 T2 的 `start`。之后才补 `.loop-wait` 复用，重跑退出 0。
4. 最终新增检查输出：
   - `PASS direct go: start/done/go, one check, no send`
   - `PASS direct go: four refusals match done, repairs pass, cache never decides`
   - `PASS direct g/go: warning, existing done, gate/hold/pause, engine continuation`

四类拒绝分别覆盖 main 未前进、未合入分支、验收失败、已跟踪工作区不干净；逐条比较 `done` 的问题行，断言事件与 send 日志不变，修复后可直接 `go`。同时伪造通过的显示缓存，确认不能绕过核对。实际生成的完成事件验证 sha、gate、时间字段、看板完成计数、耗时、提交数和等放行显示。

### 回归与缺陷植入

前台运行 `for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done`，总退出码 0：

| 套件 | 结果 |
|---|---|
| criteria | PASS，含真实中/法文坏 ref 场景、分支判据和收尾记号四道闸 |
| drover | PASS，新增直接 go 及所有原队列、done、hold、循环与 init 断言 |
| install | 9 tests，OK；仅隔离临时 HOME / 沙箱，无真实安装 |
| drover-board | 所有 PASS，含无收尾记号不自动完成、TUI、引擎及 20 项 check-result 测试 |

`git diff --check` 退出 0。

植入只在临时目录；每个变体的 `drover` / `drover-board` 同目录，均以绝对路径设置 `DROVER_BIN` / `DROVER_BOARD_BIN`，前台运行 `bash tests/drover.sh`。五个变体均退出 1，命中行为断言，没有语法或 fixture 错误：

| 植入 | 命中的断言 |
|---|---|
| 清空核对问题列表，绕过拒绝 | main 未前进时 `go` 实际退出 0，预期 9 |
| 重复调用 `check_done` | `go must check exactly once`，实际计数 2 |
| 漏写 `done` | 事件只有 `start/go`，预期 `start/done/go` |
| 漏写 `go` | 事件只有 `start/done`，预期 `start/done/go` |
| 漏留 `.loop-wait` | 引擎下一跳仍只有三条事件，缺 T2 的 `start` |

### 问题和未做事项

- 无需新增设计决定；主控继续按任务要求审查，真实 T6 留给用户本人按 `g` 验收。
- 未动 HANDOFF，未再委派，未操作真实队列/agent，未安装、动 launchd、合并 main、推送或打收尾记号；T4 与列明的既有欠账未处理。
- 阅读时发现 QUICKSTART/手册仍有正文 `验收：` 覆盖命令的旧说明，本次仅同步完成/放行操作流程，未扩大为其它文档清理。


## 主控审查（第 1 轮，2026-09-22）

结论：改完再审。四套测试主控独立重跑全绿，范围符合；认可保留 done、一次共用核对、go 不直接发下一件及补 .loop-wait 的取舍。

**必须改：TUI 按 g 吞掉结果中的重要信息。** `bin/drover-board:run_drover` 只返回 stdout 第一行，当前新测试只从 key_action 拿参数再自行执行 CLI，绕过了真实 TUI 的 run_drover 路径。主控用临时合成仓库和真实 CLI 实测：缺收尾记号时 CLI 有「这次算你自己判断的」，但 run_drover 返回只有「核对通过 T1：」；已跟踪文件脏时返回只有「NOT DONE: T1 还没收尾：」，没有任何具体原因。直接按 g 是本任务的主入口，这两种是正常使用会遇到的情形，不能把 CLI 全绿当成端到端验收。

请先补能通过真实 run_drover 路径复现缺口的 RED，再最小修复：看板必须让用户看到缺记号的手动确认警告，以及拒绝时的具体原因；成功结果应明确已经放行。保持 CLI 输出/退出码和事件语义，避免为了显示增加重复核对或额外队列写入。结果文本进入 curses 时沿用必要的控制字符处理，避免引入换行/tab 崩溃。无需新造复杂界面；优先沿用现有消息区/详情机制，关键状态放前面以免窄屏截掉。

补 GREEN、相关回归与针对「恢复只返回第一行」的缺陷植入，记录证据。原任务范围不扩大，其余既有欠账不处理。

## 第 1 轮审查修复记录

2026-09-22，基于实际审查提交 `348748b`，仅修改 `bin/drover-board`、`tests/drover.sh` 和本文件。

### 修复

`run_drover` 对 `go` 的结果按退出码前置「已放行 / 未放行」，把 CLI 原有的警告行（`↑`）和问题行（`-`）排到消息前面，再连接其它输出；沿用现有单行消息区，不新增界面或队列写入。进入 curses 前按详情区已有规则压平 ASCII 控制字符，避免原始 tab / 换行落进 `addstr`。CLI 输出、退出码、判据和事件语义均未改动。

### RED → GREEN

- **先加测试**：合成仓库 + 假 corral，经真实 `tui → key_action → run_drover → CLI → draw` 执行 `g`，只替换 curses 终端边界，读取假屏幕最后一帧的底部消息。
- **RED**：`bash tests/drover.sh` 退出 1。无记号场景消息只有 `核对通过 T1：`，缺「已放行」「没看到收尾记号」「这次算你自己判断的」；脏工作区消息只有 `NOT DONE: T1 还没收尾：`，缺具体原因和 `work` 文件名；有记号成功时也缺「已放行」。随后才修改 `run_drover`。
- **GREEN**：同命令退出 0。新增断言确认 80 列可见完整手动确认警告，40 列仍可见放行状态和缺记号提示；40/80 列都可见脏工作区原因与文件名。每个 TUI 用例仍恰好一次 CHECK_CMD，成功事件精确为 `start/done/go`，拒绝只有 `start`，均无额外发送。
- 补充真实 CHECK_CMD 输出 `failed\twith\nsecond` 后退出 1，经 `run_drover` 保留失败文本并压平控制字符，再送进 20/40/80/2000 列假屏幕，断言无控制字符、无越界；最窄屏仍可见「未放行」，40 列起可见「判据 3」。

### 回归与缺陷植入

- 前台运行 `for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done`，总退出码 0：criteria、drover、drover-board 全部 PASS，install 9 tests OK，check-result 20 tests OK；安装仅隔离临时 HOME / 沙箱。
- 两个脚本成对复制到临时目录，`DROVER_BIN` / `DROVER_BOARD_BIN` 均设置为该目录绝对路径，前台运行 `bash tests/drover.sh`：
  - **恢复首行截断**：仅移除 go 消息前置/拼接分支，恢复返回 `out[0]`，退出 1，真实 TUI 再次只显示 `核对通过 T1：` / `NOT DONE: T1 还没收尾：`，40/80 列对应断言均捕获。
  - **移除控制字符压平**：退出 1，命中消息中仍含 `failed\twith` 的断言。
- `git diff --check` 退出 0；既有断言全部保留。

无需主控新增设计决定；待增量复审。未再委派、未操作真实队列或 agent、未合并或推送，其余认可取舍与既有欠账未扩大处理。


## 主控增量复核（2026-09-22）

结论：主控审查通过，进入独立交叉审查。返工 943399e 仅改消息展示和相关测试，认可沿用单行消息区、警告和原因前置、ASCII 控制字符压平的取舍，CLI 与事件语义未变。

主控独立前台重跑 `bash tests/drover.sh`、`bash tests/drover-board.sh`，全部通过（含 20 项 check-result）；`git diff --check` 通过。此前四套全绿，返工未动安装与判据实现，不重复扩大检查。

主控独立在临时成对脚本副本中植入两项缺陷并运行 drover 套件：恢复首行截断退出 1，命中真实 TUI 缺「已放行」等消息断言；重复 check_done 退出 1，命中「go must check exactly once」，实测计数 2。均非语法/fixture 失败，被审代码未修改。

第 1 轮必须改项已解决，其余取舍同意。交叉审查通过前不合并；真实 T6 的 g 验收归用户。


## 交叉审查返工要求（2026-09-22）

主控认可唯一必须改：run_drover 对 go 仍 timeout=120，会杀掉正常的长验收；CHECK_TIMEOUT=1800，现有引擎 done 外层为 CHECK_TIMEOUT+60。独立审查原版完整 TUI 用 125 秒成功验收复现，120.63 秒返回超时，事件只有 start。

先补经过真实 run_drover/CLI 的 RED，再仅将 go 的外层期限对齐 CHECK_TIMEOUT+60，其它短操作保留原期限。不引入异步 UI，不改判据/队列语义。回归可以缩短时限模拟同样内外层关系，避免每次等待 125 秒；不能仅断言传入某个常数，要让慢验收实际成功落账，精确 start/done/go、验收一次、无额外发送。保留其它断言，针对恢复旧超时做缺陷植入。记录证据和相关回归，提交到本分支后回复 DONE。

完整审查及裁定在主仓库 /Users/firegnu/Developer/personal_projs/drover/docs/任务/m15-go-done 交叉审查.md，只读它，不修改。仍不合并、不推送，不操作真实队列，不再委派。审查者之后只做增量复核。

## 交叉审查返工完成记录

2026-09-22，已读主仓库交叉审查全文及主控裁定；基于返工要求提交 `47266b2` 修复。

- **最小实现**：`run_drover` 的 subprocess 调用只改一行，`go` 使用 `CHECK_TIMEOUT + 60`（当前 1860 秒），其它命令继续 120 秒。未改 CLI、验收内部期限、判据或队列语义，未引入异步 UI。
- **先 RED**：在 `tests/drover.sh` 增加合成仓库和真实慢验收，经实际 `run_drover → CLI` 执行；只包装父进程的 subprocess 边界，将传入外层 timeout 除以 120，旧预算为 1 秒、新预算为 15.5 秒。验收脚本真实记录 PID/次数并睡 2 秒，不伪造命令结果。`bash tests/drover.sh` 退出 1，命中 `slow go must finish within the check budget`，消息含 `timed out after 1.0 seconds`；此前「验收确实启动且恰好一次」断言通过。失败返回后按记录 PID 等该短验收自然退出，未留下进程。随后才改生产代码。
- **GREEN**：同命令退出 0，输出 `PASS run_drover slow go: start/done/go, one check, no send; short commands keep 120s`。断言返回明确「已放行」、事件精确 `start/done/go`、验收一次、send 日志不变；另经真实 `run_drover list` 确认短命令仍传 120 秒且不增加事件/验收/发送。
- **相关回归**：前台 `bash tests/drover.sh` 和 `bash tests/drover-board.sh` 均退出 0，后者含 20 项 check-result 测试；`git diff --check` 退出 0。本轮未改判据实现和安装，沿用交叉审查已验证的四套全绿结果，不重复扩大检查。
- **恢复旧超时植入**：两个脚本成对复制到临时目录，仅把条件 timeout 恢复为固定 `120`，先通过 Python 语法编译，再用绝对路径 `DROVER_BIN` / `DROVER_BOARD_BIN` 前台运行 `bash tests/drover.sh`。套件退出 1，精确命中同一慢验收断言及 `timed out after 1.0 seconds`；非语法或 fixture 失败。测试仍等验收 PID 退出后才报告失败，没有实际等 125 秒。

本轮仅改 `bin/drover-board`、`tests/drover.sh` 与本文件，保留全部既有断言；主仓库交叉审查文件只读。无需新增设计决定，待原审查者增量复核；未再委派、未操作真实队列、未合并或推送。
