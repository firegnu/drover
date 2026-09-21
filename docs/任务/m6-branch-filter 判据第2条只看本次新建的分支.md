# 任务：判据第 2 条只看本次任务新建的分支（修废弃分支死锁）

2026-09-21，drover/main 交给 drover/dev-branch-filter（Codex，常规档：`-m gpt-6-astra -c 'model_reasoning_effort="high"'`）。
路由：常规 / 交叉审查要（路由：档=拿不准（倾向重 0.76），交叉审查=要（核心规则 0.91）；推翻：档位路由拿不准，主控定为常规——修法 ROADMAP 已写死、bug 已定位、改动只有一个函数加一个参数，难点不在设计而在别碰坏共享函数，那一层由重档交叉审查兜）。
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

1. `AGENTS.md`（特别是「硬规矩」和「测试」两节）
2. `docs/ROADMAP.md`「判据第 2 条（里程碑分支）的历史」整节——这件活修的就是那一节最后一段
3. `bin/drover-board` 的 `milestone_branches`（309 行）和 `criteria`（328 行）
4. `tests/criteria.sh` 全文，尤其是第 2 条相关的用例
5. 本文件

## 你在哪里干活

- worktree：`../drover-worktrees/m6-branch-filter`，分支 `m6-branch-filter`（已从 main 建好）。只在这里改。
- 只动 `bin/drover-board`、`tests/criteria.sh`、`docs/ROADMAP.md` 三个文件。
- 纯 Python 标准库 + bash，没有依赖要装。
- 没有别的 agent 同时在这个仓库干活。

## 背景：这个 bug 长什么样

判据第 2 条是「`BRANCH_GLOB` 匹配到的里程碑分支都已经是 `main` 的祖先」。它拿 `git branch --list <glob>` 取分支，**不区分这些分支是哪一次任务留下的**。

于是：仓库里只要有一个**被遗弃、永远不会合并**的分支撞上 glob，第 2 条就永远过不了，**之后每一件活全部卡死**。靶场 `~/Developer/personal_projs/drover-sandbox` 上现成两个：`m4/parallel-scalable-generation`（末次提交 2026-09-14）、`m4/planning`（2026-09-02），配上 `m[0-9]*` 就会踩。

方向要看清楚：这**不是**「没做完却判成做完了」，是反过来——**做完了永远判不成做完**，而且在看板上跟「主控还在干活」长得一模一样，分不出来。

第 1 层的合成测试现在测不出来，因为它造的分支都是这次任务新建的。

## 要做的

### 1. 先写测试，确认它因为这个缺陷而失败

在 `tests/criteria.sh` 里加用例，造一个带**历史遗留分支**的合成仓库：

- 在 main 上先提交若干次；
- 从一个**较早**的 main 提交上分叉出一个分支（例如 `m4/planning`），在它上面提交，**永不合并回 main**；
- main 继续前进，取此刻的 sha 作为 `base_sha`（模拟「送任务」那一刻）；
- 再从 `base_sha` 建**这次任务的**分支（例如 `m6/impl`），提交，然后合进 main。

期望：第 2 条**过**（这次任务的分支已合入，历史遗留的那个不算数）。
改之前跑，它必须失败，而且失败原因是「`m4/planning` 还没合进 main」——**不是**语法错、不是仓库造坏了。把改之前的失败输出贴进完成记录。

再加一条相反方向的用例守住安全方向：同样的历史遗留分支还在，但**这次任务的分支没合进 main** → 第 2 条必须**不过**。这条是防止过滤写过头，把该挡的也放过去。

### 2. 改实现

`milestone_branches(repo, glob_pat)` 加一个 `base_sha` 参数，只留**这次任务开始之后才出现**的分支。

**判别式：`git merge-base --is-ancestor <base_sha> <branch>` 成功，才算这次的。**

理由：这次任务的分支是从 `base_sha`（送任务那一刻的 main）建出来的，必然包含 `base_sha`；历史遗留分支在 `base_sha` 之前就分叉了，不包含它。和判据第 1 条同一个基准，不引入新配置项。主控已在靶场上实测过这条判别式：`m3/implementation`、`m4/parallel-scalable-generation`、`m4/planning` 三个全部排除，正是要的结果。

> **注意 `docs/ROADMAP.md` 那一句写岔了。** 该节最后写的是「分支的第一个提交不在 `base_sha` 的历史里，才算这次的」——照字面读，遗留分支和新分支的首个提交**都**不在 `base_sha` 的历史里，这条判别式区分不开两者。**设计意图没变**（「只看这次任务开始之后才出现的分支」），岔的只是这一句的算法措辞。请把这一句改成上面那个判别式，改动限于这一句，**不要动该节其它任何内容**。

`base_sha` 为空时（没记下送任务前的 sha）不要瞎猜：这时无从判断哪些分支是这次的，**整条标「不适用」（`ok: None`）**，`why` 说明是因为没有 `base_sha`。不要退回旧行为（那等于留着死锁），也不要判成不过（那会在正常配置下凭空卡住）。

### 3. `why` 文案要分得出两种「0 个」

过滤之后可能一个都不剩，这时**仍然判不过**（和现状一致，防的是「空真」，见 ROADMAP 该节），但理由必须说得出是哪一种，否则排查时看不出来：

- glob 压根没匹配到任何分支 → 沿用现在的说法（写错了？还是这件活没建分支？）
- glob 匹配到了 N 个，但全是 `base_sha` 之前就有的 → 新说法，要把被过滤掉的分支名报出来，让人一眼看出是遗留分支在干扰，而不是模式写错了。

第 2 条**过**的时候，`why` 也要让人看得出哪些分支被排除了（如果有），否则「全都合进去了」会让人以为遗留分支也合了。

### 4. 别把共享的东西碰坏

`bin/drover-board` 同时是数据模块，`bin/drover` 和三个测试套件都 import 它。

- `criteria(repo, base_sha, glob_pat, check_cmd, do_check=True)` **签名不要动**——它本来就收 `base_sha`，往下传就行。
- `milestone_branches` 只有两个调用点：`criteria` 内部，和 `tests/criteria.sh:85` 那条断言。加参数时把那条断言一并改对。
- 四个套件全部要跑过：`tests/criteria.sh`、`tests/drover.sh`、`tests/install.sh`、`tests/drover-board.sh`。

## 验收（先写测试，确认它因为功能没实现而失败，再实现）

- 新增用例：历史遗留分支在、这次任务的分支已合入 → 第 2 条过。
- 新增用例：历史遗留分支在、这次任务的分支没合入 → 第 2 条不过。
- 新增用例：`base_sha` 为空 → 第 2 条标「不适用」。
- 新增用例：glob 匹配到的全被过滤掉 → 第 2 条不过，且 `why` 与「glob 没匹配到」的说法能区分开。
- 原有用例全部照旧通过，一条都不许删或改弱。
- 四个套件全绿：`for t in criteria drover install drover-board; do bash tests/$t.sh; done`
- 失败必须是因为目标行为还没实现；导入报错、合成仓库造坏了不算。
- 全部用合成 git 仓库，不碰真实仓库、不碰靶场、不花钱。

## 不要做

- 不要动 `criteria` 的签名，不要动 `bin/drover`。
- 不要加新的配置项（不要引入 `IGNORE_BRANCHES` 这类清单）。
- 不要改判据第 1 条、第 3 条，不要改收尾记号检测器 `find_done_mark`。
- 不要改 `docs/ROADMAP.md` 里除那一句算法措辞之外的任何内容；不要改 `HANDOFF.md`（主控收尾时自己写）。
- 不要碰 `AGENTS.md`「绝对不许碰」那张表里的任何东西：真的 jb-finetune、`~/.review/`、`~/wt/`、herdr、`dev.herdsman.*`、`~/.local/bin/` 里那六个老命令、`~/.config/review/`。
- 不要往 `~/.local/bin` 拷东西，不要 `launchctl` 任何东西。
- 不要按项目名或路径批量杀进程（`pkill -f drover` 这类）：主控和别的 agent 的进程命令行里都带着项目名和工作目录，一条命令能把它们全杀掉。停自己起的服务用起的时候记下的 PID，或者固定端口后 `lsof -ti:<端口>`。
- 不合并到 main，不推送。只在 `m6-branch-filter` 上提交。
- 拿主意的地方写进完成记录「实现时的取舍」，并在回复里列出。
- 判别式换成别的写法（比如按提交日期、按 reflog、按 `--contains`）之前停下来报告，等决定，不要自己换。

## 记录要求

做完在本文件末尾追加「## 完成记录」（在你的分支里提交）：做了什么、测试命令和结果、**改之前那条测试的失败输出**、遇到的问题、没做的事、实现时的取舍。

## 回复

回复里只写：做完了哪些、测试结果、取舍各一句话、有没有要主控决定的事。命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 完成记录

2026-09-21，drover/dev-branch-filter，在 `m6-branch-filter` 分支完成。

### 做了什么

- `milestone_branches` 增加 `base_sha`，严格以 `git merge-base --is-ancestor <base_sha> <branch>` 的成功结果保留本次分支，继续排除 `main`。
- 第 2 条缺少 `base_sha` 时返回 `ok: None`；过滤后为空仍不过，分别说明 glob 无匹配或全部被过滤，后者列出数量和全部分支名；有本次分支时也在理由中列出被排除的分支。
- 合成仓库覆盖遗留分支与本次未合入／已合入分支并存、缺少基准、全部被过滤和完全无匹配；原有断言保留，仅适配直接调用的参数和返回值。
- ROADMAP 只修正指定算法句；按本任务的记录要求追加本节。

### 测试命令和结果

1. RED：先新增合成仓库用例，未改实现时运行 `bash tests/criteria.sh`，退出码 1。本次分支已合入，失败原因确为历史遗留分支仍被计入，输出如下：

   ```text
   FAIL: merged current branch must pass despite legacy branch: 1:ok 2:no 3:skip
     1 main 前进了: 2c2e1e9 → 4e79d1f
     2 里程碑分支都合进去了: 还没合进 main：m4/planning
     3 验收命令过了: 没有验收命令：CHECK_CMD 空着，队列条目也没写
   ```

2. GREEN：实现后运行 `bash tests/criteria.sh`，退出码 0，原有及新增断言全部通过。
3. 回归：前台顺序运行 `for t in criteria drover install drover-board; do bash tests/$t.sh || exit; done`，退出码 0；四个套件全部通过，其中安装套件 9 项、看板套件 10 块全部通过。
4. `git diff --check` 通过。所有测试只使用临时合成仓库和假 corral；安装测试在临时 HOME 和 macOS 写入沙箱中运行，未执行真实 launchctl。

### 遇到的问题

初写未合入分支的文案断言时，误要求旧实现把本次分支列在首位，导致先停在文案断言；调整为检查分支名后，得到上面明确由 `m4/planning` 阻塞已合入任务的 RED。没有阻塞问题或待定设计。

### 没做的事

未改 `criteria` 签名、判据第 1／3 条、`find_done_mark`、`bin/drover`、`HANDOFF.md` 或任何配置项；未访问真实项目或靶场，未修改 corral，未安装到真实 HOME，未操作 launchd、agent；未合并到 main、未推送。交叉审查和主控审查留给主控安排。

### 实现时的取舍

- `milestone_branches` 返回 `(本次分支, 被排除分支)` 两份名单，两个调用点一起适配，避免为诊断文案重复查询 git；共享入口 `criteria` 的签名和返回结构不变。
- 文案以“不包含 base_sha，按遗留分支处理”说明判别依据，不引入日期或 reflog 推断；通过和未通过时均附排除名单。
- ROADMAP 保留原句开头的“修法（还没做）”，严格遵守仅改算法措辞的范围；落地状态记在本完成记录，HANDOFF 由主控收尾时更新。

没有需要主控决定的新事项。

### 交叉审查修订（2026-09-21）

按主控本轮裁定，只处理意见 2、3、4；意见 1 的判别式设计边界仍待主控向人确认，本轮没有改判别式、ROADMAP 或引入任何新状态。

- **意见 2**：祖先查询退出码 0 保留、1 排除，其它退出码归入独立的错误列表；`criteria` 只要收到错误就令第 2 条 `ok=False`，`why` 包含故障分支名、退出码与 Git stderr。错误分支不再冒充遗留分支。正常排除名单在查询失败时仍可显示。
- **意见 3**：新增两个包含 `base_sha` 的本次分支混合状态场景：`m6/impl` 已合入、`m6/second` 未合入时必须不过且点名后者，两者都合入后必须过；单个及混合本次分支的阻塞状态均断言显示 `m4/planning` 的排除信息。
- **意见 4**：整个历史场景放进子 shell，`R` 和场景变量不再污染外层；退出后用原 `R`、`BASE` 再核对一次判据，验证恢复后的配对可用。

**新增回归的 RED：** 未改实现时前台运行 `bash tests/criteria.sh`，退出码 1。合成仓库中已合入分支仍正常，另一个有未合入提交的 `m6/z-broken` 被暂时移走中间提交对象；测试先确认分支列表查询成功、正常分支祖先查询为 0、故障分支查询为 128 且 stderr 非空，再检查公开的 `criteria` 结果。失败输出：

```text
Traceback (most recent call last):
  File "<stdin>", line 20, in <module>
AssertionError: branch query error must block despite merged siblings: {'n': 2, 'name': '里程碑分支都合进去了', 'ok': True, 'why': '2 个都已经是 main 的祖先：m6/impl、m6/second；已排除不包含 base_sha 的遗留分支：m6/z-broken'}
```

这不是整个 `base_sha` 无效的全失败场景，也不是测试前提构造错误；失败正是第 2 条将单分支查询故障排除后误过。对象在 `finally` 中恢复，所有操作仅发生在测试的临时合成仓库。

**意见 3 的变异验证：** 修复后在临时目录复制 `bin/drover-board`，分别将返回值改成 `return current[:1], excluded, errors`，以及将显示排除名单的条件改成 `if excluded and rows[-1]["ok"]:`；逐一通过 `DROVER_BOARD_BIN=<临时副本> bash tests/criteria.sh` 前台运行，两个变异均退出 1，输出如下（工作区实现未变异）：

```text
first-branch-only: exit=1
FAIL: second current branch must still block: 1:ok 2:ok 3:skip
  1 main 前进了: ebc6b89 → 1496b2c
  2 里程碑分支都合进去了: 1 个都已经是 main 的祖先：m6/impl；已排除不包含 base_sha 的遗留分支：m4/planning
  3 验收命令过了: 没有验收命令：CHECK_CMD 空着，队列条目也没写
hide-excluded-when-blocked: exit=1
FAIL: a blocking criterion must name the excluded legacy branch
```

**GREEN 和回归：** 实现后 `bash tests/criteria.sh` 退出 0；补完子 shell 退出后的核对及变异验证，再前台顺序执行 `for t in criteria drover install drover-board; do bash tests/$t.sh || exit; done`，退出 0，四个套件全绿（安装 9 项、看板 10 块通过）。`git diff --check` 通过；本轮 `docs/ROADMAP.md` 无差异。

**实现时的取舍：** 将已有两份名单扩为 `(本次分支, 被排除分支, 查询错误)`，两个调用点同步适配，避免异常控制流或重复 Git 查询；`criteria` 签名及返回结构不变。保留完整 stderr（仅去掉首尾空白）便于排查，不把异常退出码解释为否定结果。

**遇到的问题／没做的事：** 没有新增阻塞问题；意见 1 按主控裁定暂不处理，不能把本轮修复当作该设计边界已解决。未改其它判据、收尾记号、配置、HANDOFF、真实项目或靶场，未合并、未推送。
