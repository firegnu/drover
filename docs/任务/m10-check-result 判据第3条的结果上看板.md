# 任务：判据第 3 条的核对结果写进交接目录，看板读出来显示

2026-09-21，drover/main 交给 drover/dev-check（Codex，常规档：gpt-6-astra / high）。
路由：常规 / 交叉审查要（路由：档位拿不准——重 0.66、常规 0.34、置信度 0.49，按技能「拿不准用常规」定，且设计已在 ROADMAP 定死、不需要做设计判断；交叉审查路由也拿不准，主控定「要」——并发 0.6，引擎进程写、看板进程读，正是第 6 节点名的那一类）。
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

1. `AGENTS.md`（尤其「硬规矩」「技术约束」「测试」，以及**「看板不存自己的状态，刷新等于重跑」**那一条）
2. **`docs/ROADMAP.md` 的「判据第 3 条的结果怎么上看板（2026-09-21 夜定）」一节——设计已经定死在那里，照做，不要重新设计。**
3. `bin/drover`：`cmd_done`、`check_done`、`criteria_report`、`loop_stop`（`.loop-wait` 的原子写法照抄它）
4. `bin/drover-board`：`criteria`、`close_if_done`（`.criteria-checked` 的用法）、`project_state`、`card_vm`
5. `tests/criteria.sh`、`tests/drover.sh`、`tests/drover-board.sh`
6. 本文件

## 背景：现在为什么看不到

第 3 条要跑人配的验收命令（drover 自己是整套测试，**实测 22 秒**）。看板 30 秒刷一次、每个项目都渲染，渲染时真跑等于每半分钟把所有项目的测试全跑一遍。所以渲染一律 `do_check=False`，第 3 条永远标「—」：

```
看板上：      — 3 验收命令过了 : `for t in criteria drover ...`    ← 只有命令，没有结果
drover done： ✓ 3 验收命令过了 : `for t in criteria drover ...`   ← 有结果，但要人去敲
```

循环引擎（`close_if_done`）其实是真跑的，但它只往 `.loop.log` 写一行摘要，**没有把结果记成看板读得了的形式**。

## 你在哪里干活

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/m10-check-result`，分支 `m10-check-result`（已从 main 建好）。只在这里改。
- 不用装依赖（只用 Python 标准库）。
- 现在没有别的 agent 在这个仓库里干活。

## 要做的

### 1. `bin/drover`：跑了第 3 条就把结果写下来

- 文件：交接目录下的 `.check-result`（`D` 就是交接目录，和 `.loop-wait`、`.criteria-checked` 放一起）。
- **谁写**：`bin/drover` 里**真跑了第 3 条**（`do_check=True`）的那条路径。人手动 `drover done` 和循环引擎调 `drover done` 都走这里，两种都要写。
- **内容**（JSON）：

  ```json
  {"task": "<任务 id>", "main": "<跑的时候 main 的 sha>", "cmd": "<验收命令原文>",
   "ok": true/false/null, "why": "<理由>", "t": <时间戳>}
  ```

- **原子写**：tmp 文件 + `os.replace`，照抄 `loop_stop` 里 `.loop-wait` 的写法。**看板会同时在读这个文件，写到一半被读到就是 bug。**
- **`ok` 为 `null` 的情况也要写**（没配验收命令时第 3 条「不适用」）——看板要能区分「跑了、不适用」和「压根没跑过」。

> **注意一个既有情况**：`cmd_done` 在判据通过时会走两条都跑验收命令的路径——`check_done()` 一次，`criteria_report()` 又一次（drover 自己是 22 秒 × 2）。**这是既有问题，本次不要修**，但你要想清楚写文件放在哪里，别写两次、别写成互相矛盾的两份。把你的选择和理由写进「实现时的取舍」。

### 2. `bin/drover-board`：只读，并判断陈不陈旧

- 看板渲染时（`do_check=False` 那条路）读 `.check-result`。**只读，绝不写。**
- **陈旧判定**：拿当前的任务 id、当前 `main` 的 sha、当前验收命令（`task_check_cmd` 算出来的那个），和文件里的 `task` / `main` / `cmd` 比。**三样全都一致才显示结果**；任一对不上，照旧显示「—」，并说明是哪一样对不上。
- **显示**：结果 + **多久之前跑的**（例如 `✓ 3 验收命令过了（3 分钟前跑的）`）。时间必须带上，理由见 ROADMAP 那节的已知限制——工作区的改动 sha 捕捉不到。
- 文件不存在、内容坏了、JSON 解析失败：一律当成「没跑过」，显示「—」，**不要抛异常把看板搞崩**。

### 3. 边界：这个文件只喂看板显示，绝不参与任何判断

这是本任务最要紧的一条，和 `m7-accounting` 里「路由：」行那条边界同级：

- `criteria()` 本身**绝不读**这个文件——要判的时候照旧现跑。
- `check_done()` / `close_if_done()` / `loop_tick()` 的行为**完全不受**这个文件影响。
- 文件被删掉、写成垃圾、或者写成「第 3 条过了」，判据和循环的结论**一个字都不能变**。

## 验收（先写测试，确认因为目标行为没实现而失败，再实现）

1. `drover done` 跑完之后 `.check-result` 存在，内容是合法 JSON，六个字段齐全，`main` 和当时的 sha 一致。
2. **看板显示结果**：三样全一致时，第 3 条显示 `ok` 和「多久之前」，不再是「—」。
3. **陈旧三种各一条**：`task` 对不上 / `main` sha 对不上 / `cmd` 对不上 —— 三种都必须显示「—」，且**理由文字能区分是哪一样对不上**（不要三条都 grep 同一个宽泛的词）。
4. **`ok=null`（没配验收命令）写下来之后，看板显示的是「不适用」，不是「没跑过」**——两者要能区分。
5. **坏文件不崩**：`.check-result` 内容是 `not json`、是空文件、是合法 JSON 但缺字段 —— 三种都显示「—」，看板照常渲染。
6. **原子性**：验证写的过程中不会留下半截文件（检查用了 tmp + `os.replace`，且 tmp 名字不会和别的进程撞）。
7. **「绝不参与判断」要有守线**（照 `m7` 的办法）：把 `.check-result` 写成「第 3 条过了」，再跑一次判据/`loop_tick`，结论必须和没有这个文件时**完全一致**。另外把文件写成一碰就炸的内容，判据照样跑完。
8. 四个套件全绿：`for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done`

**断言有效性自检（这个项目连着三件活都栽在这里，务必做）**：写完测试后往实现里**逐条植入缺陷**，确认对应断言真的变红——至少包括：陈旧判定去掉一样（比如不比 `cmd`）、显示时不带时间、坏文件不做保护、`ok=null` 和「没跑过」混成一种、原子写改成直接 `open(...).write()`、以及让 `criteria()` 去读这个文件。**有任何一条植入之后测试仍然全绿，说明那条断言守不住，重写它。** 在完成记录里列出你植入了哪几条、各自红了没有。

失败必须是因为目标行为还没实现；语法错、fixture 坏了不算 RED。

## 不要做

- **不要改 `docs/ROADMAP.md`**（设计已定死，那是主控的文件）。不要动 `docs/任务/` 下已有的历史任务文件。
- **不要修 `cmd_done` 跑两次验收命令那个既有问题**（本次范围外，我会另记欠账）。
- **不要让看板写任何文件**。「看板不存自己的状态，刷新等于重跑」是硬约束。
- 不要引入第三方包、不要引入新的配置项。
- 不要碰 `~/.drover/` 下的真实交接目录、`~/.review/`、`~/wt/`、`~/.local/bin/`、launchd。测试一律用合成仓库和假 corral。
- 不要合并到 main，不要推送。只在 `m10-check-result` 上提交。
- 不要按项目名或路径批量杀进程（`pkill -f drover` 这类）：主控和别的 agent 的命令行里都带着项目名和工作目录，一条命令能把它们全杀掉。
- 拿主意的地方写进本文件「实现时的取舍」，并在回复里列出。
- 遇到「按 ROADMAP 做不下去」的情况，停下来报告，等决定，不要自己换别的办法。

## 记录要求

做完在本文件末尾追加「## 完成记录」（在你的分支里提交）：做了什么、测试命令和结果、**植入缺陷自检的逐条结果**、遇到的问题、没做的事。

## 回复

回复里只写：做完了哪些、测试结果、取舍各一句话、有没有要主控决定的事。命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 实现时的取舍

- **只在 `check_done()` 发布一次**：保存决定是否允许 done 的第一次核对结果；`criteria_report()` 既有的第二次执行原样保留，不覆盖记录。测试用第一次通过、第二次失败的命令验证：仍执行两次，文件只发布一次且保存第一次结果。第二次报告与第一次判断可能不同，这是本次明确不修的既有问题。
- **main 在核对前取值，时间在首次核对结束时记录**：不会把验收期间新出现的 main 提交当成已验证的版本；看板随后会按 main 不一致判陈旧。时间沿用看板的 `dur()` 口径，如 `3m 前跑的`，放在判据名称后，避免被长命令挤掉。
- **只在 `card_vm()` 的显示层替换第 3 条**：新增 `check_result_vm()`，不改 `criteria()`、`wants_human()`、`close_if_done()`、`loop_tick()` 的判断逻辑；无有效文件与已核对但不适用分别显示「没跑过」和「不适用」。
- **原子写沿用 `.loop-wait` 模式**：同目录 `.check-result.<pid>.tmp` 写完关闭后 `os.replace`，临时名字按进程区分；不增加配置、依赖或看板写操作。

## 完成记录

2026-09-21，drover/dev-check，在 `m10-check-result` 分支完成。

### 做了什么

- `bin/drover`：手动或循环调用 done 时，将第 3 条的成功、失败、不适用结果写入 `.check-result`，包含设计列出的 `task/main/cmd/ok/why/t` 字段；未通过其它门时仍记录已执行的核对结果。
- `bin/drover-board`：只读记录，严格核对当前任务 id、main sha、有效验收命令；不匹配时分别说明原因。匹配时显示结果、原始理由和运行距今时间；文件缺失、坏 JSON、缺字段、字段类型错误、非法时间和非法 UTF-8 均降级。
- `tests/check-result.py`：8 个聚焦测试，覆盖真实 CLI 写入、循环写入、显示与只读性、三种陈旧、null、坏文件、原子替换、进程临时名、核对期间 main 改变，以及文件不参与判断。由 `tests/drover-board.sh` 调用，支持现有 `DROVER_BIN` / `DROVER_BOARD_BIN` 临时副本验证方式。

### 测试命令和结果

所有命令均前台运行并等到退出；只使用临时合成 git 仓库和假 corral，安装套件使用自己的隔离环境。

1. `python3 tests/check-result.py CheckResult.test_done_writes_result`：实现前 RED，三个子例均因「done 未写 .check-result」失败；实现后 GREEN。
2. `python3 tests/check-result.py CheckResult.test_board_matching_results CheckResult.test_board_stale_results CheckResult.test_board_missing_and_invalid_results CheckResult.test_board_not_applicable_is_not_missing`：修正夹具后 RED，命中结果仍是 None、三种陈旧原因缺失和「没跑过」缺失；实现后 GREEN。
3. `python3 tests/check-result.py`：8 个测试全绿。
4. `for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done`：四个套件全部通过，退出 0；安装 9 项、新增聚焦测试 8 项通过。
5. `bash -n tests/drover-board.sh`、Python 源码 `compile()` 检查、`git diff --check`：通过。

### 植入缺陷自检

逐条在临时目录里的 `drover` / `drover-board` 副本植入，先用 `compile()` 确认不是语法错误，再通过环境变量指向副本运行对应的 `CheckResult.test_*`。9 项全部 RED；执行后核对工作区两个实现文件字节未变。

| 植入缺陷 | 对应测试 | 结果与失败依据 |
|---|---|---|
| 陈旧判断不比 task | `test_board_stale_results` | RED，`True is not None` |
| 陈旧判断不比 main | `test_board_stale_results` | RED，`True is not None` |
| 陈旧判断不比 cmd | `test_board_stale_results` | RED，`True is not None` |
| 显示名称去掉距今时间 | `test_board_matching_results` | RED，实际详情缺少 `3m 前跑的` |
| 取消坏 JSON 的 ValueError 保护 | `test_board_missing_and_invalid_results` | RED，`JSONDecodeError`，看板渲染中断 |
| `ok=null` 直接走没跑过分支 | `test_board_not_applicable_is_not_missing` | RED，缺少「不适用」，实际成了「没跑过」 |
| 改成直接 open 目标写入并移除 replace | `test_done_publishes_once_atomically` | RED，「不得直接写目标文件」 |
| tmp 改成无 pid 的固定名字 | `test_done_publishes_once_atomically` | RED，临时名不含模拟进程号 `12345` |
| `criteria()` 调 read 读取 `.check-result` | `test_result_never_enters_decisions` | RED，「判断路径读了 .check-result」 |

### 遇到的问题、没做的事

- 看板测试最初漏建 `queue.md`，因此没有卡片；补齐夹具后重新取得真正的行为 RED，未将夹具错误算作 RED。实现阶段统一了陈旧提示的空格，随后聚焦测试全绿。
- 未修 done 重复跑验收命令；未改 ROADMAP、历史任务文件、HANDOFF；未改 corral / corral-dispatch；未访问真实交接目录或真实项目、未实际安装或动 launchd、未合并 main、未推送。
- 没有需要主控决定的设计问题；交叉审查与后续合并由主控安排。

## 主控审查

2026-09-21，drover/main。**结论：通过，可以进交叉审查。**

- **四个套件自己重跑全绿。** 新测试 `tests/check-result.py` 挂在 `drover-board.sh` 末尾，用 `DROVER_BIN` / `DROVER_BOARD_BIN` 两个环境变量指向实现，保住了本项目的植入自检跑法。
- **自己独立植入三条要害，全部因目标断言变红**：
  1. 陈旧判定不比 `cmd` → `test_board_stale_results` 红（`True is not None`）；
  2. 显示去掉「多久之前跑的」→ `test_board_matching_results` 红（`'3m 前跑的' not found`）；
  3. 让判断路径（`close_if_done`）去读 `.check-result` → `forbid_read` 开火，`判断路径读了 .check-result`。
- **`test_result_never_enters_decisions` 比我要求的强**：它 `patch("builtins.open", forbid_read)`，**从机制上禁止判断路径读这个文件**，不是弱比对；三种内容（合法 JSON 说通过 / `not json` / 非法 UTF-8）各试一遍，并断言 `tasks.state` 字节不变、`.loop.log` 与基线一致、`drover done` 的 returncode/stdout/stderr 三样全同。
- **抽看代码**：原子写 tmp+`os.replace`、tmp 名带 PID；`check_result_vm` 只在 `card_vm` 里替换第 3 条，`criteria()` / `wants_human()` / `close_if_done()` / `loop_tick()` 的判断逻辑一个字没动；坏文件走严格类型校验（含 `math.isfinite` 挡 NaN）降级成「没跑过」。
- **范围核对**：只动了 `bin/drover`、`bin/drover-board`、`tests/drover-board.sh`、新增 `tests/check-result.py` 和本文件。ROADMAP 没碰，`cmd_done` 跑两次验收命令那个既有问题按要求**没修**。

### 主控自己踩的两个坑，记下来免得重走

1. **植入自检只复制 `drover-board` 一个文件会炸在成对检查上**：`task_bin_path()` 返回「board 副本旁边的 `drover`」，副本放临时目录就 `FileNotFoundError`。**两个文件要一起复制**（dev 的做法是对的）。以前只跑 `tests/criteria.sh` 没撞上，因为那条路不走 `close_if_done`。
2. **植入代码里写 `except Exception: pass` 会把 `forbid_read` 的 `AssertionError` 吞掉**，造成「测试守不住」的假象。植入时要么显式 `except AssertionError: raise`，要么别包 try。

### 取舍逐条表态

1. **只在 `check_done()` 发布一次，不覆盖 `criteria_report()` 的第二次执行** —— 同意。它还补了一条测试（第一次通过、第二次失败的命令）证明「执行两次、只发布一次且是第一次的结果」，正好把那个既有问题的边界钉住了。
2. **`main` 在核对前取值、时间在核对结束时记录** —— 同意。验收期间新出现的提交不会被当成已验证的版本，看板随后按 main 不一致判陈旧，方向正确。
3. **只在 `card_vm()` 显示层替换，不碰 `wants_human()`** —— 同意。「等你」横幅不因这个文件改变，符合「绝不参与判断」。
4. **原子写沿用 `.loop-wait` 模式，tmp 名按 PID 区分** —— 同意。

### 留给交叉审查的两点（主控没有定论）

1. **`rows[-1] = check_result_vm(...)`** 依赖「第 3 条永远是 `rows` 最后一行」。同一件事 `bin/drover` 里用的是 `next(r for r in rows if r["n"] == 3)`，两处风格不一致。现在 `criteria()` 恒定产出三行所以成立，但以后增减行就会错位。
2. **`forbid_read` 的盲区**：它靠抛 `AssertionError` 报警，而生产代码里若写 `try: ... except Exception: pass` 就会把它吞掉，守线失效。现实中判断路径不太可能这么写，但这是这条守线的边界，请判断要不要加固。

## 返工记录

2026-09-21，drover/dev-check，按主控对交叉审查的裁定完成第一轮返工：第 1–6 条全部落实，第 7–9 条保持已接受边界。

### 改了什么

1. **坏记录保护到绘制边界**：`.check-result` 读取处捕获 `RecursionError`；四个字符串字段拒绝 NUL，并检查 UTF-8 可编码性，避免 JSON 转义解出的孤立代理码送进 curses。失败只把本记录降级为无有效记录，没有给整个看板套宽泛异常捕获。所有显示回归现在经过 `draw()` / 假屏幕 `addstr()`，假屏幕拒绝 NUL，并断言第 3 条确实被画出；真实 `printf '\000'; exit 1` 产生的记录另用 40×120 PTY 跑真实 curses 绘制。
2. **发布失败不影响判断**：只对 tmp 写入、JSON 写入、replace 的 `OSError` 报 stderr 诊断，继续返回真实判据并维持队列动作。实际将 marker 放成目录，成功/失败 × 放行/自动四组对照的退出码、stdout、事件完全相同（事件仅剔除运行时间戳）；自动模式继续发 T2。另注入 tmp 权限错误、写入磁盘满、replace 错误，确认 `check_done()` 问题列表不变。不删除异常目标，不清扫 tmp。
3. **加固读取守线**：独立列表观察 `builtins.open`、`io.open`、`os.open` 的读取尝试，路径统一 `fsdecode` + `realpath`，兼容 Path、bytes、`..`、`./` 与 macOS `/var` 别名。调用返回后断言列表为空；不靠一个可被吞掉的异常断言。直接调用同进程 `check_done()`，连同它独立加载的 board 模块一起观察；保留真实 CLI、循环和事件的内容污染对照，成功侧伪造失败、失败侧伪造成功，两侧都测坏 JSON / 非法 UTF-8。
4. **局部限量**：只在读取 `.check-result` 时以二进制读最多 65537 字节，记录超过 64 KiB 降级；`why` 超过 4096 字符降级。覆盖上限正好成立、超一位、2 MiB 理由；另观察实际 read 请求和返回量，防止先无界读再检查长度。未改全局 `read()` 或排版函数。
5. **未来时间**：用显示时 `time.time()` 判断并计算距今时间，容许 5 秒偏差；超过该范围按坏记录降级。覆盖一天后的坏时间、3 秒小偏差，以及采集开始后 59 秒发布、60 秒才显示的正常记录，后者显示 `1s 前跑的`，不拿采集起点 NOW 误判。
6. **按编号替换**：`card_vm()` 用 `n == 3` 定位；调序为 3、1、2 的回归确认只更新第 3 条，最后一条保持原结果。

### RED → GREEN 与完整验证

- 先用新增回归复现真实 curses `ValueError: embedded null character`；系统 `/usr/bin/python3`（3.9.6）对 1200 层 JSON 实际抛 `RecursionError`。默认 Python 3.14.7 另外用解析器抛 `RecursionError` 的确定性注入覆盖异常出口，避免依赖解释器恰好不报错。修复后两种 Python 的两项回归都通过。
- 发布路径目录异常：实现前四组对照均因退出 1 而失败，修复后真实退出码分别恢复为成功自动 0、成功放行 8、失败 9；事件与无故障基线一致。
- 长度和时间回归：实现前 4097 字符、2 MiB、65537 字节、一天后的时间均被错误接受；实现后按坏记录降级。
- `for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done`：四套件全部通过，退出 0；安装套件 9 项、新增及原有聚焦测试合计 15 项通过。
- `/usr/bin/python3 tests/check-result.py`：系统 Python 3.9.6 下 15 项全部通过，含真实 PTY。
- `bash -n tests/drover-board.sh`、两个实现及聚焦测试的 `compile()`、`git diff --check`：通过。
- PTY 回归初版未排空终端缓冲而超时，修正测试驱动后才取得真实的 NUL RED；不把夹具超时算作产品缺陷证据。发布回归用 `finally` 清掉测试自己创建的空目录，避免一组失败污染下一组。

### 缺陷植入逐条结果

所有植入都在临时成对副本中进行，先 `compile()` 确认语法有效，再用 `DROVER_BIN` / `DROVER_BOARD_BIN` 指向副本跑对应聚焦测试；没有在工作区实现里留下植入。

先从返工前的 `HEAD` 取实现和旧测试，重放审查者的五种读取植入，再用新实现、新测试逐项对照：

| 植入 | 旧守线 | 新守线与失败依据 |
|---|---|---|
| `close_if_done` 普通 open 读取，外包 `except Exception: pass` | GREEN，复现盲区 | RED，返回后发现 `builtins.open` 读取计数非零 |
| `close_if_done` 用 `Path(.../../.../.check-result).read_bytes()` | GREEN，复现盲区 | RED，`io.open` 读取计数非零 |
| `close_if_done` 用 bytes 路径 `os.open` + `os.read` | GREEN，复现盲区 | RED，`os.open` 读取计数非零 |
| `close_if_done` 用子进程 `cat` | GREEN | **仍 GREEN，明确不在此守线覆盖范围** |
| `check_done` 用普通 open 读取记录 | GREEN，复现子进程盲区 | RED，同进程直接调用记录到 `builtins.open` 读取 |

其余植入全部 RED：

| 植入 | 对应测试 | 失败依据 |
|---|---|---|
| 去掉 NUL 字符检查 | `test_nul_output_reaches_real_draw` | 真实 PTY 退出 1，`addstr` 的 `ValueError: embedded null character` |
| 每份有效结果在显示时 why 追加 NUL | `test_board_matching_results` | 假屏幕绘制边界抛 `ValueError: embedded null character`，不再停在 VM 层而假绿 |
| 去掉 `RecursionError` 捕获 | `test_deep_json_and_parser_recursion` | `RecursionError: deep JSON` |
| 发布的 OSError 重新抛出 | `test_publish_failure_preserves_done_and_advance` | 退出 1 与基线 0/8/9 不符 |
| tmp 打开错误不隔离 | `test_publish_io_errors_preserve_check_done` | `PermissionError: tmp denied` |
| 改回无界 `read()` | `test_record_and_reason_limits` | 观测到 `read(-1)` 返回 2097280 字节，即使事后降级也会 RED |
| 去掉 why 长度上限 | `test_record_and_reason_limits` | 4097 字符结果仍为 True，预期 None |
| 去掉未来时间校验 | `test_future_time_and_collection_skew` | 一天后结果仍为 True，预期 None |
| 恢复 `rows[-1]` | `test_check_row_is_selected_by_number` | 调序后第 3 条未被更新，None 不等于预期 False |

共 13 项要求守住的退化全部变红；`cat` 作为已声明不覆盖的对照仍绿。第一批植入驱动的失败消息筛选漏列了 `PermissionError`，实际测试已红；补齐筛选并重跑该项和未执行的后续项，均取得上述明确证据。

### 守线覆盖范围与未改内容

- 本测试观察**同进程**中这三个标准库打开入口：`criteria()`（包含 do_check=False）、项目的等人判断、`close_if_done()` / `loop_tick()` 本进程部分，以及直接调用的 `check_done()`（含其 board 模块）。它是测试内的读取观察，**不是从机制上禁止读取，也不是通用文件访问沙箱**。独立列表的断言发生在被测调用返回之后，生产代码吞异常藏不掉读取尝试。
- 真实 `drover done` 子进程保留行为对照，但不会继承这层观察；子进程 `cat`、其它打开入口或事先持有的文件描述符也不属于本计数器的覆盖范围。实现审阅确认生产判断路径没有新增此类记录读取；不能把一次内容对照当成禁止所有未来读取方式的证明。此前主控审查中「从机制上禁止读取」的表述，以本节和最新主控裁定为准。
- 未改第一次核对才发布的选择、重复验收既有问题、三键陈旧规则；未加 tmp 清扫、fsync、结果锁或队列锁，残留与两个 done 并发的既有欠账留给主控。
- 未改 ROADMAP / HANDOFF / 交叉审查文件；未碰真实交接目录、真实项目、安装与 launchd；只在 `m10-check-result` 提交，不合并、不推送。没有新增待主控决定的事项。
