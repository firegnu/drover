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
