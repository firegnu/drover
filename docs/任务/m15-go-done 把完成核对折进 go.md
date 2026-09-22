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
