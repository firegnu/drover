# 任务：`drover done` 遇到孤立代理码不再崩，顺带把撤掉的那条回归补回来

2026-09-21，drover/main 交给 drover/dev-surrogate（Codex，常规档：gpt-6-astra / high）。
路由：常规 / 交叉审查不要（路由：档位拿不准——常规 0.81、轻 0.19、置信度 0.71，按技能「拿不准用常规」；交叉审查 `core_rules` 0.05、数据模型 0.02、并发 0.04，纯输出编码问题）。
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

1. `AGENTS.md`（尤其「硬规矩」「技术约束」「测试」三节）
2. `bin/drover` 的 `criteria_report()`（第 380 行附近）和 `cmd_done()` 里第 394 行那个 `print(line)`
3. `bin/drover` 第 214–222 行：`m10` 给 `.check-result` 发布加的 `except (OSError, UnicodeError)`
4. `git show 84f76c3`——**当初撤掉那条回归测试的提交**，和它前一条 `1cc33e8`（加上那个 except 的提交）
5. `tests/check-result.py` 第 200–240 行（现存的「未能发布」两条断言）
6. 本文件

## 这个 bug 是什么

`bin/drover` 的 `cmd_done()` 里：

```python
for line in criteria_report(current, rows):
    print(line)
```

任务正文里含**孤立代理码**（U+D800–U+DFFF，落单的代理对半边）时，`print` 抛 `UnicodeEncodeError`，`drover done` 直接退出 1：

```
UnicodeEncodeError: 'utf-8' codec can't encode character '\ud800' in position 3: surrogates not allowed
```

**怎么进来的**：`tasks.state` 每行是 JSON，`\udXXX` 是合法的 JSON 转义，`json.loads` 解出来就是一个孤立代理码。它进到任务正文（`body`）、再进到判据理由（`why`）、再进到这一行 `print`。

**这是既有问题**，改动前的 `main` 一模一样会崩——实测两边都是退出 1、同一处 `UnicodeEncodeError`。

## 连带要做的：把撤掉的那条回归补回来

`m10`（`1cc33e8`）给 `.check-result` 的发布旁路加了 `except (OSError, UnicodeError)`，让写文件失败不挡住 `drover done`。**但守它的那条回归在 `84f76c3` 被撤掉了**，理由是它依赖调用者有没有设 `PYTHONIOENCODING`——设了就绿、不设就红，不稳。

2026-09-21 夜用户定的口径是：**撤掉测试、保留修复、记欠账**，并写明「要补测试得先修 `print`」。这件活就是那个「先」。所以：

**`print` 修好之后，把那条回归用不依赖 `PYTHONIOENCODING` 的方式补回来。** 先 `git show 84f76c3` 看它原来怎么写的、为什么不稳，再决定新写法。

## 要做的

1. **修 `drover done` 的输出路径**，让它遇到孤立代理码不崩。具体改哪几处 `print` 你自己判断——至少 `cmd_done` 里那个 `print(line)`，如果同一条正文还会流到别的输出点，一并处理。
2. **不要改判据理由的内容**。理由里的字符原样保留，只让输出这一步不炸（`m13` 刚定过同一条边界：显示层不许改写数据）。代理码怎么显示你定，但要在任务文件里说清楚取舍。
3. **把 `84f76c3` 撤掉的那条回归补回来**，新写法不许依赖 `PYTHONIOENCODING` 或任何调用者环境。

## 验收（先写测试，确认它因为目标缺陷而失败，再实现）

**顺序按项目规矩**：先写测试、在**没改** `bin/drover` 的情况下跑一遍确认它红了，而且红的原因是 `UnicodeEncodeError`（不是导入报错、不是 fixture 坏了），再动实现。

至少覆盖：

- 任务正文含孤立代理码时 `drover done` **不崩**：退出码是正常的判据结果（8 / 9），不是 1，stderr 里没有 `UnicodeEncodeError`。
- 判据理由里那些**正常字符原样保留**（别为了不崩把整条理由吞掉或换成占位符）。
- `84f76c3` 撤掉的那条：`.check-result` 发布遇到编码错误时**不挡住 `drover done`**，走 `WARNING: 未能发布` 那条旁路。**新测试不设 `PYTHONIOENCODING`，也不依赖调用者设没设**。

跑法（四套都要绿，跑完把数字贴进完成记录）：

```sh
for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done
```

**另外做一次独立的缺陷植入自检**：把你的修复临时改回原来的裸 `print`，确认新断言**红**；改回来确认绿。自检的临时改动不要提交。

> 植入自检的两个已知坑，别再踩：临时目录里要把 `bin/drover` 和 `bin/drover-board` **两个文件一起**复制过去（`task_bin_path()` 找的是 board 副本旁边的 `drover`）；`DROVER_BIN` / `DROVER_BOARD_BIN` 要传**绝对路径**（测试内部会切 cwd）。

> 造测试数据时注意：**孤立代理码没法经过 UTF-8 编码的中间层**（shell 的 `echo`、写进 UTF-8 文件都会炸——主控自己刚踩过一次）。用 Python 直接写 `tasks.state`，或者写 JSON 的 `\udXXX` 转义让 `json.loads` 解出来。

## 不要做

- 不要改判据逻辑（`criteria()`、`check_done()`、`find_done_mark()`），也不要改判据理由的文字内容。
- 不要碰 `bin/drover-board` 的渲染。看板那边 `m13` 刚处理过，是另一条路径。
- 不要动欠账 9（`.check-result.<pid>.tmp` 残留）和欠账 10（两个 `drover done` 并发写两条 `done`），那是别的活。
- 不要为了「顺手」把 `bin/drover` 里全部 47 处 `print` 都包一层——只处理会吃到任务正文 / 判据理由的那些，其余不碰。
- 不要装第三方包，不要引入标准库之外的依赖。
- 不要合并到 `main`，不要推送，不要开别的 agent。只在 `m14-print-surrogate` 上提交。
- 不要按项目名或路径批量杀进程（`pkill -f drover` 这类）：主控和别的 agent 的命令行里都带着项目名和工作目录，一条命令能把它们全杀掉。
- 拿主意的地方写进完成记录的「实现时的取舍」，并在回复里列出来。
- 遇到「不依赖 `PYTHONIOENCODING` 就补不回那条回归」这种情况，**停下来报告，等决定**，不要自己换个方案往下做，也不要再把测试删掉。

## 你在哪里干活

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/m14-print-surrogate`，分支 `m14-print-surrogate`（已从 `main` 建好）。只在这里改。
- 只用 Python 标准库，不装依赖。没有别的 agent 在并行干活。

## 记录要求

做完在本文件末尾追加「## 完成记录」（在你的分支里提交）：做了什么、测试命令和结果（四套的数字）、缺陷植入自检的结果、代理码怎么显示的取舍、遇到的问题、没做的事。

提交时用 `git add <具体文件>`，**不要 `git add -A`**——这个仓库踩过把 `__pycache__/*.pyc` 提交进分支的坑。

## 回复

回复里只写：做完了哪些、测试结果、植入自检结果、取舍各一句话、有没有要主控决定的事。命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 完成记录

### 做了什么

- `bin/drover` 增加仅供输出使用的 `print_text()`，只替换三个调用点：`cmd_done()` 的成功报告、失败理由，以及未配置主控时 `issue()` 打印的任务正文。
- `tests/check-result.py` 新增三项回归：含高低代理码正文的真实 CLI 返回正常判据码 8 / 9；手动重发正文正确显示且不改状态文件；发布遇到真实 UTF-8 编码错误时保留旧 `.check-result`、打印 `WARNING: 未能发布`，并保持 done / 未完成事件语义。
- 判据函数、报告生成、原始理由、看板渲染均未修改。

### 测试命令和结果

1. RED（生产代码未改）：`python3 tests/check-result.py CheckResult.test_publish_encoding_error_preserves_done`，退出 1；`true` / `false` 两个子用例分别在原第 394 / 389 行裸 `print` 抛 `UnicodeEncodeError`。失败不是导入或 fixture 问题。
2. GREEN：修复两个报告出口后，同命令退出 0。
3. 正文出口 RED：`python3 tests/check-result.py CheckResult.test_surrogate_body_preserves_done CheckResult.test_surrogate_body_manual_resend`，正文 done 用例通过，手动重发因 `issue()` 的裸 `print(text)` 抛 `UnicodeEncodeError`、CLI 退出 1 而失败；修复该出口后，连同发布回归共 3 项全部通过。
4. 全量：`for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done`，退出 0。criteria：2 个 PASS 块；drover：2 个 PASS 块；install：9 项测试；drover-board：13 个 PASS 块，附带 check-result：20 项测试（16.514 秒），全绿。
5. 调用者环境对照：分别清除 `PYTHONIOENCODING`、在外层设成 `ascii:strict`、在外层设成 `utf-8:surrogateescape`，逐次运行三项新增测试，每次均 3 项通过。测试本身不设置该环境变量。
6. `git diff --check`、两个改动 Python 文件的 `ast.parse` 语法检查通过。

### 独立缺陷植入自检

用前台 Python 脚本创建临时目录，将 `bin/drover` 和 `bin/drover-board` 一起复制进去，`DROVER_BIN` / `DROVER_BOARD_BIN` 均指向绝对路径；每次只改一个缺陷，再运行对应新增测试：

| 临时植入 | 结果 | 还原后 |
|---|---|---|
| 成功报告改回 `print(line)` | 退出 1，`UnicodeEncodeError` | 退出 0 |
| 失败理由改回 `print(f"  - {p}")` | 退出 1，`UnicodeEncodeError` | 退出 0 |
| 手动重发正文改回 `print(text)` | 退出 1，CLI 因 `UnicodeEncodeError` 崩溃 | 退出 0 |
| 发布旁路移除 `UnicodeError` 捕获 | 退出 1，真实 JSON 写入发生 `UnicodeEncodeError` | 退出 0 |

两个临时副本最终均与工作区文件逐字节一致；植入改动没有进入工作区或提交。

### 实现时的取舍

- 显示形式选择小写十六进制 `\ud800` / `\udcff` 等可读转义；仅输出字符串中的 U+D800–U+DFFF 被转换，正常中文、NBSP、emoji 原样保留，不改原始正文或理由，也不改变全局标准流错误策略。
- 只处理确实承载任务正文或判据理由的三个输出点；手动重发属于任务文件要求一并检查的正文出口，其余打印点不扩展。
- 当前分支已经删除正文「验收：…」覆盖 `CHECK_CMD` 的功能，旧回归不能原样搬回。新发布回归在 `setup()` 后直接给内存中的 `CHECK_CMD` 赋含 U+DCFF 的 shell 注释，真实执行判据、真实触发 JSON 文件编码错误、真实调用 `cmd_done()`；不伪造判据结果或写文件异常。独立的真实 CLI 测试覆盖含代理码正文返回 8 / 9，不重新启用旧覆盖语法。
- 发布回归自建严格 UTF-8 `TextIOWrapper`，CLI 回归用 `-I` 忽略 Python 环境变量并显式固定标准流为严格 UTF-8，因此调用者环境不能掩盖裸 `print` 的缺陷。

### 遇到的问题、没做的事

唯一与任务原描述不同的是正文已不再进入验收命令，以上测试拆分保留了现行设计和原回归要守的发布旁路。无需主控另作设计决定。未处理欠账 9 / 10，未改 ROADMAP、看板或判据逻辑，未装依赖、未安装服务、未接触真实项目或 corral；只提交当前分支，不合并、不推送。所有命令都已在前台等待结束。

## 主控审查

2026-09-21，drover/main 审 `9d155a2`。**结论：可以合并，0 条必须改。**

生产代码只加了一个 3 行的 `print_text()` 和 3 个调用点（`issue()` 的正文回显、`cmd_done()` 的失败理由和成功报告），`re` 早就导入了。范围干净：`bin/drover`、`tests/check-result.py`、本任务文件三个，没有 `.pyc`。四套主控自己重跑全绿，`check-result` 从 17 项涨到 20 项，数字和完成记录对得上。

**独立植入自检**：把 `print_text` 退化成裸 `print(text)`，`check-result` 当场 1 failure + 2 errors，报的正是 `UnicodeEncodeError: ... position 17: surrogates not allowed`，守得住。

**这件活的关键一条我单独验了**——老那条回归就是栽在「依赖调用者的 `PYTHONIOENCODING`」上才被 `84f76c3` 撤掉的，所以新写法必须不吃环境。四种环境各跑三条新测试：

| `PYTHONIOENCODING` | `test_surrogate_body_preserves_done` | `..._manual_resend` | `test_publish_encoding_error_preserves_done` |
|---|---|---|---|
| 不设 | 绿 | 绿 | 绿 |
| `ascii:strict` | 绿 | 绿 | 绿 |
| `utf-8:surrogateescape` | 绿 | 绿 | 绿 |
| `latin-1:strict` | 绿 | 绿 | 绿 |

做法是测试自己用 `-I` 忽略环境变量、再显式把标准流固定成严格 UTF-8。**欠账 11 的连带项到此了结**：`m10` 那个 `except (OSError, UnicodeError)` 重新有测试守着了。

### 取舍表态

- 「代理码只在输出时转义成 `\udxxx`，原始正文和理由不动」——同意，和 `m13` 刚定的那条边界（显示层不许改写数据）一致。
- 「只处理确实承载任务正文 / 判据理由的三个输出点，其余 print 不扩展」——同意，这正是任务文件里写的范围。
- 「新发布回归给内存里的 `CHECK_CMD` 赋含 U+DCFF 的 shell 注释来触发真实 JSON 写入编码错误，不伪造异常」——同意。本分支已经没有正文覆盖 `CHECK_CMD` 的语法（`29ed637` 删了），旧回归不能原样搬，这个替代路径是真实触发、不是 mock，比原来更好。

### 顺手实测发现的一条，记欠账，不挡合并

`drover list` 仍会被**标题**里的孤立代理码打崩（`bin/drover:591`，`print(f"  {current['id']} {current['title']}…")`）：

```
UnicodeEncodeError: 'utf-8' codec can't encode character '\ud800' in position 12
```

合成仓库实测：标题带代理码、正文干净时，**`drover done` 不崩**（这件活的目标达成，退出码 8、报告完整），但 `drover list` 退出 1。

**不挡合并**，两条理由：① 既有问题，`main` 一模一样会崩，本次没制造也没扩大；② 任务文件里我自己写的「只处理会吃到任务正文 / 判据理由的那些，其余不碰」把它划在范围外。按分级标准这是「建议改」，进欠账清单。
