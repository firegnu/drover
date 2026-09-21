# 任务：分支名原样传递，别让 Unicode 空白把门 2 蒙过去

2026-09-22，drover/main 交给 drover/dev-ref（Codex，常规档：gpt-6-astra / high）。
路由：常规 / **交叉审查要**（路由：档位拿不准——常规 0.53、重 0.47、置信度 0.30，按技能「拿不准用常规」；交叉审查 `core_rules` 0.82，和 `m9` 那次同量级，它碰的正是判据的分支识别）。
你是被委派的 agent：照本文件做，不要再开别的 agent。

**这是 drover 自举的第二件活**（队列 id `T2`）。

## 先读

1. `AGENTS.md`（「硬规矩」「技术约束」「测试」）
2. **`docs/任务/m9-drop-branch-glob 交叉审查.md` 的「### 4. 建议改：分支名应原样传递」那一条**——审查者当初实测复现的原文，改法也在那里。
3. `bin/drover-board` 的 `task_branches()` 和 `criteria()` 里第 2 条那一段
4. `tests/criteria.sh` 里判据第 2 条相关的用例
5. 本文件

## 主控已经实测复现，你可以直接照着造

合成仓库：`main` 上一个提交当 `base_sha`；`feature/merged` 停在 base（已合入）；另建一个**末尾带 NBSP** 的分支 `feature/merged `，让它有一个未合入的提交。

```
git 眼里：    feature/merged
              feature/merged\u{a0}     ← 未合入
              main

drover 眼里： 'feature/merged'
              'feature/merged'         ← 被 strip() 裁成了同一个名字

门 2 → ✓ 过 | 2 个都已经是 main 的祖先：feature/merged、feature/merged
```

**未合入的分支被裁成已合入的那个，门 2 判过**——正是止损点里写死不许发生的「没做完却判成做完了」。而且理由里两个名字一模一样，人也看不出哪里不对。

另一条：含 **U+2028**（行分隔符）的分支名会被 `splitlines()` 拆成两条不存在的 ref，两条都查询失败，门 2 判不过（假阴性，方向安全，但报的分支名是错的）。

> **这两条旧版就有，不是 `m9` 引入的**——审查者用旧版同一 fixture 对照确认过。

## 要做的

`bin/drover-board` 的 `task_branches()`：

1. **只按 ASCII 换行切分**。`str.splitlines()` 会在 U+2028 / U+2029 / U+0085 等处也断开，不能用在 ref 清单上。
2. **不对分支名做 Unicode `strip()`**。现在的 `b.strip()` 会吃掉 NBSP 这类合法 ref 字符。
3. **查询用完整 ref**（`refs/heads/<name>`），显示时再去掉固定的 `refs/heads/` 前缀。完整 ref 一并避免短名歧义。
4. `main` 的排除照旧（现在比的是短名，改完注意别比错层）。
5. 枚举失败、退出码三分（0 / 1 / 其它）、`LC_ALL=C`、超时和异常处理**全部原样保留**——那是 `m9`/`m10` 的成果，一个字都不要退回去。

## 验收（先写测试，确认因为目标行为没实现而失败，再实现）

1. **末尾 NBSP 那条**：正常 `feature/merged`（已合入）和 `feature/merged `（未合入）并存时，门 2 **判不过**，理由里出现的是**真正未合入的那个名字**（要能和已合入的那个区分开，别两个都显示成 `feature/merged`）。
2. **U+2028 那条**：含 U+2028 的分支名不被拆成两条，作为一条完整 ref 处理，结论和理由都对得上。
3. **普通分支名一切照旧**：现有用例全绿，短名显示不带 `refs/heads/` 前缀。
4. **`main` 仍然永远排除**（改成完整 ref 之后尤其要验）。
5. 四个套件全绿：`for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done`

**断言有效性自检**：往实现里逐条植入缺陷，确认对应断言变红，至少包括——(a) 改回 `splitlines()`；(b) 改回 `b.strip()`；(c) 去掉 `main` 的排除；(d) 显示时不去 `refs/heads/` 前缀。**任一植入之后测试仍全绿，说明那条断言守不住，重写它。**

> **跑测试的注意事项**（这个仓库连着栽过几次）：
> - 植入自检要把 `drover` 和 `drover-board` **两个文件一起复制**到同一个临时目录（`task_bin_path()` 找的是 board 副本旁边的 `drover`）。
> - `tests/check-result.py` 的 `DROVER_BIN` / `DROVER_BOARD_BIN` 要用**绝对路径**。
> - **不要设 `PYTHONIOENCODING`**，用干净环境跑。
> - 植入代码里别写 `except Exception: pass`，会吞掉守线抛的 `AssertionError`。

## 不要做

- 不要改 `docs/ROADMAP.md`、不要动 `docs/任务/` 下已有的历史任务文件。
- **不要改判据语义**：三条门的结论、`base_sha` 判别式、退出码三分处理都不动。
- 不要动 `.check-result` 的字段、陈旧判定或发布逻辑。
- 不要修 `print(line)` 遇到孤立代理码会崩那个既有问题（欠账 11，用户已定不修）。
- 不要引入第三方包、不要引入新配置项。
- 不要碰 `~/.drover/` 下的真实交接目录、`~/.review/`、`~/wt/`、`~/.local/bin/`、launchd。
- 不要合并到 main，不要推送。只在 `m12-ref-names` 上提交。
- 不要按项目名或路径批量杀进程（`pkill -f drover` 这类）。
- 拿主意的地方写进本文件「实现时的取舍」，并在回复里列出。

## 记录要求

做完在本文件末尾追加「## 完成记录」：做了什么、测试命令和结果、植入自检逐条结果、没做的事。

## 回复

只写：做完了哪些、测试结果、取舍各一句话、有没有要主控决定的事。命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 实现时的取舍

- 保留 `task_branches()` 返回短名列表的接口：枚举和祖先查询使用完整 `refs/heads/…`，查询后仅去掉固定前缀；`criteria()` 再补前缀查询分支和 main，显示保留原始 Unicode 字符，不引入转义格式。
- 复用已有普通分支、遗留分支、main 排除和错误处理回归，新增同名 tag 场景覆盖 Git 短名歧义；不改判据语义，无需主控另作决定。

## 完成记录

- `bin/drover-board`：枚举改用 `%(refname)`，只按 ASCII `\n` 切分，不再对 ref 做 `strip()`；按完整 ref 排除 main，门 2 两次祖先查询均使用完整 ref。枚举失败、退出码三分、`LC_ALL=C`、超时和异常处理保持原样。
- `tests/criteria.sh`：合成仓库验证普通已合入分支与末尾 NBSP 未合入分支并存、NBSP 合入后通过、U+2028 分支合入前后结论与完整名字对应、同名 tag 与 `core.warnAmbiguousRefs` 两种设置；精确断言理由文本，显示不带 `refs/heads/`。

### RED → GREEN

逐步执行 `env -u PYTHONIOENCODING bash tests/criteria.sh`，每步都等待前台命令结束：

1. NBSP 回归先以退出码 1 失败：门 2 错判 True，理由中出现两个 `feature/merged`；去掉 `strip()` 后整个判据套件通过。
2. U+2028 回归先以退出码 1 失败：已合入的分支被拆成 `feature/line` / `separator`，两条查询均退出 128；改为 `split("\n")` 后整个判据套件通过。
3. 同名 tag 回归先以退出码 1 失败：理由错误显示 `heads/feature/line\u2028separator`；改用完整 ref、显示仅去固定前缀后整个判据套件通过。

### 全套与植入自检

- `env -u PYTHONIOENCODING bash -c 'for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done'`：退出码 0，四套全绿，含安装 9 项和核对记录 17 项；安装测试只使用临时 HOME 和现有沙箱。所有命令均在前台跑完，未设置 `PYTHONIOENCODING`。
- 自检用标准库 Python 驱动：将 `drover` 与 `drover-board` 一起复制到同一临时目录，`DROVER_BIN` / `DROVER_BOARD_BIN` 均为绝对路径；先跑未改副本的 `bash tests/criteria.sh`，退出码 0。随后每次从原始实现独立植入一条缺陷，再跑同一套件：
  - (a) `result.stdout.split("\n")` → `result.stdout.splitlines()`：退出码 1，`U+2028 branch must stay intact` 断言失败。
  - (b) `for b in out:` → `for b in (b.strip() for b in out):`：退出码 1，`NBSP branch must block` 断言失败。
  - (c) 去掉完整 main ref 的排除条件：退出码 1，`criterion 2 explains the empty branch set` 断言失败（main 被计入）。
  - (d) 三处短名清单的显示统一加回 `refs/heads/` 前缀：退出码 1，NBSP 未合入理由的精确文本断言失败。
- 四个副本均先通过 Python `compile()`；失败输出没有 `SyntaxError` / `FileNotFoundError`，没有吞掉断言的异常处理；生产工作区未植入缺陷。
- `git diff --check`：通过。
- 未改 ROADMAP、历史任务文件、`.check-result` 或孤立代理码既有问题；未访问真实交接目录、改 corral、安装到真实 HOME、动 launchd、开关 agent、合并 main 或推送。只提交在 `m12-ref-names`，交叉审查留给主控安排。

## 主控审查

2026-09-22，drover/main。**结论：通过，可以进交叉审查。**

- **四个套件自己重跑全绿**（干净环境）。
- **用主控那个 NBSP 合成仓库实测，修好了**：

  ```
  改动前： 本次分支 ['feature/merged', 'feature/merged']   门 2 → ✓ 过（误过）
  改动后： 本次分支 ['feature/merged', 'feature/merged\xa0'] 门 2 → ✗ 不过
  ```

  理由里保住了 NBSP：`'还没合进 main：feature/merged\xa0'`——报的确实是真正未合入的那个，不是裁过的同名分支。这条单看终端输出分辨不出（NBSP 不可见），**用 `repr` 验的**。
- **自己独立植入三条，全部因目标断言变红**：改回 `splitlines()` → `U+2028 branch must stay intact`；把 `strip()` 加回来 → `NBSP branch must block`；去掉 `main` 排除 → `criterion 2 explains the empty branch set`。
- **`m9` / `m10` 的成果逐条核对都还在**：`LC_ALL=C`、`ignoring broken ref` 检测、退出码三分（`== 1` 那支）、枚举失败进 `errors`。改 `task_branches` 最容易顺手把这些一起重写掉，没有发生。
- **范围核对**：只动了 `bin/drover-board`、`tests/criteria.sh`、本文件。ROADMAP 没碰，判据语义没动，`.check-result` 那套没碰。

### 取舍表态

- **查询用完整 ref、接口和显示保留短名** —— 同意。`b = b[len("refs/heads/"):]` 放在 `merge-base` 之后，查询拿到的是完整 ref、返回给调用方的是短名，`criteria()` 里第二次查询也补了前缀。两层各用各的形态，没有混。

### 留给交叉审查的点

1. **`split("\n")` 对 `for-each-ref` 输出的假设**：末尾换行产生的空串靠 `if not b` 跳过。ref 名里能不能出现别的东西让这个切分失效（比如 `\r`）？`%(refname)` 的输出保证是什么？
2. **去前缀用的是固定长度切片** `b[len("refs/heads/"):]`。`for-each-ref refs/heads/` 保证每条都带这个前缀吗？有没有路径能拿到不带前缀的 ref。
3. **`main` 的排除改成比完整 ref** 之后，`MAIN_BRANCH` 若被配成别的值（现在硬编码 `"main"`）会不会有层级错配。
