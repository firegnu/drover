# 交叉审查：T6 完成核对折进 go

2026-09-22，drover/main 交给独立 Codex，重档 gpt-6-astra / xhigh。
路由：重 / 交叉审查要（开发任务路由拿不准，core_rules 0.54；主控判断为完成与放行核心规则，独立审查）

你是被委派的审查 agent，不再委派，不开 Claude。

## 背景与先读

开发分支 m15-go-done，实现提交 a401c3e，主控第 1 轮意见 348748b，返工提交 943399e。用户要在手动模式只按 g 核对、记完成、放行，下一件仍按 n；保留 done 命令以及自动档位。主控已发现并交回修复 TUI run_drover 只显示首行、吞掉手动警告和拒绝原因的问题。

先读 AGENTS.md、HANDOFF.md、docs/ROADMAP.md「记 done 折进 drover go」、开发任务文件 `docs/任务/m15-go-done 把完成核对折进 go.md`（含主控审查与返工证据），再读本文件与 diff。按当前任务和最新记录理解历史，不重开用户已定的设计。

## 审查范围

- 你的 worktree：/Users/firegnu/Developer/personal_projs/drover-worktrees/review-m15-go-done，detached，基于返工后的分支创建。
- 被审实现固定为 943399e；基准 e6e1c3c。用 `git diff e6e1c3c..943399e` 看代码和测试；后续提交若只有主控审查记录，不改变被审实现。
- **只读代码，不修改、不提交、不切分支、不合并。** 只能追加本文件「## 审查意见」。
- **本文件在主仓库工作区，不在你的审查 worktree 里**，唯一可写文件的绝对路径：/Users/firegnu/Developer/personal_projs/drover/docs/任务/m15-go-done 交叉审查.md。
- 可前台运行四套合成测试（criteria/drover/install/drover-board），安装测试只跑隔离临时 HOME；可在 /tmp 创建合成仓库和生产副本做定向复现/植入。DROVER_BIN、DROVER_BOARD_BIN 传绝对路径，两个脚本放同一目录。避免 .pyc 污染。
- 禁止运行真实队列 done/go/next/loop on；不真实安装、不动 launchctl、不推送；不碰 corral 源码、技能、内部状态及 AGENTS 列出的老 herdsman/真实项目路径。不按名字批量杀进程。

## 主控已验证

- 第 1 轮：独立重跑四套全绿，真实 CLI + 合成仓库复现 TUI 信息丢失，故未直接放行。
- 增量复核关注真实 tui → run_drover → CLI → draw 消息路径，40/80 列警告、拒绝原因、放行状态，检查调用计数和事件顺序。
- 保留 done 的兼容/引擎路径、复用一次核对、手动缺记号警告并允许确认、go 不发送下一件、循环启用时留 .loop-wait 的取舍，主控认可。

## 重点看（7 条）

1. 进行中直接 go：核对失败不追加 done/go，成功严格 done → go；已 done 只 go，无重复验收/记账。空状态、重复 go 的错误路径是否保持。
2. check_done/record_done 提取是否保留工作区检查、三条门、手动依据警告、一次 CHECK_CMD、显示缓存不参与判断；原 done 返回码与引擎行为有无回退。
3. go 自身绝不发送下一件；loop on 的 .loop-wait 补充是否使档 2/3 正常继续，pause/hold 是否保留。区分本次引入的缺陷与既有无锁事件并发问题。
4. TUI 真正按 g 的输出：成功明确放行，拒绝有可行动原因，缺记号的手动确认警告可见；检查窄屏顺序、ASCII 控制字符和 Unicode 保真。不能只测 key_action 后绕过 run_drover。
5. start/done/go 的字段、完成时间、等放行时间、看板统计是否符合既有口径。
6. RED/GREEN 证据及新增断言是否真能挡回退，必要时做定向缺陷植入；不要求为既有欠账补测试。
7. 改动范围及文档与实际行为一致，确认不会恢复正文验收命令覆盖语法或启用无人值守；只评价本次变更，不做全仓库文字清理。

## 分级与输出

**分级按「正常用会不会撞上」来定：需要特意构造畸形输入才触发的，标「建议改」或「可以不改」，不要标「必须改」。** 本次新引入且正常使用会碰到的回退才挡合并。既有欠账（并发重复 done、短 main 与同名 tag、list 代理码、旧正文验收说明）不扩大本次。

在本文件末尾追加「## 审查意见」：一句结论（可以合并 / 改完再合并），每条意见写必须改/建议改/可以不改、位置、复现证据、问题和改法；逐条评价上述取舍，记录实际测试命令与结果。

回复只写结论和条数。命令都在前台跑完，全部做完后，回复最后一行写 DONE。


## 审查意见

2026-09-22，独立 Codex 交叉审查。

**结论：改完再合并。必须改 1 条，建议改 0 条，可以不改 0 条。** 下方认可的取舍与逐项核对不另计问题条数。

被审实现固定为 `943399e`，基准 `e6e1c3c`。审查 worktree 的 HEAD 是 `f256e41`，其相对 `943399e` 仅追加开发任务文件中的主控增量复核，不改变代码或测试。未重开已定设计。

### 必须改 1：TUI 的 120 秒外层超时会提前杀掉正常的 go 核对

- **位置**：`bin/drover:429–436` 新增的进行中任务核对路径；`bin/drover-board:976–983` 的 `run_drover`，尤其 `timeout=120`。对照同文件 `CHECK_TIMEOUT = 1800`（403 行）及引擎调用 `done` 时的 `CHECK_TIMEOUT + 60`（1112–1113 行）。
- **问题**：本次把可能运行整套测试的核对放进 `g`，却仍使用原先只做短操作的 120 秒期限。正常配置一个耗时超过 2 分钟、但未超过现有 30 分钟上限的 `CHECK_CMD`，CLI/引擎允许它运行，TUI 主入口却提前终止 `drover go`。这不是畸形输入，也不是既有无锁事件并发问题；旧流程在终端运行 `done`，再按只放行的 `g`，不会把验收放进这个短超时。
- **实际复现**：在临时合成仓库中完成 `next`，添加合法收尾空提交，设置验收为一个等待 125 秒后正常退出 0 的 Python 脚本。使用被审原版脚本，走真实 `tui → key_action → run_drover → CLI → draw`，只替换 curses 终端边界和 corral；没有缩短或替换生产超时。
  - `g` 在 **120.63 秒**返回，消息为 `drover go：没跑起来（Command ... timed out after 120 seconds）`。
  - `tasks.state` 仍只有 `start`，没有 `done` / `go`，也没有 `.check-result`。
  - 验收确实已启动，TUI 返回时仍未结束；随后自然执行完并正常退出，事件仍只有 `start`。因此重新按 `g` 会重新核对，前一次的成功无法落账。
  - 已等待这个自建验收进程自然结束，并按记录 PID 确认没有遗留进程。
- **改法**：对会执行核对的 `go` 给足外层期限，至少沿用引擎已有的 `CHECK_TIMEOUT + 60` 口径；保留其它短操作的既有期限即可。补一条经过 `run_drover` 的慢验收回归，证明在验收允许时间内成功时，返回明确放行、事件精确为 `start/done/go`、验收一次且无额外发送。测试可用受控的短时限模拟相同的内外层关系，避免每次回归等待两分钟。无需改完成判据、引入异步界面或重构引擎。

### 七项核对与取舍

| 项目 | 判断与证据 |
|---|---|
| 1. 进行中 / 已 done / 空状态 / 重复 go | 除上述 TUI 超时外通过。直接 CLI 成功严格 `start/done/go`；main 未前进、未合入分支、验收失败和已跟踪工作区脏均返回 9，不追加完成或放行，修复后可重试。已 done 路径只追加 go，连后来故意弄坏的验收都不会重跑；空状态和重复 go 返回 2、事件与发送日志不变。 |
| 2. 共用核对和 done 兼容 | 认可 `record_done` 的小幅提取。工作区检查、三条门、依据报告和缺记号警告保留；每次 CHECK_CMD 一次，报告复用 rows，伪造通过的显示缓存不能绕过核对。原 done 的拒绝 9、等放行 8、自动模式调用 next 均由既有回归验证；自动路径缺记号仍不记 done。没有将 done 的返回 8 或自动 next 带入 go。 |
| 3. 派发边界与循环 | 认可循环开启时补 `.loop-wait`。go 自身没有 next/send，调用前后发送日志不变；档 2、档 3 都到下一次 loop_tick 才派发 T2，循环关闭时须显式 next。hold 继续反映在 done 的 gate 字段，人的 go 完成放行；pause 仍阻止引擎派发，resume 后续跑。未扩大到既有无锁并发欠账。 |
| 4. 真实 g 消息 | 主控第 1 轮信息丢失问题已修复：完整 TUI 路径中，80 列可见完整缺记号手动确认警告，40 列可见放行状态和缺记号提示；40/80 列都可见脏工作区原因与文件名，成功明确已放行。验收拒绝在 20/40/80/2000 列不越界；另经真实 CLI 核对了全部九个目标 ASCII 空白控制字符的压平。独立合成未合入分支名的末尾 NBSP、内部 U+2028 / U+0085 在 TUI 消息原文中完整保留。本项尚有上面的慢验收超时必须改。 |
| 5. 事件与看板记账 | 通过。done 保留 id/sha/gate/t，go 保留 id/t；task_fold 使用 done 时刻算完成耗时、go 时刻算等放行时长。直接 go 的完成数、队列余量、提交数和详情显示与既有口径一致，不产生额外 start。自动引擎原有无 go 的记账路径仍由原测试覆盖。 |
| 6. RED/GREEN 与断言有效性 | 当前四套全绿；独立把基准 e6e1c3c 的成对脚本配上当前测试，直接 go 明确以实际退出 2 / 预期 0 失败，错误是「没有在等放行的任务」，不是 fixture 或语法错误。三项独立缺陷植入均命中行为断言，见下。现有断言一条未删；新增测试仍缺慢验收场景，随必须改 1 补充即可。 |
| 7. 范围与文档 | 通过。变更限于两个脚本、相关测试、日常操作文档和开发任务记录；README / QUICKSTART / 手册 / ROADMAP 的新流程均为 n → g → n，并保留 done 兼容入口及自动档位。未恢复正文「验收：」覆盖 CHECK_CMD 的语法，未改变默认档位或启用无人值守。原 QUICKSTART/手册遗留的正文验收说明未因本次变更产生，按任务约定不扩大清理。 |

### 实际验证命令与结果

所有命令均在前台等待完成，无真实队列或真实 agent 操作。安装套件使用其临时 HOME 和 macOS 写入沙箱。

1. 被审 worktree 中运行：

   ```sh
   PYTHONDONTWRITEBYTECODE=1 DROVER_BIN="$PWD/bin/drover" DROVER_BOARD_BIN="$PWD/bin/drover-board" bash -c 'for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done'
   ```

   总退出码 **0**：criteria PASS（含中/法文坏 ref 和收尾记号四道闸）；drover PASS（含新增直接 go、四类拒绝、计数、档位和真实 TUI 路径）；install **9 tests OK**；drover-board 全部 PASS，附带 check-result **20 tests OK**。

2. 定向复现、基准 RED 与缺陷植入的命令：

   ```sh
   PYTHONDONTWRITEBYTECODE=1 python3 /tmp/review-m15-go-done-kcm_jb_7/timeout_probe.py
   PYTHONDONTWRITEBYTECODE=1 python3 /tmp/review-m15-go-done-kcm_jb_7/unicode_probe.py
   PYTHONDONTWRITEBYTECODE=1 python3 /tmp/review-m15-go-done-kcm_jb_7/controls_probe.py
   PYTHONDONTWRITEBYTECODE=1 python3 /tmp/review-m15-go-done-kcm_jb_7/red_probe.py
   PYTHONDONTWRITEBYTECODE=1 python3 /tmp/review-m15-go-done-kcm_jb_7/mutation_probe.py
   ```

   五个验证脚本均退出 **0**，表示其预期现象得到确认；timeout_probe 是对上面缺陷的复现，**不表示被审行为通过**。具体结果：

   | 验证 | 被测结果 / 命中的断言 |
   |---|---|
   | 真实慢验收 | 120.63 秒超时；成功的验收最终无法落账，只有 start。结构化证据为临时目录中的 `timeout-result.json`。 |
   | Unicode / ASCII 控制字符 | NBSP、U+2028、U+0085 保真；`\t \n \v \f \r \x1c \x1d \x1e \x1f` 不进入结果消息，拒绝仍只有 start。 |
   | 基准 e6e1c3c + 新测试 | 内层 `bash tests/drover.sh` 退出 1：直接 go 实际退出 2，预期 0。 |
   | 恢复仅返回首行 | 内层测试退出 1：真实 TUI 缺「已放行」「没看到收尾记号」「这次算你自己判断的」及脏工作区原因，40/80 列均被抓住。 |
   | 重复 check_done | 内层测试退出 1：`('go must check exactly once', 2)`。 |
   | 漏写 done | 内层测试退出 1：实际只有 `start/go`，精确事件序列断言失败。 |

   基准和变体仅写临时生产副本，每个目录内的 drover / drover-board 成对放置，`DROVER_BIN` / `DROVER_BOARD_BIN` 均为绝对路径；变体先通过 Python 语法编译，再运行当前 `tests/drover.sh`。日志保留在上述临时目录，未修改被审代码或测试。

3. `git diff --check e6e1c3c..943399e` 和工作区 `git diff --check` 均退出 **0**。审查期间 worktree 保持 detached、代码及测试无修改；主仓库只追加本审查文件，不提交、不切分支、不合并、不委派。


## 主控裁定（2026-09-22，交叉审查第 1 轮）

唯一必须改项采纳，暂不合并。主控核对原代码：CHECK_TIMEOUT=1800、引擎 done 外层 CHECK_TIMEOUT+60，而 TUI run_drover 仍固定 120；并读回审查者 timeout-result.json，确认真实用例 120.63 秒超时、只有 start、验收已启动但返回时未完成。是本次把核对移入 g 后引入的正常慢验收回退，值得返工。

限定修复：仅对 go 采用与引擎一致的外层超时预算，其它短命令不变。补经 run_drover 的受控慢验收 RED/GREEN，断言成功、start/done/go、核对一次且不派下一件；用缩短时限模拟内外层关系即可，不要求回归每次等待 125 秒。不得引入异步界面、改判据或扩大既有欠账。

其余七项核对和取舍结论认可；修好后交原审查者只复核本条相关改动，不重跑已做过的全仓库审查。


## 增量复核任务（第 1 轮，2026-09-22）

开发修复提交 `ba93e3f`，基于 `47266b2`；生产变更只有 run_drover 超时参数一行，go 采用 CHECK_TIMEOUT+60，其它短命令继续 120。新增 tests/drover.sh 受控慢验收：真实子进程睡 2 秒，仅把父进程调用的外层 timeout 缩放为原来的 1/120；检查成功落账、核对一次、无发送及 list 仍用旧期限。开发记录含 RED/GREEN 和恢复固定 120 的植入证据。

主控会在派发前将你的 detached worktree 更新到 ba93e3f。**仅看 `git diff 47266b2..ba93e3f` 中本条超时和测试相关变化**，复核唯一必须改是否解决。不要重跑上一轮完整四套或重新做全仓库审查；可跑相关 drover 测试及必要的短时受控验证，不需要再真实等 125 秒。

仍只写本主仓库审查文件，代码只读、不提交、不切分支、不操作真实队列。追加「## 增量复核意见（第 1 轮）」：可以合并 / 改完再合并、原必须改项结论、实际验证、剩余条数。命令都在前台跑完，全部做完后，回复最后一行写 DONE。

主控增量检查：`bash tests/drover.sh` 独立重跑退出 0，含真实慢验收成功、精确事件序列、核对一次、无发送和短命令预算检查；`git diff --check 47266b2..ba93e3f` 通过。实现和测试范围符合返工要求，交原审查者增量复核。


## 增量复核意见（第 1 轮）

2026-09-22，独立 Codex。

**结论：可以合并。原唯一必须改项已解决；剩余必须改 0 条、建议改 0 条、可以不改 0 条。**

仅复核 `git diff 47266b2..ba93e3f` 的 go 外层超时、受控慢验收测试及对应开发记录；本 worktree 的 detached HEAD 已确认是 `ba93e3f`。上一轮其它认可结论不变，未重复四套或全仓库审查，也未再真实等待 125 秒。

### 原必须改项结论

- `bin/drover-board:980–981` 仅将 `run_drover` 的 go 外层期限改为 `CHECK_TIMEOUT + 60`，当前为 **1860 秒**，与引擎 done 路径一致；其它命令仍为 **120 秒**。未改内部验收上限、CLI 判据或事件语义，改动范围符合限定返工要求。
- 新测试经真实 `run_drover → CLI → CHECK_CMD` 执行，验收进程真实睡 2 秒。包装只缩放父进程调用 CLI 的外层期限（除以 120），不会伪造子进程结果，也不会改变子进程内的验收上限；旧期限因此为 1 秒，新期限为 15.5 秒，能有效区分原缺陷与修复。
- 成功断言同时覆盖明确「已放行」、精确 `start/done/go`、验收恰好一次及发送日志不变；真实 list 调用另验证短命令仍传 120 秒，且不新增事件、核对或发送。失败分支在验收确实启动的断言之后，按记录 PID 等短验收自然退出，再报告目标行为失败。

### 本轮实际验证

为避免重复整套，临时脚本 `focused-slow.sh` 只从当前 `tests/drover.sh` 提取原有假 corral / 合成仓库初始化、Python fixture 定义，以及本次新增的 44 行慢验收块；补入该块所需的既有 `patch` 导入，不改测试断言。生产脚本和仓库测试均未修改。

1. **GREEN，退出 0，约 2.91 秒**：

   ```sh
   PYTHONDONTWRITEBYTECODE=1 DROVER_BIN="$PWD/bin/drover" DROVER_BOARD_BIN="$PWD/bin/drover-board" bash /tmp/review-m15-timeout-recheck-qnxgbpm1/focused-slow.sh
   ```

   输出：`PASS run_drover slow go: start/done/go, one check, no send; short commands keep 120s`。

2. **恢复旧超时的定向缺陷植入，退出 1，约 2.78 秒**：仅在临时成对生产副本中把条件 timeout 恢复为固定 `120`，先通过 Python 语法编译，再运行同一块测试：

   ```sh
   PYTHONDONTWRITEBYTECODE=1 DROVER_BIN=/tmp/review-m15-timeout-recheck-qnxgbpm1/fixed-120/drover DROVER_BOARD_BIN=/tmp/review-m15-timeout-recheck-qnxgbpm1/fixed-120/drover-board bash /tmp/review-m15-timeout-recheck-qnxgbpm1/focused-slow.sh
   ```

   精确命中 `slow go must finish within the check budget`，返回消息包含 `timed out after 1.0 seconds`。此前验收已启动且恰好一次的断言通过，按 PID 等自然退出的步骤也完成；不是语法、fixture 或清理失败。新增断言能挡住恢复原缺陷。

3. `git diff --check 47266b2..ba93e3f` 退出 0。代码和测试保持只读，HEAD 不变且仍 detached；只追加本审查文件，没有提交、切分支、委派或操作真实队列。


## 主控最终裁定（2026-09-22）

接受增量复核「可以合并」：唯一必须改已解决，剩余 0 条。主控先前已独立验证修复后的 drover 套件，审查者又以短时真实验收及恢复 120 秒的植入作增量确认，证据足够，不再重复全仓库测试。

认可全部实现取舍：保留 done 兼容/引擎入口，手动 go 复用一次核对并保留缺记号警告；go 本身不派下一件，开启循环时由引擎下一跳推进；TUI 沿用单行消息区、关键警告前置，go 外层超时与引擎对齐。准予本地合并 m15-go-done，不推送；清理本任务两个 worktree 和分支并关闭对应自开的 agent，记录收尾记号。真实 T6 的 done/go 不由主控操作，用户亲自按 g 验收，T4 继续暂缓。
