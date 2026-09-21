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
