# 任务：删掉 BRANCH_GLOB，完成判据第 2 条改成只认 base_sha

2026-09-21，drover/main 交给 drover/dev-glob（Codex，常规档：gpt-6-astra / high）。
路由：常规 / 交叉审查要（路由：档位拿不准——常规 0.65、重 0.35、置信度 0.47，按技能「拿不准用常规」定；交叉审查「要」，core_rules 0.9）。
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

1. `AGENTS.md`（尤其「硬规矩」「技术约束」「测试」三节）
2. `docs/ROADMAP.md` 的「完成判据：纯 git，零解析」整节，**重点是「判据第 2 条（本次任务建的分支）」和紧跟其后的「这条判据的已知限制」**。设计已经定死在那里，本任务是把它落到代码上，**不要重新设计**。
3. `bin/drover-board` 的 `milestone_branches()` 和 `criteria()`；`bin/drover` 里所有 `BRANCH_GLOB` 的引用
4. `tests/criteria.sh`、`tests/drover.sh`、`tests/drover-board.sh` 里和判据第 2 条相关的用例
5. 本文件

## 背景：为什么删

「里程碑」不是这个项目里的实体，只是用户对「某次功能完成」的叫法（他可能自己打个 tag，drover 不读 tag）。所以「里程碑分支」这类东西不存在，判据第 2 条要认的是**这次任务建的分支**，而认它的正确依据是 `base_sha`——`m6-branch-filter` 已经在这么做了，分支名 glob 只是套在外面的一层壳。这次把壳去掉。

## 你在哪里干活

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/m9-drop-branch-glob`，分支 `m9-drop-branch-glob`（已从 main 建好）。只在这里改。
- 不用装依赖（只用 Python 标准库）。
- 现在没有别的 agent 在这个仓库里干活。

## 要做的

### 1. `bin/drover-board`：取分支的方式和判定

- `milestone_branches(repo, glob_pat, base_sha)` → **改名 `task_branches(repo, base_sha)`**，去掉 `glob_pat` 形参。
  取分支从 `git branch --list --format=%(refname:short) <glob>` 改成**不带 glob**（枚举所有本地分支）。`MAIN_BRANCH` 自己照旧永远排除。
  返回值结构不变：`(本次分支, 排除的遗留分支, 查询错误)`。
  **退出码的三分照原样保留**：0 = 包含 base_sha（本次的）、1 = 确定不包含（遗留）、其它 = 查询失败进 errors。这是 `m6` 交叉审查挖出来的假阳性修复，不许退回 `returncode == 0` 两分。
- `criteria(repo, base_sha, glob_pat, check_cmd, do_check=True)` → **去掉 `glob_pat` 形参**，变成 `criteria(repo, base_sha, check_cmd, do_check=True)`。
  这是签名变更，`bin/drover` 和三个测试套件都在调它，一并改（见下）。
- 第 2 条的显示名：`"里程碑分支都合进去了"` → **`"这次建的分支都合进去了"`**。
- **删掉 `if not glob_pat:` 那条「不适用」分支**（没有配置项了，这种情况不存在）。`not base_sha` 那条「不适用」**保留不动**。
- **行为翻转（本任务的要害，只此一处）**：过滤后 `brs` 为空时，结论从 `ok=False` 改成 **`ok=True`**。
  守纪律的项目一件活干完分支就删了，「一个不剩」是正常收尾，该过。
  但 `why` 必须让人看得见发生了什么，**两种「一个不剩」要分别说**：
  - 有 `excluded`（有分支，但都不含 `base_sha`、按遗留分支排除）→ 理由里**逐个报出被排除的分支名**。ROADMAP「已知限制」那条说的就是这种情况会落在危险那侧，人必须看得见。
  - 没有 `excluded`（压根没有别的分支）→ 说清楚是「没有未合并的分支」。
- `p["branch_glob"]` 那行（约 588）删掉；186 和 686 两处 `criteria(...)` 调用跟着改。

### 2. `bin/drover`

- 读配置的 `BRANCH_GLOB`（约 91）删掉，`global` 声明里（约 79）一并去掉。
- 两处 `B.criteria(...)` 调用（约 216、234）按新签名改。
- 注释里提到 `BRANCH_GLOB` 的（约 39、206）改掉。
- **`init` 生成的 `.drover.conf` 模板里 `BRANCH_GLOB=` 连同它上面那段注释整个删掉**（约 658-665）。

> 配置解析器是正则收所有 `KEY=VALUE`，没人读的键就是没人读。所以**老的 `.drover.conf` 里残留 `BRANCH_GLOB=` 一行不会报错，不需要写迁移代码**。

### 3. 三个测试套件

先看清楚每条用例原本在守什么，再决定它是「改措辞」还是「换语义」：

- `tests/criteria.sh`：`crit()` / `why()` 两个辅助函数的参数要去掉 branch_glob；第 54-60 行两个用例（「空 glob → 不适用」「glob 匹配 0 个 → 不过」）**按新语义重写**；第 77-85 行 `milestone_branches` 直调改成 `task_branches`；第 171-185 行「全是遗留分支」那组用例保留并按新结论改（现在判**过**，但理由里要有被排除的分支名）。
- `tests/drover.sh` 第 90 行断言了显示名措辞，跟着改。
- `tests/drover-board.sh`：第 69 行往合成仓库 `.drover.conf` 写的 `BRANCH_GLOB=m[0-9]*` 去掉；867 / 870 两处 `p["branch_glob"]`；相关注释。

### 4. 文档措辞

`docs/手册.md`（3 处）、`docs/QUICKSTART.md`（1 处）里提到 `BRANCH_GLOB` / 里程碑分支的地方，按新设计改。**`docs/ROADMAP.md` 已经改完了，不要再动它。** `docs/任务/m6-*.md` 两份是历史记录，**不要动**。

## 验收（先写测试，确认因为目标行为没实现而失败，再实现）

新增/改写的测试至少要守住这几条，每条都要能单独挂掉：

1. **一个分支都没有** → 第 2 条 `ok=True`，理由说「没有未合并的分支」这个意思。
2. **有分支、都含 `base_sha`、都已合入 main** → `ok=True`，理由里列出分支名。
3. **有分支、含 `base_sha`、没合入 main** → `ok=False`，理由里列出没合入的那些。
4. **只有遗留分支**（都不含 `base_sha`）→ `ok=True`，**理由里必须出现被排除的分支名**。这条守的是 ROADMAP「已知限制」那个危险方向：结论虽然放过，但人看得见。
5. **第 1、4 两种「一个不剩」的理由文字不一样**（断言要能区分，不要两条都只 grep 一个宽泛的词）。
6. **`main` 自己永远不算**（现在没有 glob 了，枚举全部分支时 `main` 必然在列，这条比以前更要紧）。
7. **`merge-base` 查询失败（退出码非 0 非 1）→ 第 2 条不过**，且报出分支名和 git 的 stderr。这条现成的，确认改完还在。
8. `base_sha` 为空 → 第 2 条仍旧「不适用」（`ok=None`）。

**断言有效性自检（这个项目上一件活三轮返工全栽在这里，务必做）**：写完测试后，往实现里**逐条植入缺陷**，确认对应的断言真的变红——比如把空集合结论改回 `False`、把排除分支名从理由里拿掉、把 `main` 的排除去掉、把退出码三分改回两分。**有任何一条植入之后测试仍然全绿，说明那条断言守不住，重写它**。在完成记录里列出你植入了哪几条、各自红了没有。

**四个套件全绿**（这是本仓库的默认验收命令）：

```sh
for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done
```

失败必须是因为目标行为还没实现；语法错、fixture 坏了不算 RED。

## 不要做

- **不要改 `docs/ROADMAP.md`**（设计已经定死，那是主控的文件）。不要动 `docs/任务/m6-*.md`。
- **不要重新设计判据**。觉得 ROADMAP 里的设计有问题，写进「实现时的取舍」并在回复里说，**不要自己改成别的方案**。
- 不要引入任何第三方包、不要引入新的配置项。
- 不要碰 `~/.drover/` 下的真实交接目录，不要碰 `~/.review/`、`~/wt/`、`~/.local/bin/`、launchd。测试一律用合成仓库和假 corral。
- 不要合并到 main，不要推送。只在 `m9-drop-branch-glob` 上提交。
- 不要按项目名或路径批量杀进程（`pkill -f drover` 这类）：主控和别的 agent 的命令行里都带着项目名和工作目录，一条命令能把它们全杀掉。要停自己起的进程，用起的时候记下的 PID。
- 拿主意的地方写进本文件「实现时的取舍」，并在回复里列出。
- 遇到「按 ROADMAP 做不下去」的情况，停下来报告，等决定，不要自己换别的办法。

## 记录要求

做完在本文件末尾追加「## 完成记录」（在你的分支里提交）：做了什么、测试命令和结果、**植入缺陷自检的逐条结果**、遇到的问题、没做的事。

## 回复

回复里只写：做完了哪些、测试结果、取舍各一句话、有没有要主控决定的事。命令都在前台跑完，全部做完后，回复最后一行写 DONE。


## 实现时的取舍

- 完全沿用 ROADMAP 已定的 `base_sha` 判别式和已接受的边界，不加分支快照、迁移逻辑或配置项；两种空集合都通过，但分别说明「没有未合并的分支」和逐个列名的「全部被排除」。
- 测试用 `feature/implementation` 守住不再依赖命名模式；只剩遗留分支的场景通过删除合成仓库中的本次分支构造，不再靠 glob 隐藏它们。`main` 排除仍直接断言分支清单，避免被最终布尔值掩盖。
- 缺陷只植入临时实现副本，用现有 `DROVER_BOARD_BIN` 入口执行原测试；每次从正确实现重新生成副本，互不叠加，工作区实现不被修改。

## 完成记录

2026-09-21，drover/dev-glob。

### 做了什么

- `milestone_branches` 改为 `task_branches(repo, base_sha)`，枚举所有本地分支并排除 `main`；保留祖先查询退出码 0 / 1 / 其它的三分处理。
- `criteria` 去掉 glob 参数，更新 CLI、看板和三个测试套件的调用；空集合通过、遗留分支逐个列名，缺少 `base_sha` 仍不适用，查询失败仍阻断并报告分支名与 stderr。
- 删除配置读取、项目状态字段和 init 模板中的 `BRANCH_GLOB`；CLI 测试确认老配置残留无影响、新配置不再生成该键。
- 更新 QUICKSTART 和手册中全部相关现行说明；看板的空分支场景计数由 0/2 改为 1/3，验收命令未配置时仍显示不适用。

### 测试命令和结果

1. RED：先只改空分支用例、仍调用旧签名，运行 `bash tests/criteria.sh`，退出码 1：`FAIL: no other branches must pass: 1:ok 2:no 3:skip`。失败来自旧空真防护，不是签名、语法或 fixture 错误。
2. GREEN：实现和调用迁移后 `bash tests/criteria.sh` 退出码 0。
3. 最终回归：`for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done`，四套全绿、退出码 0（安装套件 9 项通过，使用临时 HOME 和写入沙箱）。所有命令均在前台等到结束。
4. 静态检查：`bash -n tests/criteria.sh tests/drover.sh tests/drover-board.sh`、Python `compile()` 检查两个脚本、`git diff --check` 均通过。生产代码中无旧函数名、glob 参数或配置键残留。

### 植入缺陷自检（逐次独立执行）

每次编译临时副本后运行 `DROVER_BOARD_BIN=<临时副本> bash tests/criteria.sh`；17/17 均退出 1，且核对了命中指定断言，无语法/签名错误，无假绿。临时副本随测试清理，当前实现保持不变。

| 植入缺陷 | 对应断言结果 |
|---|---|
| 没有其它分支时改判 False | 红：`no other branches must pass` |
| 只有遗留分支时改判 False | 红：`all legacy branches must pass` |
| 去掉「没有未合并的分支」说明 | 红：`criterion 2 explains the empty branch set` |
| 已合入的本次分支改判 False | 红：`merged branch passes even though it was not deleted` |
| 已合入分支理由只列第一个名字 | 红：`criterion 2 must name every merged current branch` |
| 未合入分支改判 True | 红：`unmerged branch must not pass` |
| 去掉未合入分支名字 | 红：`criterion 2 names the unmerged branch` |
| 只检查第一个本次分支是否合入 | 红：`second current branch must still block` |
| 全是遗留分支时只列第一个排除名字 | 红：`excluded branch missing: m4/planning` |
| 全排除的理由混入「没有未合并的分支」，保留原数量和名字 | 红：`all-filtered branches must not use the no-other-branches explanation` |
| 完全去掉 main 排除 | 红：空分支理由断言 |
| 仅有兄弟分支时漏排除 main，避免先被空集合断言挡住 | 红：分支清单出现 `main`，`main itself must never be counted as a task branch` |
| 退出码三分改成两分，把查询失败当遗留分支 | 红：`branch query error must block despite merged siblings` |
| 查询失败理由漏掉分支名 | 红：查询错误分支名断言 |
| 查询失败理由漏掉 git stderr | 红：stderr 原文断言 |
| base_sha 为空时改判 False | 红：`missing base_sha makes criterion 2 inapplicable` |
| 枚举分支重新加上 m[0-9]* 过滤 | 红：非 m 命名的未合入分支未能阻断 |

### 遇到的问题、没做的事

- 无设计阻塞，无需主控另作决定。手册实际残留的相关旧说明多于任务概述中的处数，均按既定设计同步。
- 未改 ROADMAP、m6 历史任务、HANDOFF；未安装、启用 launchd、使用真实交接目录或真实 agent；未合并 main、未推送。仅在本任务分支提交，审查和合并留给主控。

## 主控审查

2026-09-21，drover/main。**结论：通过，可以进交叉审查。**

- **自己重跑四个套件全绿**，和回复一致。断言数 `tests/criteria.sh` 51 → 49：删的 5 条全是 glob 专有的（空 glob 不适用、匹配 0 个、`m*` 匹配到 main、未匹配理由），新增 3 条（空集合过 + 理由、每个已合入分支都要列名），净 −2 对得上，不是削弱。
- **自己另做了 4 次缺陷植入**（不看它的表格，独立挑的要害），全部变红：空集合结论翻回 `False` → `no other branches must pass`；全排除时理由里拿掉分支名 → `excluded branch missing: m4/planning`；两种「一个不剩」混成同一句 → `all-filtered branches need a distinct explanation`；去掉 `main` 排除 → `criterion 2 explains the empty branch set`。**没有假绿。**
- **抽看代码**：`task_branches` 枚举全部分支并排除 `MAIN_BRANCH`，`merge-base` 退出码 0/1/其它的三分处理原样保留（`m6` 那条假阳性修复没被退回）；`not base_sha` 的「不适用」保留；行为翻转只此一处。
- **实测真实场景**：老 `.drover.conf`（残留 `BRANCH_GLOB=`）配新代码，`drover list` 正常，第 2 条正确认出未合并的 `m9-drop-branch-glob`。确认无需迁移代码。
- **范围核对**：只动了 `bin/drover`、`bin/drover-board`、三个测试套件、`QUICKSTART`、`手册` 和本文件。ROADMAP 没碰、`m6` 历史任务文件没碰、没加第三方包、没加配置项、没合并没推送。「不要做」一条没犯。

### 取舍逐条表态

1. **沿用既定 `base_sha` 判别式、不加分支快照** —— 同意。那是 ROADMAP 里标着「动之前先问人」的设计变更，本任务范围外。
2. **测试改用 `feature/implementation` 而非 `m1/implementation`** —— 同意，**比我要求的更好**：它证明判据不再依赖 `m` 开头的命名，正是这次改动的要点。
3. **只剩遗留分支的场景改用「删掉本次分支」构造，不再靠 glob 隐藏** —— 同意，构造方式和新语义一致。
4. **缺陷只植入临时副本、每次从正确实现重新生成** —— 同意，这是上一件活教出来的干净跑法。
5. **手册改动多于任务概述列的处数** —— 同意。核过 diff，多出来的是「已知限制」一段（主动补的，指向 ROADMAP）和「门 2 永远过不了」那节里「更好的修法还没实现」一句的删除（现在实现了）。都该改。

### 顺带记一条（既有问题，不属本任务）

`.gitignore` 没有盖住 `__pycache__` / `*.pyc`。跑 python 导入 `bin/drover-board` 就会留下 `bin/__pycache__/`。这次是我审查时产生的，已手动清掉。要不要补进 `.gitignore` 另说。
