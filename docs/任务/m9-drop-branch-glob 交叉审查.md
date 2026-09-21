# 任务：交叉审查 m9-drop-branch-glob（判据第 2 条只认 base_sha）

2026-09-21，drover/main 交给 drover/review-glob（Codex，重档：gpt-6-astra / xhigh）。
路由：交叉审查要（core_rules 0.9）。
你是被委派的 agent：照本文件做，不要再开别的 agent。**只读审查**，不改代码、不提交、不切分支。

## 背景

drover 的完成判据有三条**门**和一条**依据**（依据是「收尾记号」，本次不动）。本次改的是**门的第 2 条**。

改动前：靠配置项 `BRANCH_GLOB`（一个 glob 模式）匹配出「里程碑分支」，再问它们是否都已合进 `main`。
改动后：**`BRANCH_GLOB` 整个删掉**，枚举所有本地分支（排除 `main`），用 `git merge-base --is-ancestor <base_sha> <branch>` 过滤出包含本次任务起点的分支，问它们是否都已合进 `main`。

**为什么删**：「里程碑」不是这个项目里的实体，只是用户对「某次功能完成」的叫法（他可能自己打 tag，drover 不读 tag）。识别「这次任务建的分支」的正确依据是 `base_sha`，不是名字模式。设计已定死在 `docs/ROADMAP.md`「判据第 2 条（本次任务建的分支）」那一节。

**主控已经审过什么**（结论在任务文件末尾「## 主控审查」）：四个套件自己重跑全绿；自己独立做了 4 次缺陷植入全部变红；抽看了 `task_branches` / `criteria`；实测老配置残留 `BRANCH_GLOB=` 无影响；核对了改动范围。**主控审查通过，所以不要重复这些，把力气花在下面「重点看」上。**

## 先读

1. `AGENTS.md`（「硬规矩」「技术约束」「测试」）
2. `docs/ROADMAP.md`：「完成判据：纯 git，零解析」整节，**特别是「判据第 2 条（本次任务建的分支）」和「这条判据的已知限制」**
3. `docs/任务/m9-drop-branch-glob 判据第2条只认base_sha.md`（任务书 + 实现时的取舍 + 完成记录 + 主控审查）
4. 本文件

## 要审查的代码

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/review-m9-drop-branch-glob`（**detached HEAD**，指向被审提交 `577c52b`）。这是你自己的 worktree，dev agent 在另一个目录，别去碰它。
- 改动：`git diff main...m9-drop-branch-glob`
- **只读**：不改任何文件、不提交、不切分支、不合并。
- 可以跑：`bash tests/criteria.sh`、`tests/drover.sh`、`tests/install.sh`、`tests/drover-board.sh`（都用合成仓库和假 corral，不花钱、不碰真实数据）。想验断言有效性，用 `DROVER_BOARD_BIN=<你自己的临时副本> bash tests/criteria.sh`，**副本放 `/tmp` 下，不要改 worktree 里的文件**。
- **不能碰**：`~/.drover/`（真实交接目录）、`~/.review/`、`~/wt/`、`~/.local/bin/`、launchd、真的 jb-finetune。不要 `pkill -f drover`（会杀掉主控和别的 agent）。

## 重点看（主控列的 7 条）

1. **行为翻转对不对**：过滤后一个分支都不剩时，结论从「不过」改成「过」。这是从保守变宽松，方向落在危险那侧。ROADMAP 说守纪律的项目（合并后删分支）「一个不剩」是正常收尾、该过。**有没有哪种真实情形，这个翻转会让「活没干完」被判成「干完了」，而 ROADMAP 那一节没覆盖到？**
2. **两种「一个不剩」的区分是否真的守得住**：有 `excluded`（有分支但都不含 `base_sha`）必须逐个列出被排除的分支名；没有 `excluded` 说「没有未合并的分支」。这是危险方向唯一的可见性保护——理由文字一旦混同，人就看不出判据是放过了一堆被排除的分支。**测试断言是真的守住了，还是被别的机制顺带满足？**
3. **枚举全部本地分支带来的新风险**：以前 glob 会把无关分支挡在外面，现在不会。`main` 的排除是唯一的硬编码过滤。有没有别的东西会混进分支列表（detached HEAD 的 worktree、`git branch --list` 在各种状态下的输出、分支名里的空格或奇怪字符、worktree 占用的分支）？`git branch --list --format=%(refname:short)` 的输出在这些情况下长什么样？
4. **`merge-base --is-ancestor` 退出码的三分处理**（0 = 是祖先 / 1 = 确定不是 / 其它 = 查询失败）有没有被削弱。这是 `m6` 交叉审查挖出来的假阳性修复：退出码 128 曾被当成「确定不包含」而静默排除分支。**确认它在新代码里原样还在，且新的空集合逻辑没有绕过它。**
5. **签名变更是否改干净**：`criteria()` 去掉了 `glob_pat` 形参，`milestone_branches` 改名 `task_branches`。调用方有 `bin/drover`（2 处）、`bin/drover-board`（2 处）和三个测试套件。**有没有漏掉的调用点、或者靠位置参数传值而没报错的地方？**
6. **测试是不是被削弱了**：`tests/criteria.sh` 的 fail 断言 51 → 49。主控核过删的 5 条是 glob 专有的、新增 3 条，净 −2。**独立核一遍：有没有哪条原本守着某个行为的断言，在改写中失去了守护力？** 这个项目上一件活三轮返工全栽在「断言被别的机制顺带满足」上。
7. **文档和代码是否一致**：`docs/手册.md`、`docs/QUICKSTART.md` 改过。`docs/ROADMAP.md` 是主控改的、**不在本次 diff 里**，但代码必须和它一致。**有没有哪里文档说的和代码做的不一样？**

## 输出

追加到**本文件**末尾「## 审查意见」。用绝对路径写：`/Users/firegnu/Developer/personal_projs/drover/docs/任务/m9-drop-branch-glob 交叉审查.md`——它在**主仓库工作区**里，不在你的审查 worktree 里；**只写这一个文件，别的什么都不要改**。

格式：
- 先写一句结论：**可以合并** 或 **改完再合并**。
- 每条意见写：级别（必须改 / 建议改 / 可以不改）、位置（文件:行）、问题、改法。
- 最后对 dev agent 列的 5 条「实现时的取舍」逐条表态。

## 回复

只写结论和条数（例如「可以合并，3 条建议改」），最后一行写 DONE。

## 审查意见

**改完再合并。** 2 条必须改，2 条建议改。

2026-09-21，drover/review-glob。被审 HEAD：`577c52b9ed2eae1c2dd064e44c91f326c99fbfa8`；对照 main：`3c2246a20434870999b7b22d211b2a4ec44a2e6f`。以下行号均指被审提交。本轮没有重跑主控已经完成的四套回归和四项缺陷植入；新增验证全部在 `/tmp` 合成仓库中进行，命令均已在前台跑完。

### 1. 必须改：分支枚举失败被当成「没有分支」，空集合翻转引入假阳性

**位置：`bin/drover-board:388`、`bin/drover-board:445`（根因还涉及既有的 `git()`，`bin/drover-board:58`）。**

`task_branches()` 通过只返回 stdout 的 `git()` 枚举分支。这个封装丢弃退出码和 stderr，异常也返回空字符串。因此新逻辑无法区分「枚举成功且没有其它分支」和「根本没有拿到可信的分支清单」；后者现在会返回 `ok=True / 没有未合并的分支`。这不属于 ROADMAP 已接受的「从旧起点建分支」限制。

独立实测了三种情况：

- 合成仓库有尚未合入的 `feature/unfinished`，正常时第 2 条为 False。设置常见的排序配置 `branch.sort=-committerdate`，暂时移走该分支 tip 的松散对象，枚举返回 **128、stdout 为空、stderr 为 `fatal: missing object … for refs/heads/feature/unfinished`**，新判据却变为 True。
- 不破坏任何对象，仅将合成仓库的 `branch.sort` 设成非法字段，枚举同样返回 128，错误被吞后仍通过。这可单独复现，无需对象损坏。
- 暂将该分支的 loose ref 内容改成 `not-a-sha`，枚举甚至返回 **0**，stdout 只有 `main`，stderr 为 `warning: ignoring broken ref refs/heads/feature/unfinished`，仍被说成「没有未合并的分支」。所以仅检查非零退出码还不够覆盖这条路径。

同一输入对照旧 `criteria(repo, base, "feature/*", "")`：后两种情况旧版 False，新版 True。另在第一个场景确认 `git status --porcelain` 为空、main 已前进、`find_done_mark()` 为 True；若区间中已经有一次先行收尾的记号，收尾依据不能替这道门识别查询失败。没有记号时引擎仍会停住，不把门误过夸大成无条件自动推进。

**改法：** 在分支枚举这一步保留退出码、stderr 和异常信息；枚举失败、超时或 Git 明确报告忽略坏 ref 时，将诊断放进返回值的 `errors`，不得进入空集合通过分支。只对成功且可信的清单应用空集合规则，无需修改 `base_sha` 设计，也不必全面重构共享 `git()`。补充「枚举非零退出」及「退出 0 但忽略坏 ref」的合成回归，断言第 2 条 False 且保留诊断。

### 2. 必须改：无 glob 的 `git branch --list` 会把本 worktree 的 detached HEAD 伪条目送入祖先查询

**位置：`bin/drover-board:388`、`bin/drover-board:390`。**

实测干净合成仓库：main 已前进、`feature/merged` 已是 main 的祖先，执行 `git checkout --detach main` 后，当前枚举输出为：

```text
(HEAD detached at refs/heads/main)
feature/merged
main
```

在另一个通过 `git worktree add --detach` 建出的 worktree 里，首行实测为 `(no branch)`。这两种都不是本地分支，但代码只排除 `main`，随后把伪条目交给 `merge-base`，返回 128，令第 2 条始终不过。相同的干净 detached 场景，旧版带 `feature/*` 时 True，新版 False。目标仓库临时 detached 检查历史版本时会遇到；仅仅存在一个 detached **兄弟** worktree，不会污染从 main worktree 发起的枚举，不能把正常交叉审查一概说成会卡住主控。

**改法：** 从 Git 的 ref 命名空间枚举真正的 `refs/heads/`（例如 `for-each-ref`），或对当前命令输出严格限定为真实分支；不要把伪条目的 128 改成可忽略的祖先查询结果。补充同一合成仓库在 attached / detached 两种 cwd 下分支清单和判据一致的用例，另保留 worktree 占用分支仍需核对的断言。此处是落实「所有本地分支」的枚举修正，不是改 ROADMAP 判别式。

### 3. 建议改：补上「候选为空且有查询错误」的独立回归

**位置：`tests/criteria.sh:170`、`bin/drover-board:443`。**

当前实现先处理 `errors` 再处理空集合，顺序正确。独立造出只有一个坏 tip 分支的仓库，实测 `task_branches()` 为 `([], [], [查询失败])`，当前第 2 条确实为 False。

但现有错误场景始终保留正常且已合入的兄弟分支。将临时副本中这一处 `if errors:` 改为 `if errors and brs:` 后，`DROVER_BOARD_BIN=<临时副本> bash tests/criteria.sh` **退出 0、全绿**；再用上面的空候选场景调用该副本，已验证它错误地返回 True。这说明测试没有守住此次空集合放行新增的错误组合，不是当前实现已写错。

**改法：** 在错误场景中再构造一次「没有正常候选分支，只有查询失败分支」，明确断言清单前提、False、分支名与 stderr；植入上述缺陷时须因这条断言变红。现有「有已合入兄弟分支」的用例继续保留，两个组合各有价值。

本轮临时副本和证据保留在 `/tmp/drover-m9-review-1es5utrx/`：`board-errors-only-with-current-branches`、`mutation-empty-errors.log`、`mutation-proof.json`。未改被审文件。

### 4. 建议改：分支名应原样传递，避免 Unicode 空白被拆分或裁掉（既有问题，可另立任务）

**位置：`bin/drover-board:388`、`bin/drover-board:390`。**

ASCII 空格、tab 和以 `-` 开头的分支名被 Git 拒绝；普通中文、`;`、`$` 实测均能正确作为一个 argv 参数查询。不过 Git 接受某些 Unicode 空白，而 Python 的 `splitlines()` / `strip()` 会改变这些合法名字。

实测同时存在已合入的 `feature/merged` 和未合入的 `feature/merged\u00a0`（这里 `\u00a0` 表示末尾一个真实的 NBSP）：对后者直接查询 `merge-base --is-ancestor` 返回 1，判据却把它裁成前者，返回 True，并显示 `feature/merged、feature/merged`。含 U+2028 的分支名则被 `splitlines()` 拆成两条不存在的 ref。已用旧版同一 fixture 对照，旧版也有这两个问题，所以不将它们冒充本次引入的合并阻塞。

**改法：** 解析清单时仅移除 Git 用来分隔记录的 ASCII 换行，不对合法 ref 做 Unicode `strip()`；查询使用完整 ref 可一并避免短名歧义，显示时再去掉固定的 `refs/heads/` 前缀。补充正常分支与末尾 NBSP 分支并存的断言，必须核对真正未合入的那个名字。

### 七项重点的核对结果

| 重点 | 结果 |
|---|---|
| 1. 空集合行为翻转 | 正常空集合及旧起点分支的既定取舍不重开；发现第 1 条新增假阳性，须先修。 |
| 2. 两种「一个不剩」的可见性 | `tests/criteria.sh:55` / `:57` 独立守空集合的结论与理由；`:206` 起守全排除结论、数量、两个分支名，并显式禁止「没有未合并的分支」。此 fixture 中其余两条判据不含这些名字或措辞，未发现被其它机制顺带满足。 |
| 3. 全量枚举的边界 | worktree 占用不会带入 `+` / `*`；`color.branch=always` 下自定义 format 仍无颜色干扰；兄弟 detached worktree 不额外贡献分支。当前 cwd detached 的伪条目是第 2 条问题；Unicode 名字的既有问题见第 4 条。 |
| 4. 祖先查询三分处理 | 0 / 1 / 其它的分流原样保留，`errors` 优先于空集合，现代码未绕过。真正缺口在更早的枚举阶段；空候选错误组合缺回归，见第 1、3 条。 |
| 5. 签名迁移 | 全文检索并检查生产调用 AST：`bin/drover:215` / `:233`、`bin/drover-board:186` / `:680` 均传正确的第三参数 `check_cmd`；看板两处仍用关键字 `do_check=False`。三个套件相关调用和预期已迁移，没有生产旧符号残留或位置参数错位。 |
| 6. 断言是否削弱 | 独立确认 `|| fail` 站点 51 → 49；另有一处独立 `fail` 两版均保留。逐项对应，删除 5 项 glob 专属检查、新增空集合结论/理由及所有已合入分支列名共 3 项，净 −2；未发现删掉非 glob 行为保护。问题在新增组合缺覆盖，不在这个净数量。 |
| 7. 文档和代码 | QUICKSTART、手册与 ROADMAP 的目标语义一致，旧配置残留说明也符合解析方式；没有需要重新拍板的设计差异。第 1、2 条属于代码没有在异常/特殊 Git 状态下兑现文档语义，应修实现。历史 HANDOFF 和 m6 任务不在本次改写范围。 |

### 五项实现取舍逐条表态

按开发任务「主控审查 → 取舍逐条表态」拆出的五项逐条回应：

1. **沿用 `base_sha`、不加分支快照：同意。** 从旧起点建分支的风险已由人接受，不重开设计。枚举失败放行属于另一种实现缺陷，须按第 1 条修复。
2. **测试使用 `feature/implementation`：同意。** 它确实守住不依赖 `m` 命名；分支名变更没有削弱未合入/已合入两种断言。
3. **全遗留场景删除合成仓库中的本次分支：同意。** 与取消 glob 后的真实集合一致；只改结论，不丢掉逐个列名及两种理由区别的保护。
4. **缺陷只植入独立临时副本：同意。** 本轮也遵循此方法；需要把第 3 条发现的仍全绿变体纳入回归，而非以此前 17 次变红推定组合已齐全。
5. **手册改动多于任务概述的处数：同意。** 补全现行语义、已知限制和排查步骤均直接属于此次变更，没有扩张到重新设计。

---

## 主控对审查意见的判断

2026-09-21，drover/main。**三条要改（1、2、3），第 4 条记欠账不挡合并。**

### 1. 枚举失败被当成「没有分支」 —— **必须改，采纳**

同意，而且这正是本次改动**新引入的危险方向假阳性**。旧版空集合判 `False`，枚举失败反而"安全地"卡住；翻转成 `True` 之后，拿不到可信分支清单就变成了误过——正是止损点里写死不许发生的那条。三种复现都成立，尤其「非法 `branch.sort` → 128」不需要对象损坏就能触发，「坏 ref → 退出码 0 但清单不全」证明只查退出码不够。

采纳它的改法：枚举这一步保留退出码 / stderr / 异常，失败或 git 报告忽略坏 ref 时进 `errors`，不得落入空集合通过分支。**不要全面重构共享的 `git()`**（那会波及无关调用点，超出本任务范围）。

### 2. detached HEAD 伪条目进入祖先查询 —— **必须改，采纳**

同意，也是本次引入的：旧版 `m[0-9]*` 之类的 glob 匹配不到 `(HEAD detached at …)` / `(no branch)`，去掉 glob 后它们混进了分支清单，交给 `merge-base` 得到 128，第 2 条永远不过。方向是假阴性（卡住，看得见），但仍是 bug。

采纳 `for-each-ref refs/heads/` 的改法。**这是落实「枚举所有本地分支」的正确写法，不是改 ROADMAP 的判别式。**

审查者对影响范围的描述准确、没有夸大（兄弟 detached worktree 不污染主 worktree 的枚举），这点记一笔。

### 3. 「候选为空且有查询错误」缺回归 —— 审查者标「建议改」，**主控升级为必须改**

升级理由：它守的正是第 1 条修复之后的行为。没有这条回归，第 1 条的修复就没有测试守着，下次重构很容易退回去。而且审查者已经用植入证明缺口是真的——把 `if errors:` 改成 `if errors and brs:` 后整套仍然全绿。

### 4. Unicode 空白分支名被 `splitlines()` / `strip()` 改写 —— **不改，记欠账**

审查者自己用旧版同一 fixture 对照确认过：**旧版也有这两个问题，不是本次引入的**，不构成本次合并的阻塞。按 `AGENTS.md`「注意到无关的问题就提一下，别顺手改」，本次不动，合并后记进 `HANDOFF.md` 欠账。

改第 2 条时注意别让它变得更糟即可（`for-each-ref` 的输出仍按行分隔，`splitlines()` 的问题依旧独立存在）。

## 复核意见

**还要改。**

2026-09-21，drover/review-glob。仅复核 `577c52b..ba09ff5`，实测 HEAD 为 `ba09ff5866e9e3cf0c2af578a824e290aa4d7fb8`；不重跑上一轮全面审查及四套回归，不重开已裁定搁置的 Unicode 分支名问题。

### 必须改：本地化的坏 ref 警告仍会绕过枚举错误检查

**位置：`bin/drover-board:397`；对应测试盲区：`tests/criteria.sh:313`。**

**问题：** 新实现只匹配英文 `warning: ignoring broken ref`，但枚举子进程继承调用者的 locale。Git 会翻译这条警告；非英文环境下即使清单因坏 ref 而不完整，退出码仍是 0，代码再次落入空集合通过。这正是本轮必须修复的第 1 条路径，没有完全堵住。

独立使用本机 Git 2.55.0，在 `/tmp` 合成仓库中将 `refs/heads/feature/unfinished` 暂改成 `not-a-sha`，同一个仓库只切换 `LC_ALL` / `LANG`，结果如下（均无 `LANGUAGE` 覆盖）：

| 环境 | 枚举退出码 / stdout | stderr | 第 2 条 |
|---|---|---|---|
| `C` | 0 / 只有 `main` | `warning: ignoring broken ref refs/heads/feature/unfinished` | False，进入 errors |
| `zh_CN.UTF-8` | 0 / 只有 `main` | `警告：忽略损坏的引用 refs/heads/feature/unfinished` | **True，理由「没有未合并的分支」** |
| `fr_FR.UTF-8` | 0 / 只有 `main` | `avertissement : réf cassé refs/heads/feature/unfinished ignoré` | **True，理由「没有未合并的分支」** |

中文环境下 `task_branches()` 的实际结果是 `([], [], [])`，警告完全丢失。新增测试的前提断言本身也固定检查英文，所以它只证明了英文环境中的修复。

**改法：** 若继续匹配英文诊断，给这一条枚举子进程显式固定 `LC_ALL=C`，通过局部 `env` 传递，不修改整个进程的环境；或采用不依赖英文措辞的保守错误处理。继续保留退出码和 stderr。补充调用者处于非英文 locale 时的真实坏 ref 回归，断言仍进入 errors、门 2 为 False 且诊断含坏 ref；不要仅在测试外层统一成英文而掩盖生产缺口。这不涉及分支名 Unicode 空白，也不要求改共享 `git()`。

### 指定三项的其余复核结果

1. **非零退出、异常/超时：通过。** 退出码检查发生在解析 stdout 之前，非零退出保留退出码与 stderr；`OSError` / `SubprocessError` 进入 errors，超时携带的 bytes stderr 会解码保留。异常/超时本身没有正常进程退出码，当前用异常诊断说明原因合理。独立执行新增枚举错误测试块，128、OSError、TimeoutExpired 均阻断。退出 0 的坏 ref 路径仅在英文环境通过，阻塞见上。
2. **`for-each-ref` 的枚举范围：通过。** 独立执行新增 attached / 本仓库 detached / detached worktree 测试块，三种状态清单一致，worktree 占用的分支追加未合入提交后仍阻断。另用合成 refs 核验：嵌套本地分支会纳入，远端跟踪 ref、tag 和相似命名空间 `refs/heads-extra/` 不会混入；旧 `branch.sort` 配置不会再左右枚举。未发现本次切换新增的枚举边界问题。
3. **空候选、只有查询失败分支的回归：通过。** 单独执行新增测试块，原实现退出 0；只在临时副本将 `if errors:` 改成 `if errors and brs:`，同一块退出 1，明确命中 `query error without candidates must block`。fixture 先断言候选/遗留均空且错误恰好一条，再直接断言门 2，因此没有被 main 未前进或其它门顺带挡住。

验证仅运行新增的三个 Python 测试块（全部通过）、上述一个变体（因目标断言失败），以及围绕改动的 locale / ref 范围探针。证据保留在 `/tmp/drover-m9-recheck-u49omg7m/locale-results.json`、`targeted-checks.log`；所有命令均已前台结束。被审 worktree 未修改。

---

## 主控对复核意见的判断

2026-09-21，drover/main。**采纳，交回返工（第 1 轮复核）。**

### 本地化的坏 ref 警告绕过枚举错误检查 —— **必须改，采纳**

主控独立实测，确认 git 会按 locale 翻译这条警告（本机 git 2.51.0）：

```
C              → warning: ignoring broken ref refs/heads/feature/x
zh_CN.UTF-8    → 警告：忽略损坏的引用 refs/heads/feature/x
fr_FR.UTF-8    → avertissement : réf cassé refs/heads/feature/x ignoré
(本机默认)      → warning: ignoring broken ref refs/heads/feature/x
```

**本机 `LANG=en_US.UTF-8`，所以此刻不会触发**——但这不构成不改的理由：

- 换机器、改 locale、或别人用这个仓库就会触发；
- `install.sh` 装出去的 launchd 常驻进程环境和登录 shell 不同，locale 不一定是英文；
- 失败方向落在**危险那侧**（清单不全却判过），正是本次改动一路在堵的那条。

靠「本机恰好是英文」来保证判据正确，本身就是 ROADMAP 里反复记的那种「时机赶巧」，不是设计。

**改法**：给枚举这一条子进程显式固定 `LC_ALL=C`（局部 `env`，不改整个进程的环境），继续保留退出码和 stderr。审查者那句「**不要仅在测试外层统一成英文而掩盖生产缺口**」一并采纳——回归必须在非英文 locale 下真的跑一遍。

### 其余三项复核结果：通过，记录在案

审查者独立验过的，主控不重复：非零退出 / 异常 / 超时三条路径都进 `errors`；`for-each-ref` 的枚举范围正确（嵌套分支纳入，远端跟踪 ref、tag、`refs/heads-extra/` 都不混入，旧 `branch.sort` 不再左右枚举）；「空候选 + 只有查询失败分支」的新回归真的守得住（它把 `if errors:` 改成 `if errors and brs:` 之后确实变红）。


## 复核意见（第 2 轮）

**可以合并。**

2026-09-21，drover/review-glob。仅复核 `ba09ff5..a510f72`，被审 HEAD 为 `a510f726604263c2cbd59801ef9be9a4abfe49a8`。

- **生产修复通过。** `bin/drover-board:391` 只给枚举子进程传入复制后的环境并覆盖 `LC_ALL=C`，未改变父进程环境、其它 Git 调用或既定判据。额外实测调用者 `LANGUAGE=zh_CN` / `fr` 非空时，枚举诊断仍是英文、坏 ref 仍进入 errors、门 2 仍为 False，父进程环境未变。
- **新增回归有效。** 独立抽取并执行本次修改的枚举测试块：真实中文、法文警告的前提断言都成立，原实现退出 0；临时副本仅去掉局部 `env`，退出 1，准确命中 `non-English locale broken ref must block (zh_CN.UTF-8)`，返回值确为 `ok=True / 没有未合并的分支`。没有靠外层英文环境或其它门取得通过/失败。
- **翻译目录依赖：可以不改，本轮不挡合并。** 位置 `tests/criteria.sh:319`。它确实使这条真实翻译回归要求 Git 安装中文、法文翻译目录；没有目录的机器不能宣称跑完了这项验证。当前测试已明确报告前提不满足，且本轮在两种真实翻译都存在的环境完成了验证，足以支撑这次修复。应将这类失败归为测试环境未就绪，不视为生产实现回归；本轮不要求为此增加跳过或模拟逻辑。生产修复本身不依赖这些翻译目录。

`git diff --check ba09ff5..a510f72` 通过；没有重跑全面审查或四套回归。验证记录保留在 `/tmp/drover-m9-recheck2-29sixf9j/verification.log`，命令均已前台结束，被审 worktree 干净。
