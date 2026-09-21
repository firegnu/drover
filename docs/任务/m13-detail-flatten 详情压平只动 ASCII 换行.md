# 任务：看板详情压平理由时只动 ASCII 换行，别改写 Unicode

2026-09-21，drover/main 交给 drover/dev-flatten（Codex，常规档：gpt-6-astra / high）。
路由：常规 / 交叉审查不要（路由：档位拿不准——常规 0.66、轻 0.34、置信度 0.48，按技能「拿不准用常规」；交叉审查 `core_rules` 0.06、数据模型 0.02、并发 0.03，远低于 `m12` 那次的 0.82，纯显示层一行改动）。
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

1. `AGENTS.md`（尤其「硬规矩」「技术约束」「测试」三节）
2. `docs/任务/m12-ref-names 交叉审查.md` 的「### 2. 建议改」那一条——这个 bug 的完整复现和判定都在里面
3. `docs/任务/m12-ref-names 分支名原样传递.md`——上一件活为什么要「原样传递」，取舍记在第 86 行附近
4. `bin/drover-board` 的 `detail_lines()`（第 866 行起）和 `criteria()`（第 460 行起）
5. `tests/drover-board.sh`（第 270–290 行、第 400–430 行、第 505–520 行是现成的 `detail_lines` 断言样板）
6. 本文件

## 你在哪里干活

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/m13-detail-flatten`，分支 `m13-detail-flatten`（已从 `main` 建好）。只在这里改。
- 只用 Python 标准库，不装任何依赖，不需要装环境。
- 没有别的 agent 在并行干活，整个仓库归你，但**改动范围要小**，见「不要做」。

## 这个 bug 是什么

`bin/drover-board:899`：

```python
f'{mark} {r["name"]}：{" ".join(r["why"].split())}'
```

`str.split()` 不带参数按**所有 Unicode 空白**切分。`m12` 刚把分支名修成原样传递，到了这里又被改写回去：

```text
输入 why： '还没合进 main：feature/name\xa0'
详情输出： '✗ 门2：还没合进 main：feature/name'        ← 末尾 NBSP 没了

输入 why： '还没合进 main：feature/name tail'
详情输出： '✗ 门2：还没合进 main：feature/name tail'    ← U+2028 变成空格
```

U+2029、U+0085 同样被换成 ASCII 空格。**这不是终端看着像，是码位真的变了。**

判据本身是对的（门 2 正确阻挡），`drover done` 的 `criteria_report()` 也原样输出；**只有看板详情里的名字被改写**。这是既有显示问题，`m12` 一个字没动这段逻辑，交叉审查用 AST 对照确认过。

## 为什么这里需要压平

`criteria()` 第 487 行：`"why": "\n".join(errors)`——多条 git 查询失败时用 **ASCII 换行**拼成一条理由。详情是一行一个元组交给 curses 画的，带 `\n` 会把排版搞乱，所以必须压平。

**但压平只需要处理 ASCII 换行。** git 的 ref 名字里不可能有 `\n` `\r` `\t`（`git check-ref-format` 禁止所有 ASCII 控制字符），却完全可以有 NBSP、U+2028 这些 Unicode 字符——**这两类必须分开对待**。

## 要做的

1. **改 `detail_lines()` 里那一处压平**：只按 ASCII 换行和回车切分，连续的换行合成一个空格，其余字符（含 NBSP、U+2028、U+2029、U+0085）逐码位原样保留。
2. 保持「一个元组一行」这个不变量：压平后的文本里不能再有 `\n` 或 `\r`。
3. 改法自己定，但**要简单**——这是一行的活，不要为它造抽象、不要加配置项、不要加新模块。用了正则就在旁边写一句注释说明为什么只认 ASCII 换行。

## 验收（先写测试，确认它因为目标缺陷而失败，再实现）

在 `tests/drover-board.sh` 里补断言。**顺序按项目规矩来**：先写测试、在**没改** `bin/drover-board` 的情况下跑一遍确认它红了，而且红的原因是名字被改写（不是导入报错、不是 fixture 坏了），再动实现。

至少覆盖这几条，都要**逐码位精确相等**（用 `==` 比整串，不要用 `in` 或者只看长度）：

- 理由是 `'还没合进 main：feature/name\xa0'` → 详情那一行结尾的名字仍是 `feature/name\xa0`，NBSP 还在。
- 理由是 `'还没合进 main：feature/name tail'` → 仍是 `feature/name tail`，U+2028 没被换成空格。
- 理由里有 **ASCII 换行**（照 `criteria()` 第 487 行那样 `"\n".join([...])` 拼两条错误）→ 压成一行，输出里 `'\n' not in` 且 `'\r' not in`。
- 建议再加一条 U+2029 或 U+0085，和上面同样的口径。

跑法（四套都要绿，跑完把数字贴进完成记录）：

```sh
for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done
```

**另外做一次独立的缺陷植入自检**（项目里踩过「全绿其实没守住」的坑）：把你的实现临时改回 `" ".join(r["why"].split())`，确认新断言**红**；再改回来确认绿。自检的临时改动不要提交。

> 植入自检的两个已知坑，别再踩：临时目录里要把 `bin/drover` 和 `bin/drover-board` **两个文件一起**复制过去（`task_bin_path()` 找的是 board 副本旁边的 `drover`）；`DROVER_BIN` / `DROVER_BOARD_BIN` 要传**绝对路径**（测试内部会切 cwd）。

## 不要做

- **不要碰 `criteria()`、`criteria_report()`、`view_model()` 或任何判据逻辑**——理由的生产端 `m12` 已经修对了，这次只修消费端的显示。
- 不要动欠账 13（其它 `main` 查询仍用短名）。那是另一件活，范围大得多。
- 不要顺手改 `bin/drover:490` 那处 `.split()`——那是发布提醒的摘要，220 字符截断，不在本次范围里。
- 不要改看板配色、布局、滚动、刷新间隔。
- 不要给 TUI 加转义显示格式（把 NBSP 画成 `\xa0` 之类）——`m12` 交叉审查明确说了继续用原始 Unicode 显示就行。
- 不要装第三方包，不要引入标准库之外的依赖。
- 不要合并到 `main`，不要推送，不要开别的 agent。只在 `m13-detail-flatten` 上提交。
- 不要按项目名或路径批量杀进程（`pkill -f drover` 这类）：主控和别的 agent 的命令行里都带着项目名和工作目录，一条命令能把它们全杀掉。要停自己起的进程，用起的时候记下的 PID。
- 拿主意的地方写进完成记录的「实现时的取舍」，并在回复里列出来。
- 遇到「压平以后 curses 画不出来 / 报错」这类超出一行改动的情况，**停下来报告，等决定**，不要自己换个方案往下做。

## 记录要求

做完在本文件末尾追加「## 完成记录」（在你的分支里提交）：做了什么、测试命令和结果（四套的数字）、缺陷植入自检的结果、实现时的取舍、遇到的问题、没做的事。

提交时用 `git add <具体文件>`，**不要 `git add -A`**——这个仓库踩过把 `__pycache__/*.pyc` 提交进分支的坑。

## 回复

回复里只写：做完了哪些、测试结果、植入自检结果、取舍各一句话、有没有要主控决定的事。命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 完成记录

- `bin/drover-board`：只改 `detail_lines()` 的理由压平，连续 ASCII CR/LF 替换为一个空格，其他字符逐码位保留；旁注说明 Unicode 空白不能折叠。
- `tests/drover-board.sh`：新增 7 组整串精确相等断言，覆盖末尾 NBSP、U+2028、U+2029、U+0085、`"\n".join(errors)`、连续及混合 CR/LF、首尾换行和原有空格/tab；每组另验输出不含 CR/LF。

### RED → GREEN 和完整回归

- 先只改测试，运行 `bash tests/drover-board.sh`：退出 1，`AssertionError: 详情理由被改写` 明确显示实际串结尾为 `feature/name`，预期为 `feature/name\xa0`。此时生产文件未改。
- 改实现后同一命令退出 0，7 组新增断言和原有看板回归全部通过。
- 运行 `for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done`，最终退出 0：criteria **2 个 PASS 块**、drover **2 个 PASS 块**、install **9 项**、drover-board **13 个 PASS 块 + 17 项 check-result 测试**；新增 7 组断言位于现有记账块内，不另增加 PASS 块。
- `bash -n tests/drover-board.sh` 和 `git diff --check` 均通过。所有命令均在前台等待结束。

### 独立缺陷植入自检

临时目录 `/tmp/drover-m13-mutation-jhiyjrx8` 中成对复制 `drover`、`drover-board`，两个覆盖变量均使用绝对路径。

1. 仅把副本中的压平表达式改回 `" ".join(r["why"].split())`，先经 `compile()` 确认语法有效，再运行 `bash tests/drover-board.sh`：退出 **1**，命中新增 NBSP 整串相等断言，无导入或 fixture 错误；日志为 `mutant.log`。
2. 恢复副本后核对两个脚本与工作区逐字节一致，使用相同路径重跑：退出 **0**，13 个 PASS 块及 17 项测试全部通过；日志为 `restored.log`。临时缺陷未写入工作区、未提交。

### 实现时的取舍

- 用已有 `re` 模块的 `re.sub(r"[\r\n]+", " ", why)`；不做 `strip()`，保留换行两侧原有空格、tab 和 Unicode 字符，首尾 CR/LF 也只替换成一个空格。使用局部变量保持表达式简洁，不新增抽象、配置或模块。
- 复用已有合成项目，在 `detail_lines()` 返回文本处比整串；清空测试副本的 `crew`，使其他标成 `bad` 的 agent 行不混入目标结果。不增加真实 git/agent 调用或转义显示格式。

### 遇到的问题、没做的事

- 首次测试运行还选中了 fixture 中 `eta/ghost` 的 `bad` 行，不能单凭那次失败作为 RED；清空副本 `crew` 后，在生产代码未改时重跑，确认只有末尾 NBSP 缺失导致失败。未遇到绘制报错，没有需要主控决定的事项。
- 未改 `criteria()`、`criteria_report()`、`view_model()`、其他判据、通知摘要、布局配色、滚动或刷新；未处理欠账 13，未改 ROADMAP/HANDOFF，未操作真实项目、agent、安装路径或 launchd；只在 `m13-detail-flatten` 提交，不合并、不推送。

## 主控审查

2026-09-21，drover/main 审。**结论：改完再合并——1 条必须改。**

核实过的：生产代码只动 `detail_lines()` 一处（`bin/drover-board:898`），`re` 早就导入了；范围干净，只有 `bin/drover-board`、`tests/drover-board.sh`、本任务文件三个，没有 `.pyc`。四套主控自己重跑全绿，数字和完成记录对得上（criteria 2 块 / drover 2 块 / install 9 项 / 看板 13 块 + 17 项）。独立植入自检也自己做了一遍：把压平换回 `" ".join(r["why"].split())`，新断言当场红，报的正是「详情理由被改写：…feature/name != …feature/name\xa0」，守得住。

另外做了一次端到端实测（任务文件里没要求，是为了堵「压平完 curses 画不出来」那个口子）：把四种理由灌进真实项目的 view_model，走 `draw()` 画进假屏幕 5 种尺寸（10x40 / 24x80 / 6x20 / 60x200 / 3x12），不崩、不越界，屏幕缓冲里仍带原码位。`width()` 对 `\xa0` ` ` ` ` `\x85` 都算 1 格。

### 必须改 1：新正则太窄，放进来 7 个旧代码挡着的 ASCII 控制字符

`re.sub(r"[\r\n]+", " ", why)` 只吞 `\n` `\r`。旧的 `str.split()` 吞的 ASCII 是 **`\t \n \v \f \r \x1c \x1d \x1e \x1f`** 九个（实测枚举 0x00–0x7f 得出），所以这次改动**放行了 `\t \v \f \x1c \x1d \x1e \x1f` 七个**——这是本次引入的回退，不是既有问题。

`\t` 会让看板崩。实测（真 pty + `curses.wrapper`，80x24）：

```
末行右边缘 纯文本:  ok
末行右边缘 带 tab:  error('addwstr() returned ERR')   ← put() 没有 try/except，直接崩掉退出
末行右边缘 单 tab:  error('addwstr() returned ERR')
中间行   长 tab:  ok（不崩，但 ncurses 折行，把下一行糊掉）
```

`put()`（`bin/drover-board:845`）按 `width()` 算宽度，`cell('\t')` 算 1 格，而终端把 tab 展开到下一个制表位——算出来够、画出去不够。

**怎么进到 `why` 里**：分支名进不来（git 禁止 ref 名含控制字符），但 `check_cmd` 进得来（`.drover.conf` 的 `CHECK_CMD`，或队列条目里「验收：…」那行，都是人手写的），收尾记号的 commit subject 也进得来（`find_done_mark` 的 `f"{sha[:7]} {subject}"`）。

**改法**：把 ASCII 控制字符照旧全吞掉，只放过非 ASCII——`re.sub(r"[\t\n\v\f\r\x1c-\x1f]+", " ", why)`。这正好是「旧 `.split()` 的 ASCII 分隔符集合减去普通空格」，做到**对 ASCII 零回退、对 Unicode 才是这次要修的原样保留**。保留成串的普通空格是有意的差异，无害。

> `\x00` 不在此列：`str.split()` 本来就不吞它，改动前后一样会穿过去，**是既有边界，本次没制造也没扩大**，不在这件活范围里。

### 取舍逐条表态

- 「仅合并连续 CR/LF，其余逐码位保留」——**方向同意，范围要扩到全部 ASCII 控制字符**，见上。
- 「不 `strip()`，保留换行两侧原有空格和 tab」——空格同意；**tab 不同意**，按上条一并吞掉。
- 「清空测试副本的 `crew` 再比整串」——同意，这样断言不会被别的 `bad` 行干扰，是对的做法。
- 「用 `re.sub` 不造抽象、不加配置」——同意。

### 要改的测试

第 7 组用例 `"\r\n  错误甲\t \n  错误乙  \r"` 现在断言 tab 被保留，改法落地后期望值要跟着变（tab 变一个空格）。另外**补一条断言守住这次的回退**：理由里塞 `\t` 和 `\x1f`，断言输出里 `"\t" not in` 且不含任何 `\x00-\x1f` 的字符；同时 NBSP / U+2028 那几条一个字不动，证明两类确实分开处理。

## 返工记录

- 已处理主控审查的 1 条必须改：`detail_lines()` 改用 `re.sub(r"[\t\n\v\f\r\x1c-\x1f]+", " ", why)`，恢复旧 `split()` 对九种 ASCII 空白控制字符的压平，普通空格和非 ASCII 字符仍原样保留，注释同步更新。
- 原第 7 组期望值改成 tab 被替换为空格；新增一组含 tab、U+001F 及其余七种目标控制字符的理由，整串相等，并断言输出中无 U+0000–U+001F 字符。共 **8 组**，原 NBSP / U+2028 / U+2029 / U+0085 四组一个字未改。
- **RED**：只改测试，未改生产代码时运行 `bash tests/drover-board.sh`，退出 **1**，新断言报 `详情残留 ASCII 控制字符`，实际串明确残留 `\t`、`\x1f`、`\x0b`、`\x0c`、`\x1c`、`\x1d`、`\x1e`；无语法、导入或 fixture 错误。
- **GREEN**：修改实现后运行 `for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done`，退出 **0**：criteria **2 个 PASS 块**、drover **2 个 PASS 块**、install **9 项**、drover-board **13 个 PASS 块 + 17 项 check-result 测试**，新增断言全部通过。
- **独立植入自检**：在 `/tmp/drover-m13-rework-jeda3fna` 成对复制两个脚本，覆盖变量均用绝对路径。每个变体先经 `compile()`，再独立运行看板套件：① 退回仅 CR/LF 的正则，退出 **1**，命中新增 ASCII 控制字符残留断言（`crlf-only.log`）；② 退回旧 `" ".join(r["why"].split())`，退出 **1**，命中 NBSP 精确断言（`unicode-split.log`）。恢复后两个副本与工作区逐字节一致，重跑退出 **0**，13 块 + 17 项全绿（`restored.log`）；临时缺陷未进入工作区或提交。
- **取舍与边界**：按主控指定集合处理，不泛化为吞掉所有 ASCII 控制字符；测试输入不含 NUL，不改变 `\x00` 的既有行为。保留普通空格，不 `strip()`，不修改判据、绘制层或其他显示功能。原完成记录中“保留 tab”的取舍由本节更正。
- `bash -n tests/drover-board.sh`、`git diff --check` 通过；四条 Unicode 用例与审查提交逐行一致。所有命令前台等待结束，只提交本分支的三个指定文件，不合并、不推送，无需主控另作决定。

## 主控复核（返工后）

2026-09-21，drover/main 复核 `43d8a60`。**结论：可以合并，0 条待改。**

改法照单采纳：`re.sub(r"[\t\n\v\f\r\x1c-\x1f]+", " ", r["why"])`。测试两处也都改对了——第 7 组期望值跟着变（tab → 一个空格），新增一组把 `\t \x1f \v \f \x1c \x1d \x1e \r` 全塞进去，另加一条 `not any("\x00" <= ch <= "\x1f")` 的守线**罩住全部 8 组**，四条 Unicode 用例一个字没动。

主控自己重跑四套全绿，并独立做了两次缺陷植入，**两半各自都守得住**：

| 植入 | 谁报警 | 报的什么 |
|---|---|---|
| 正则缩回 `[\r\n]+` | 新增的控制字符守线 | `详情残留 ASCII 控制字符：…错误甲\t错误乙\x1f…` |
| 整个换回 `" ".join(why.split())` | 原有的 NBSP 整串断言 | `…feature/name != …feature/name\xa0` |

端到端再实测一遍（真实 view_model → `draw()` → 假屏幕 5 种尺寸）：NBSP 和 U+2028 逐码位保住，`make\ttest` 里的 tab 和 `\x1f` 都变成空格，**四种情况残留控制字符都是「无」**——崩溃路径关上了，要救的码位救住了，两类确实分开处理。

### 取舍表态

- 「压平指定九种 ASCII 控制字符，保留非 ASCII」——同意，正是要的口径。
- 「NUL 未动」——同意。`str.split()` 本来就不吞 `\x00`，改动前后一样穿过去，是既有边界（欠账里另记）。
