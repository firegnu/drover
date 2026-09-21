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
