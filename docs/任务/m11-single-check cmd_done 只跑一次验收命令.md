# 任务：`cmd_done` 只跑一次验收命令，报告复用同一次结果

2026-09-21，drover/main 交给 drover/dev-once（Codex，常规档：gpt-6-astra / high）。
路由：常规 / **不做交叉审查**（路由两项都拿不准——档位常规 0.58、重 0.42，置信度 0.36；交叉审查 core_rules 仅 0.37，明显低于前两件活的 0.9 和并发 0.6。主控判定：改动是纯粹「复用已经算好的结果」，不引入新逻辑、不改判据语义，主控审查加植入自检足够）。
你是被委派的 agent：照本文件做，不要再开别的 agent。

**这是 drover 自举的第一件活**——任务是 drover 自己从队列里发给主控的（队列 id `T1`）。

## 先读

1. `AGENTS.md`（「硬规矩」「技术约束」「测试」）
2. `bin/drover` 的 `check_done()`、`criteria_report()`、`cmd_done()` 三个函数
3. `tests/check-result.py` 的 `test_done_publishes_once_atomically`（**这条会因为本次改动失效，必须改写**）
4. 本文件

## 背景

`cmd_done` 判据通过时会跑**两次**验收命令：

```python
probs = check_done(current)          # ← 里面 B.criteria(..., do_check=True) 跑一次
if probs: ... return 9
print(f"核对通过 {tid}：")
for line in criteria_report(current):  # ← 里面又 B.criteria(..., do_check=True) 跑一次
    print(line)
```

drover 自己的验收命令是四个套件，**实测 22 秒**，所以 `drover done` 要等 44 秒。

## 要做的

让验收命令**只跑一次**，报告复用同一次的结果。怎么串你定（把 `rows` 传出来、把两个函数合一、或者别的），但要满足下面全部约束。

### 必须守住的边界

1. **`check_done()` 的返回值被测试多处 `assertEqual` 断言**（`tests/check-result.py` 的 214/224/236、489/508 几处）。改它的签名或返回类型，要把这些调用点一并处理好，**不能靠放宽断言来通过**。
2. **`.check-result` 仍然只发布一次，且是决定能否 `done` 的那次结果。** 现在这条由 `test_done_publishes_once_atomically` 守着，它用的 fixture 是：

   ```python
   self.configure(f"echo run >> {counter}; test $(wc -l < {counter}) -eq 1")
   ```

   —— 靠「第一次过、第二次不过」来证明发布的是第一次的结果。**本次改成只跑一次之后，这个构造就失效了**（命令只跑一次，永远通过，「第二次」不存在）。

   **改写成：断言验收命令确实只执行了一次**（例如核对 counter 文件恰好一行），并保留原有的原子发布断言（`不得直接写目标文件`、tmp 在同一文件系统、tmp 名带 PID、发布前读者仍看见完整旧文件、发布后内容一致）。这条改写正好把本次改动的目标钉住，别削弱成只验发布。
3. **判据语义一个字不能变**：三条门的结论、`probs` 的内容和顺序、`drover done` 的退出码（8 / 9）、`done` 事件、`NOT DONE` 的输出格式，都和改动前一致。
4. **报告内容不变**：`criteria_report` 打出来的四行（依据 + 三条门）措辞、顺序、`✓ / — / ✗` 标记都不变。人看到的东西一模一样，只是快了一半。
5. **`criteria_report` 里的依据那一行**（`done_mark_row`）是纯 git、很便宜，不受本次影响，照旧每次算。

## 验收（先写测试，确认因为目标行为没实现而失败，再实现）

1. **验收命令只执行一次**：用计数器命令跑一次真实 `drover done`，断言 counter 恰好一行。这条是本次的核心，必须是新增或改写后的断言。
2. **`drover done` 的可观察行为完全不变**：判据全过时退出 8、事件 `start, done`、stdout 的报告四行；判据不过时退出 9、`NOT DONE` 格式、`probs` 内容。**拿改动前后的输出逐字节对照**（构造一个验收命令稳定的场景，别用带时间戳的输出）。
3. **`.check-result` 的内容仍是那次核对的结果**，六个字段齐全，原子发布的几条断言全部保留。
4. 四个套件全绿：`for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done`
5. **顺带报一下提速**：改动前后 `drover done` 的耗时各测一次，写进完成记录。

**断言有效性自检**：往实现里植入缺陷，确认对应断言变红，至少包括——(a) 改回跑两次；(b) 报告用第二次的结果而不是第一次的；(c) 发布的是第二次的结果。**任一植入之后测试仍全绿，说明断言守不住，重写它。**

> **跑测试和植入自检的注意事项**（这个仓库连着栽过三次）：
> - `tests/check-result.py` 要 `DROVER_BIN` / `DROVER_BOARD_BIN` 指向实现，**必须用绝对路径**（测试内部会切 cwd）。
> - 植入自检要把 `drover` 和 `drover-board` **两个文件一起复制**到同一个临时目录（`task_bin_path()` 找的是 board 副本旁边的 `drover`）。
> - **不要设 `PYTHONIOENCODING`**，用干净环境跑。
> - 植入代码里别写 `except Exception: pass`，会吞掉守线抛的 `AssertionError`。

## 不要做

- 不要改 `docs/ROADMAP.md`、不要动 `docs/任务/` 下已有的历史任务文件。
- **不要修 `print(line)` 遇到孤立代理码会崩那个既有问题**（欠账 11，用户已定不修）。
- 不要改判据本身（`drover-board.criteria`）、不要改 `.check-result` 的字段或陈旧判定。
- 不要引入第三方包、不要引入新配置项。
- 不要碰 `~/.drover/` 下的真实交接目录、`~/.review/`、`~/wt/`、`~/.local/bin/`、launchd。
- 不要合并到 main，不要推送。只在 `m11-single-check` 上提交。
- 不要按项目名或路径批量杀进程（`pkill -f drover` 这类）。
- 拿主意的地方写进本文件「实现时的取舍」，并在回复里列出。

## 记录要求

做完在本文件末尾追加「## 完成记录」（在你的分支里提交）：做了什么、测试命令和结果、植入自检逐条结果、**改动前后 `drover done` 的耗时**、没做的事。

## 回复

只写：做完了哪些、测试结果、取舍各一句话、有没有要主控决定的事。命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 实现时的取舍

- `check_done(task)` 返回 `(probs, rows)`，`cmd_done` 将同一份 `rows` 传给 `criteria_report(task, rows)`；不加缓存、可选参数或新抽象，报告入口不能暗中重新执行验收。既有直接调用测试全部适配为完整元组相等断言，仍比较原来的问题列表，另覆盖三条门。
- `.check-result` 仍在原位置原子发布一次；依据行仍每次调用 `done_mark_row(task)` 现算。三条门、问题顺序、打印格式、事件和退出码不变。
- 原子发布用例保留“第二次会失败”的命令作为缺陷植入时的结果区分器，但核心改为明确断言 counter 只有一行；另加真实 CLI 计数测试，避免只证明发布次数。
- 耗时用临时合成仓库的稳定命令 `sleep 1` 各测一次，隔离重复执行本身的成本；不把这组数字当成真实项目四套件的耗时。

## 完成记录

2026-09-21，基线 `6c696f4`，在 `m11-single-check` 完成。

### 改动与 RED → GREEN

- `bin/drover`：首次核对的三条门同时用于决定 done、发布结果及打印报告，只执行一次验收命令。
- `tests/check-result.py`：新增真实 CLI 单次执行和完整报告/失败输出回归，改写原子发布测试，适配 `check_done` 的完整返回值。
- 先运行以下命令，退出 1、两条真实目标失败：CLI counter 为 `['run', 'run']`，预期 `['run']`；报告的第三条门实际为第二次的 `✗`，预期第一次的 `✓`。没有语法错误或 fixture 错误。

  ```sh
  env -u PYTHONIOENCODING DROVER_BIN="$PWD/bin/drover" DROVER_BOARD_BIN="$PWD/bin/drover-board" \
    python3 tests/check-result.py CheckResult.test_done_runs_check_once CheckResult.test_done_publishes_once_atomically
  ```

- 最小实现后同一命令退出 0，2 条全过。
- 原子发布原有断言全部保留：禁止直接写目标、tmp 同目录且带 PID、发布前读到完整旧文件、发布后内容等于 tmp、每次只发布一次、不同进程不撞名、成功后无 tmp 残留；另核对六字段与首次核对的 `ok` / `why` / task / main / cmd。

### 输出对照与耗时

改动前先把两个可执行文件复制到同一临时目录。临时 `observe.py` 使用现有 `CheckResult` 的合成仓库 fixture 和假 corral，固定 git 提交日期；改动前保存原始 stdout/stderr 字节，改动后逐字节比较。临时证据目录为系统临时目录下的 `drover-m11-zfnosayn`，含 `before.json`、`after.json`、耗时、观察及植入脚本/日志。

运行命令（`EVIDENCE` 指上述临时证据目录，两个实现路径均为绝对路径）：

```sh
env -u PYTHONIOENCODING python3 "$EVIDENCE/observe.py" "$PWD" "$EVIDENCE/before/drover" "$EVIDENCE/before"
env -u PYTHONIOENCODING python3 "$EVIDENCE/observe.py" "$PWD" "$PWD/bin/drover" "$EVIDENCE/after"
```

五个场景全部相等：`true` 成功、`echo failed; exit 1` 失败、空验收不适用、工作区脏且三条门同时失败、`sleep 1` 成功。成功退出 8、事件 `start, done`、依据加三条门四行报告；失败退出 9、仅 `start`，`NOT DONE` 输出与问题内容/顺序不变。多项失败的顺序为工作区、门 1、门 2、门 3。事件与 `.check-result` 除时间戳外也完全相等。

同一合成场景、`CHECK_CMD=sleep 1`，用 `time.perf_counter()` 包住真实 `drover done T1` 子进程，各测一次：

| 实现 | 耗时 |
|---|---|
| 改动前 | 2.151203 秒 |
| 改动后 | 1.121760 秒 |

减少 1.029443 秒，约 47.9%；这是单次合成测量，不是整套验收命令的性能基准。

### 断言有效性植入自检

运行 `env -u PYTHONIOENCODING python3 "$EVIDENCE/mutate.py" "$PWD"`。每种缺陷独立复制 `drover` 与 `drover-board` 到同一临时目录，使用绝对 `DROVER_BIN` / `DROVER_BOARD_BIN`，前台运行对应测试；未设置 `PYTHONIOENCODING`，未吞断言异常。

| 植入 | 对应测试与结果 |
|---|---|
| (a) 首次核对后额外跑一次 `B.criteria`，丢弃结果 | `test_done_runs_check_once` 退出 1：counter 两行，命中“验收命令只能执行一次” |
| (b) 报告重新跑 `B.criteria`，用第二次结果 | `test_done_publishes_once_atomically` 退出 1：报告行实际 `✗ 3`，预期 `✓ 3` |
| (c) 发布用第二次 `B.criteria` 的第 3 条，判断仍用首次结果 | `test_done_publishes_once_atomically` 退出 1：发布前检查 `saved["ok"]`，`False is not True` |

三次均为目标断言失败（各 `FAILED (failures=1)`），没有假绿或启动错误。植入仅在临时副本，之后恢复两个文件并逐字节核对等于工作区实现。

### 完整验证及边界

```sh
env -u PYTHONIOENCODING DROVER_BIN="$PWD/bin/drover" DROVER_BOARD_BIN="$PWD/bin/drover-board" python3 tests/check-result.py
env -u PYTHONIOENCODING bash -c 'for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done'
git diff --check
```

- 结果记录测试 17 条全绿；四个套件全部退出 0，含安装隔离测试 9 条与看板中的结果记录测试 17 条；diff 无空白错误。
- 所有命令都等待前台执行完成；只用合成仓库、假 corral 和隔离安装测试，无真实 agent 或真实交接目录操作。
- 未改 `drover-board.criteria`、记录字段/陈旧判定、ROADMAP 或历史任务文件；未修孤立代理码旧问题；未安装、启用 launchd、合并 main 或推送。
- 无需主控另行决定实现事项；按原安排交主控审查。
