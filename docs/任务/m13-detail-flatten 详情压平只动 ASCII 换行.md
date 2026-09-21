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
