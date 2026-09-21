# 任务：交叉审查 m12-ref-names（分支名原样传递）

2026-09-22，drover/main 交给 drover/review-ref（Codex，重档：gpt-6-astra / xhigh）。
路由：交叉审查要（`core_rules` 0.82）。
你是被委派的 agent：**只读审查**，不改代码、不提交、不切分支。不要再开别的 agent。

## 背景

drover 的完成判据门 2 问「这次任务建的分支都合进 main 了吗」。识别分支靠 `base_sha`（`m9` 定的），不看名字。

**本次修的是一个危险方向的误判**：`task_branches()` 原来用 `splitlines()` 切分、对每个名字 `strip()`，会改写 git 接受的合法分支名——

```
改动前： 本次分支 ['feature/merged', 'feature/merged']     门 2 → ✓ 过（误过）
改动后： 本次分支 ['feature/merged', 'feature/merged\xa0']   门 2 → ✗ 不过
```

末尾带 NBSP 的 `feature/merged `（未合入）被裁成 `feature/merged`（已合入），门 2 判过——**正是止损点里写死不许发生的「没做完却判成做完了」**。含 U+2028 的名字还会被 `splitlines()` 拆成两条不存在的 ref。这两条**旧版就有**，`m9` 的交叉审查实测复现过（见 `docs/任务/m9-drop-branch-glob 交叉审查.md` 第 4 条）。

改法：`%(refname)` 取完整 ref、`split("\n")` 只按 ASCII 换行、不做 `strip()`、查询用完整 ref、显示时切掉 `refs/heads/` 前缀。

**主控已审过**（结论在任务文件末尾「## 主控审查」）：四套全绿；NBSP 合成仓库实测修好了、理由里保住了 NBSP（用 `repr` 验的）；独立植入三条全红；逐条核对 `m9`/`m10` 的成果（`LC_ALL=C`、坏 ref 检测、退出码三分、枚举失败进 `errors`）都还在。**不要重复这些。**

## 先读

1. `AGENTS.md`（「硬规矩」「技术约束」「测试」）
2. `docs/ROADMAP.md`「判据第 2 条（本次任务建的分支）」整节 + 「这条判据的已知限制」
3. `docs/任务/m12-ref-names 分支名原样传递.md`（任务书 + 取舍 + 完成记录 + 主控审查）
4. `docs/任务/m9-drop-branch-glob 交叉审查.md` 第 4 条（这个问题的原始发现）
5. 本文件

## 要审查的代码

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/review-m12-ref-names`（**detached HEAD**，指向被审提交 `7bbddff`）。dev agent 在另一个目录，别碰它。
- 改动：`git diff main...m12-ref-names`
- **只读**：不改文件、不提交、不切分支、不合并。
- 可以跑四个套件。验断言有效性用临时副本：**`drover` 和 `drover-board` 两个文件一起复制**到同一临时目录（`task_bin_path()` 找的是 board 旁边的 `drover`），副本放 `/tmp`，不要改 worktree 里的文件。`tests/check-result.py` 的 `DROVER_BIN`/`DROVER_BOARD_BIN` 要用绝对路径，**不要设 `PYTHONIOENCODING`**。
- **不能碰**：`~/.drover/`、`~/.review/`、`~/wt/`、`~/.local/bin/`、launchd、真的 jb-finetune。不要 `pkill -f drover`。

## 重点看（主控列的）

1. **`split("\n")` 对 `for-each-ref` 输出的假设够不够稳**。末尾换行产生的空串靠 `if not b` 跳过。`%(refname)` 的输出格式保证是什么？ref 名里能不能出现 `\r` 或别的东西让这个切分失效？git 对 ref 名的合法字符规则（`git check-ref-format`）在这里意味着什么？
2. **去前缀用的是固定长度切片 `b[len("refs/heads/"):]`**。`for-each-ref refs/heads/` 保证每条输出都带这个前缀吗？有没有路径能拿到不带前缀的 ref，导致切错字符。
3. **`main` 的排除改成比完整 ref** `f"refs/heads/{MAIN_BRANCH}"`。`MAIN_BRANCH` 现在硬编码 `"main"`，若将来可配，这里会不会层级错配。另外 `criteria()` 里第二次查询也补了前缀，两处是否一致。
4. **还有没有别的地方仍在用短名做查询或比较**，会因为这次改动产生新的不一致（`criteria()` 的 `left` 那段、错误消息里的分支名、显示层）。
5. **U+2028 那条修好了没有**：含 U+2028 的分支名现在作为一条完整 ref 处理，结论和理由是否都对。顺便看还有没有别的 Unicode 行分隔符（U+2029、U+0085）会出问题。
6. **测试有效性**：新增的回归有没有被别的机制顺带满足？NBSP 那条断言是否真的能区分「报了带 NBSP 的名字」和「报了裁过的同名分支」——终端里两者看起来一样，**断言必须在字节/码位层面区分**。请独立挑几条自己的植入验一验。
7. **`m9`/`m10` 的成果有没有被悄悄退回**：`LC_ALL=C`、`ignoring broken ref` 检测、`merge-base` 退出码三分（0/1/其它）、枚举失败和异常进 `errors`。主控核过一遍，你再独立核一遍。

## 输出

追加到**本文件**末尾「## 审查意见」。用绝对路径写：`/Users/firegnu/Developer/personal_projs/drover/docs/任务/m12-ref-names 交叉审查.md`——它在**主仓库工作区**里，不在你的审查 worktree 里；**只写这一个文件，别的什么都不要改**。

格式：先写一句结论（**可以合并** / **改完再合并**）；每条意见写级别（必须改 / 建议改 / 可以不改）、位置（文件:行）、问题、改法；最后对 dev 列的取舍逐条表态。

**分级请按「正常用会不会撞上」来定**：需要特意构造畸形输入才触发的，标「建议改」或「可以不改」，不要标「必须改」。

## 回复

只写结论和条数，最后一行写 DONE。

## 审查意见

**可以合并。** 0 条必须改，3 条建议改，1 条可以不改（本次）。门 2 的修复成立，未发现本次引入的判据回归；以下测试缺口和既有边界不要求再开一轮功能返工。

被审提交：`7bbddffdf16a7b28395b9d9854c0f9cfb9b4e792`；对照 main：`3fcfc1d22a2a631823287624088cc8562d433078`。行号均指被审提交。没有重跑主控已完成的四套全量回归，也没有重复其三项植入；本轮跑了独立合成探针、未改临时副本的判据套件及四项不同的植入。命令均在前台等待结束。

### 1. 建议改：同名 tag 回归只守住第二次查询的分支参数，另两个消歧点仍可退回而全绿

**位置：`tests/criteria.sh:131`；对应 `bin/drover-board:406`、`bin/drover-board:467`。**

当前实现这两处都是对的，问题在断言覆盖。现有同名 tag 指向 `base`，分支也包含 `base`，因此第一次查询无论选中 tag 还是分支都返回 0；同时没有名叫 `main` 的 tag，第二次查询的目标是否补前缀也无法区分。

独立从原始实现各植入一条缺陷，完整 `tests/criteria.sh` 均退出 **0**：

- 第一次查询把完整 `b` 改成 `b[len("refs/heads/"):]`，只在该查询点退回短名，返回接口不变。另造 `early → base → pending`，本地 `feature/task` 指向 pending、同名 tag 指向 early：原版门 2 为 False，变体将未合入分支当作遗留分支排除，门 2 为 True。
- 第二次查询保留分支完整 ref，只把 `f"refs/heads/{MAIN_BRANCH}"` 改回 `MAIN_BRANCH`。另造 main 停在 base、`feature/task` 指向 pending、tag `main` 也指向 pending：原版门 2 为 False，变体误查 tag 后为 True。

**改法：** 各补一个上述合成场景，断言 `task_branches()` 的本次/遗留分类和门 2 的结论、准确理由；分别植入这两处退回时须变红。可沿用现有测试结构，无须改生产逻辑。属于测试补强，不把变体的缺陷说成当前实现已有的缺陷。

### 2. 建议改：看板详情仍会把修复后的名字再次改写（既有显示问题）

**位置：`bin/drover-board:856`；取舍说明见 `docs/任务/m12-ref-names 分支名原样传递.md:86`。**

`criteria()` 和 `view_model()` 传递的理由保留原字符，但 `detail_lines()` 的 `" ".join(r["why"].split())` 会按 Unicode 空白再次拆分。直接喂入本次修复产出的理由，返回给绘制层的文本为：

```text
输入 repr：'还没合进 main：feature/name\xa0'
详情 repr：'✗ 门2：还没合进 main：feature/name'

输入 repr：'还没合进 main：feature/name\u2028tail'
详情 repr：'✗ 门2：还没合进 main：feature/name tail'
```

U+2029、U+0085 同样变成 ASCII 空格。这里不是终端看起来相似，而是码位实际丢失/改变。门 2 仍正确阻挡，`drover done` 的 `criteria_report()` 也原样拼接理由；受影响的是详情中的名字。与 main 的函数 AST 对照确认该显示逻辑完全未改，不能算本次新引入的误判。按任务分级，特殊名字下的既有显示问题不阻断合并。

**改法：** 详情压平多行理由时只处理实际的 ASCII 换行/回车，保留合法 ref 的 Unicode 字符；给 `detail_lines()` 补一个精确文本断言。继续采用原始 Unicode 显示即可，不要求新增转义格式。完成说明应区分「判据理由已原样保留」与「整个 TUI 已原样显示」。

### 3. 建议改：待合并提交额外带入了生成的 Python 字节码

**位置：`bin/__pycache__/drover-boardcpython-312.pyc`（二进制，无行号）；`docs/任务/m12-ref-names 分支名原样传递.md:129`。**

实际 `git diff main...m12-ref-names` 是 **4 个文件**，其中包含 81,340 字节的 `.pyc`，不是主控记录写的三个。`git show --stat` 确认它由 `7bbddff` 的主控审查记录提交带入，开发实现提交 `1e5939f` 没有这个文件。它不是交叉审查跑出来的工作区文件：开工时已被 HEAD 跟踪，审查 worktree 始终干净。

**改法：** 从待合并内容中排除这份缓存，修正范围记录；若要防止重现，可另加 `__pycache__/` 忽略规则。正常启动已有 `sys.dont_write_bytecode = True`（`bin/drover:50`），本轮没有发现它导致实际功能回归，因此作为提交卫生建议，不定为判据阻塞。本审查没有执行删除。

### 4. 可以不改（本次）：其它主分支查询仍使用短名，不能把门 2 的修复描述为全链消歧

**位置：`bin/drover-board:439`、`:515`、`:554`、`:555`、`:711`；`bin/drover:110`。**

门 1、收尾记号范围、提交统计、核对记录的新鲜度和派发起点仍使用短名 `MAIN_BRANCH`。Git 对同名 tag/branch 的短名会优先解析 tag，完整 ref 才能明确命名空间。[Git 官方 revision 解析规则](https://git-scm.com/docs/gitrevisions#_specifying_revisions)

在第 1 条的 `main` 同名 tag 合成仓库里，真实 main 没动，门 1 仍报告前进；但本次修好的门 2 正确报告 `feature/task` 未合入。直接加载 main 版本对照，门 1 返回完全相同的结果，旧门 2 还会误过。**这是既有的其它查询边界，本次修复没有制造它。** `task_branches()` 的返回值仅在门 2 内消费，那里没有漏掉短名补前缀的调用。

**改法：** 本次可不扩大范围。后续若单独处理主分支消歧，应把上述读点及派发保存的起点一起核对，配同名 tag 回归；本轮不改 `.check-result` 或收尾判据。

### 七项重点核对结果

| 重点 | 独立核对结果 |
|---|---|
| 1. 仅按 ASCII 换行切分 | 成立。Git 拒绝 ref 中的 ASCII 控制字节、空格和 DEL，因此合法 ref 不含 LF/CR；实测 `check-ref-format` 拒绝 U+0001–U+0020 与 U+007F，NUL 无法作为 argv 内容。`text=True` 的 CR/LF 处理不会改写合法 ref；U+2028/U+2029/U+0085 保持为记录内字符。[官方命名规则](https://git-scm.com/docs/git-check-ref-format#_description) |
| 2. 固定前缀切片 | 成立。`%(refname)` 输出完整 ref，`refs/heads/` 模式限定该命名空间；没有使用 `:short` 或 host-language quoting。实测 tags、remotes、`refs/heads-extra/` 都未混入，`core.quotePath=true/false` 及打包 refs 后，输出字节均等于预期完整 ref 加 LF。[官方枚举与字段规则](https://git-scm.com/docs/git-for-each-ref) 无须添加对不可能前缀的兜底。 |
| 3. main 排除与两次查询 | 当前硬编码短名 `main` 的层级一致。临时将常量设为短名 `release/main` 并使用同名主分支，也正确排除、正确查询。未来若允许配置，值应定义为短分支名；完整 `refs/heads/...` 不是当前接口，不能据此要求现在加配置兼容。 |
| 4. 其它消费/显示点 | 门 2 的 `left`、已合入清单、排除清单、错误名前缀都按短名输出，查询按完整 ref；错误和排除理由中的 Unicode 也已独立验证。详情层和其它 main 查询的边界见第 2、4 条。 |
| 5. Unicode 行分隔符 | U+2028、U+2029、U+0085 各用独立仓库验证：清单恰好一个本次分支，未合入时 False、合入后 True，理由逐码位等于原名。没有错误拆分或混入前缀。 |
| 6. 断言有效性 | NBSP 的字符串全等断言有效，单独裁掉理由里的 NBSP（查询和 False 结论保留）会在该断言变红；第二次查询的分支参数退回短名会在同名 tag 断言变红。另两处消歧的测试缺口见第 1 条。 |
| 7. m9/m10 保留项 | `LC_ALL=C`、枚举 timeout=30、坏 ref 警告检测、异常转 `errors`、0/1/其它退出码分流、`errors` 优先于空集合全部保留；枚举异常处理和错误分支另作 AST 对照确认未改。判据基线套件通过真实中/法文警告前提及注入的非零/异常/超时回归。第二次查询的非零仍安全阻挡，原先未细分错误说明的行为没有退回或变化。 |

### 独立植入记录与证据

临时目录：`/tmp/drover-m12-review-wofkd0ri/`。包含 `probes.py`、`probe-results.json`、`mutations.py`、每个变体的成对脚本副本和 `.log` / `.json` 结果。

| 变体 | 判据套件退出码 | 目标结果 |
|---|---:|---|
| 未改副本 `baseline` | 0 | 建立本轮基线，含原有错误与 locale 回归。 |
| `report-strip-only` | 1 | 门 2 仍 False，精确理由断言抓到末尾 NBSP 被删；不是被结论断言顺带抓到。 |
| `second-query-short-branch` | 1 | 同名 tag 断言抓到门 2 错判 True。 |
| `first-query-short-branch` | 0 | 新增对照 fixture 确认会错误排除本次分支并误过，现套件未守住。 |
| `second-query-short-main` | 0 | 新增对照 fixture 确认会查询 tag `main` 并误过，现套件未守住。 |

运行命令为 `env -u PYTHONIOENCODING PYTHONDONTWRITEBYTECODE=1 python3 -B <临时目录>/probes.py`，以及相同环境下的 `mutations.py baseline report-strip-only second-query-short-branch` / `mutations.py first-query-short-branch second-query-short-main`。驱动逐一执行 `bash tests/criteria.sh`，`DROVER_BIN` / `DROVER_BOARD_BIN` 均指向同一临时目录内的绝对路径；没有设置 `PYTHONIOENCODING`。变体均先通过 `compile()`，两项红例没有 `SyntaxError` / `FileNotFoundError`，没有吞断言的异常处理。

`git diff --check main...m12-ref-names` 通过。写入审查意见前，主仓库与审查 worktree 的全部已跟踪文件内容哈希均与开工快照一致；审查 worktree 的 HEAD 与干净状态未变。本轮仓库内只追加本审查文件，没有改代码、测试、ROADMAP，没有提交、切分支、合并、访问真实交接目录或操作 agent。

### 对 dev 两项实现取舍逐条表态

1. **保留短名返回接口，查询使用完整 ref、显示不引入转义：同意。** 只剥固定前缀，再在门 2 的查询点补回，接口与查询形态一致；没有必要为这次修复改函数签名。判据理由已兑现原样传递；TUI 详情仍有第 2 条的既有折叠，完成说明不能覆盖它。
2. **复用普通分支/遗留/main 排除/错误回归，新增同名 tag 用例，不改判据语义：同意。** 无须重新拍板设计；新增用例确实守住第二次查询的分支消歧，但不是全部消歧点，建议按第 1 条补两条独立回归。本轮没有重开 ROADMAP 已接受的旧起点分支限制。
