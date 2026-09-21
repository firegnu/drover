# 交接

新开主控先读这份，再读 `AGENTS.md`。**只写「现在在哪、下一步干什么、有什么悬着」**，设计和理由在 `docs/ROADMAP.md`。

---

## 2026-09-21（晚）

**这一节最新，先读它。** 今天最后干的一件事是**拿一件真活去验 corral-dispatch 新改的收尾流程**（用户当天的要求）。活和流程都完成了：`m8-detail-scroll` 已合并进 main（本地，**未推送**），两个 worktree 清掉、两个 agent 关掉、收尾记号已补（现在**五条**）。四个套件全绿，工作区干净，没有 worktree、没有别的分支。

drover 自己**仍旧没有开跑**（`MAIN_AGENT` 空着），配置现值和「换机器要重填」见下面 9-21 那一节，没有变化。

**corral-dispatch 的 SKILL.md 当天又改过一轮**（我报上去的四条它全采纳了），**派活前先重读**，要点见下面那一节。

### 今天做完的活：欠账 4（TUI 详情区滚动）

`detail_viewport(total, room, offset, pages)` 纯函数统一算夹限和翻页；`draw()` 每帧把项目身份 / 行数 / 可视高度 / 归一后的偏移写回进程内 `state`；`key_action()` 读它、保持纯函数。PgUp/PgDn 翻页，切项目归零，缩窗和内容变短都重新夹住。**偏移只活在内存里，刷新照旧等于重跑。**

ROADMAP D1 第 5 步第 3 小节那句「**还欠**：详情区不滚动」可以划掉了。

**这件活真正的教训不在功能上，在测试的有效性上**：三轮返工，**生产代码一个字节没改过**，全部问题都是「断言被别的机制顺带满足，守不住回归」。

- 第一轮（我抓的）：「切项目归零」的断言切到 `queue=None` 的短项目，`limit` 算出来是 0，**任何偏移都会被夹限压成 0**，断言分不出归零逻辑有没有生效。
- 第二轮（交叉审查抓的两条，我判定同类、全部采纳）：「内容缩短」用例同样被归零掩盖；翻页的「输入未变」断言被 PgDn/PgUp 一来一回抵消。

**用的办法是往实现里植入缺陷，看测试红不红**，不看测试数量。五次植入里第一轮就抓出一次假绿。这个办法以后审代码继续用。更干净的跑法是 dev agent 教的：`DROVER_BOARD_BIN=<临时副本> bash tests/drover-board.sh`，被审 worktree 一个字节不动。

### corral-dispatch 新流程实测结果：跑通了，反馈的四条上游已全修

5 处改动全部走到，**一次跑通、零卡壳**。第 7 节那五步按顺序无摩擦：两个 agent 都 `idle`/`attached=0` → 两个 worktree 都干净 → 分支是 main 的祖先 → `worktree remove` 不加 `--force` 两个都删掉、`branch -d` 删掉 → 关掉两个 agent。「第 5 步的扳机是第 4 步成功返回」和「关之前确认记录都落盘」这两条实际都用上了。

跑完把四条使用者视角的事实交给了 `corral/main`（只交事实、不提改法——上游的设计不归 drover 管）。**它四条全采纳改掉了**，还多补了一条。所以**派活前重读一遍 SKILL.md**，下面这些是新的：

- **第 6 节，复核前先把审查者的 worktree 推到新提交**：`git -C <审查 worktree> checkout <新 sha>`（仍 detached）。不推的话它 `git diff` 看得到对象、跑测试却还是旧代码。这是四条里唯一够得上「缺口」的一条，原先要主控自己想到。
- **第 6 节，审查任务文件放主仓库工作区**，派的时候给绝对路径，并写明它不在审查 worktree 里、只写这一个文件。
- **第 6 节，detached 的真正理由补全了**：同一个分支不能在两个 worktree 里同时 checkout，git 会拒绝，所以只能 detached（原先只写了「顺带防手滑提交」）。这条是上游自己补的，不是我报的。
- **第 1 节，残骸判据只看 `cwd` 在不在**，名字后缀不是判据（`--unique` 第一次开就补 `-1`）。原先那句「`-2`、`-3` 多半也是」删掉了。
- **第 7 节第 5 步末尾**：关掉 agent 之后，之前挂在它身上的 `--after` 提醒照样会送来，查到 `not_found` 忽略就行。

> **这些改动此刻还在 corral 工作区里没提交**（`git -C ~/Developer/personal_projs/corral status` 看得到 `M SKILL.md`）。技能是软链过去的，所以**未提交也已经生效**。

### 下一步

还是 D2 第 3 层自举，**和昨天写的一样，只差两步**：填 `MAIN_AGENT=drover/main`、往队列里加第一件活，然后 `drover loop on` + 起引擎进程（记下 PID，别用 `pkill`）。一律放行模式跑够 5 件、没有「没做完却判成做完了」，再上靶场。

欠账清单少了一条（欠账 4 做完了），剩下的见最底下那一节。

---

## 2026-09-21（下半天）

**这一节是给新开的主控看的,先读它。** 今天 drover 这边全部收尾干净:main 已推送、工作区干净、没有 worktree、没有分支、三条收尾记号齐、四个套件全绿。**drover 没有开跑**(`MAIN_AGENT` 空着),不会往任何人的输入框送东西。

### 新主控开场要注意的两件

1. **corral-dispatch 的技能可能已经改了,重新读一遍再派活。** 2026-09-21 下午跟 corral 主控讨论了「委派出去的 agent 堆积」这个问题,它给了一份 5 处文档的改动清单(SKILL.md 第 3、6、7 节和开头,加项目 AGENTS 模板),**还在等人拍板两件事**:
   - 「清完 worktree 顺手关 agent」算对「关 agent 先问用户」开的第二个例外(第一个是清 worktree 本身);
   - 取消跨任务复用 agent(复用收窄到同一个 worktree 内的返工/复核)。

   **这件事不归 drover 管,也不要再插手**——根子在 corral-dispatch(拆掉 drover 照样堆),而 drover 主控参与上游规矩设计会侵蚀「只能往下依赖」那条线。要提供的只有使用者视角的事实,判断由人和 corral 主控做。

   （**2026-09-21 晚已全部落地**：两件都拍板进了 SKILL.md，我又拿一件真活实测了一遍、报了四条事实、上游全采纳。见顶上那节。**这一节以下都是当天早些时候的历史记录。**）

2. **`AGENTS.md` 的派活规矩今天改了两条**(用户定的,提交 `4f587b5`):交叉审查用 detached worktree `../drover-worktrees/review-<分支>`;清掉某个 worktree 时把住在里面的 agent 一并关掉,其余仍旧用户说关才关。

   **两个保护有意先不补,等真实跑出来再说**(用户 2026-09-21 定的):
   - **`worktree remove` 之前没有「确认 agent 是 idle」这一步。** 实测过:起一个进程占着 worktree 的 cwd,`git worktree remove` **不加 `--force` 照样删成功**,进程还活着但 cwd 悬空。**git 在这件事上不兜底**,所以如果 agent 还在跑,这一步会把它的工作目录直接抽掉。
   - `attached` 非 0 时不关(人可能正接在那个窗格里看输出)。

   踩到了再补,别提前加。

### 今天做完的两件活

1. **`m6-branch-filter`** 修废弃分支死锁(欠账 1)。判据第 2 条现在只认包含 `base_sha` 的分支。交叉审查还挖出一条假阳性:`returncode == 0` 把 git 查询失败(128)和「确定不包含」(1)混成一类,查坏的分支被当遗留分支静默排除,同时有个已合入的兄弟分支时第 2 条会**误过**。已修。
2. **`m7-accounting`** 记账 + 路由行(待定 3、4 的落地)。ROADMAP「待定」四条现在全部有结论。

## 2026-09-21

**欠账 1（废弃分支死锁）修完了**，`m6-branch-filter` 已合并进 main（本地，**未推送**），worktree 和分支都清了，收尾记号已补。四个套件全绿。

判据第 2 条现在只认包含 `base_sha` 的分支（`git merge-base --is-ancestor`），和判据第 1 条同一个基准，没加配置项。交叉审查（Codex 重档）还挖出一条一轮时看不出来的**假阳性**：`returncode == 0` 把 git 查询失败（128）和「确定不包含」（1）混成一类，查坏的分支被当「遗留分支」静默排除，同时有个已合入的兄弟分支时第 2 条就误过。已修。设计和理由全在 `docs/ROADMAP.md` 判据第 2 条那一节。

```sh
# 一分钟自检
cd ~/Developer/personal_projs/drover
for t in criteria drover install drover-board; do bash tests/$t.sh >/dev/null 2>&1 && echo "✓ $t" || echo "✗ $t"; done
git log --grep '^收尾:' --oneline      # 现在应该有三条
git worktree list                      # 只有 main，没有残留 worktree
```

### 开跑自举之前必须先定这个（今天实测撞出来的）

**`BRANCH_GLOB` 对 drover 自己必须留空，填了第一件活就卡死。**

两条规矩正面撞车：

- **空真防护**：`BRANCH_GLOB` 非空却匹配到 0 个 → 第 2 条判不过（防的是模式写错、没建分支）。
- **corral-dispatch 收尾纪律**：合并后立刻 `git worktree remove` + `git branch -d`。

守纪律的项目，一件活做完分支就没了 → 匹配 0 个 → 第 2 条永远判不过。今天在本仓库实测就是这个结果（`m[0-9]*` → `ok=False 一个都没匹配到`）。

ROADMAP 里「改成问『活合进去了吗』，删不删分支都成立」那句，是在空真防护加进来**之前**写的，后者推翻了它的一半。**这一条还没改 ROADMAP，也没改代码——要人先拿主意**，三条路：

1. `BRANCH_GLOB` 留空，第 2 条对 drover 自己标「不适用」（最省事，但等于自举全程不验这道门）。
2. 承认「删分支」和「空真防护」不兼容，把空真防护的适用条件写清楚（哪些项目该填 `BRANCH_GLOB`、哪些不该）。
3. 改判据：分支不存在但区间里有合并提交，也算数。**这是设计变更，要问人。**

注意方向：填了 `BRANCH_GLOB` 导致的是**假阴性**（卡住，看得见），不是误推进。所以不紧急，但会让自举第一件活就停在门 2 上。

### `.drover.conf` 已经生成了（2026-09-21）

跑了 `python3 ./bin/drover init drover`：仓库里有了 `.drover.conf`（**已进 `.gitignore`**），`~/.drover/drover` 交接目录和 `~/.drover/projects` 登记都就绪。

**`BRANCH_GLOB` 留空，这是有意的，别去填**——drover 自己守「合并后删分支」的纪律，填了第 2 条必然判不过。理由写进 `docs/ROADMAP.md`「什么项目该填 `BRANCH_GLOB`」了。以后上靶场（分支合了还留着）那边才填。

`MAIN_AGENT` **还空着**，这是故意的：一填上 drover 就会往主控的输入框送任务，那等于自举正式开跑。**要开跑再填，填之前跟人确认。**

### 待定 3、4 定了并且做完了（`m7-accounting`）

**待定 3（记账记什么）**：耗时（`start`→`done`）、提交数、等放行时长（`done`→`go`）。**「返工轮数」放弃了**——drover 看不见主控和 dev agent 的往返（硬规矩第 4 条），按 ROADMAP 自己那句「记不出数就等于没记」。测试里有一条 `lacks '返工'` 守着措辞，不许把提交数说成返工轮数。

**待定 4（读不读「路由：」行）**：读，但降级处理。配套加了 `TASK_FILE_DIR`。找任务文件两条路：队列正文里 `任务文件：<路径>` 优先，否则在 `TASK_FILE_DIR` 里按标题前缀找、**挑含「路由：」行的那份**（自然跳过「交叉审查.md」这类同前缀的附属文件——这是审查时用真数据撞出来的）。

**「绝不参与任何判断」有两条测试守线**：带/不带路由行的 `view_model` 摘掉 `route` 必须完全相等；把 `task_route` 换成一碰就炸再跑 `loop_tick`，照样自己记 done。

已知边界（不是缺陷）：队列条目标题写长了，80 列窄屏下记账会被截掉大半；截断顺序是对的（先掉「等放行时长」），「当前这件活」那里有全的。

### `.drover.conf` 现在的值（本地文件，不进仓库）

```
HANDOFF_DIR=~/.drover/drover
MAIN_AGENT=                    ← 还空着，填上就等于自举开跑
BRANCH_GLOB=                   ← 有意留空，别去填（见 ROADMAP「什么项目该填」）
CHECK_CMD=for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done
DONE_MARK=收尾
TASK_FILE_DIR=docs/任务
```

**换机器或重新 clone 要重跑 `drover init drover`，再把 `CHECK_CMD` 和 `TASK_FILE_DIR` 填回去**（`.drover.conf` 在 `.gitignore` 里，不跟着仓库走）。

门的现状：第 1 条（main 前进了）有效，第 2 条不适用（`BRANCH_GLOB` 空，有意的），第 3 条有效（跑四个套件，实测 20 秒，且套件挂掉时确实判不过）。依据（收尾记号）有效。

### 下一步还是 D2 第 3 层自举

一律放行模式（`TASK_GATE=1`），跑够 5 件、没有「没做完却判成做完了」，再上靶场。**现在只差两步**：填 `MAIN_AGENT=drover/main`，往队列里加第一件活，然后 `drover loop on` + 起引擎进程（记下 PID，别用 `pkill`）。

---

## 2026-09-20

**D1 全部做完了**（第 0–5 步）。四个套件全绿：`tests/criteria.sh`、`tests/drover.sh`、`tests/install.sh`、`tests/drover-board.sh`（10 块）。工作区干净，只有 `main` 分支。**远端 `origin` 2026-09-20 建好了**：`github.com/firegnu/drover`，公开，157 个提交已同步。

```sh
# 一分钟自检
cd ~/Developer/personal_projs/drover
for t in criteria drover install drover-board; do bash tests/$t.sh >/dev/null 2>&1 && echo "✓ $t" || echo "✗ $t"; done
git log --grep '^收尾:' --oneline      # 应该有两条
```

### 今天做完的四件

1. **收尾记号落地**——drover 终于判得出「这件活完了」。约定写在**项目自己的 `AGENTS.md`** 里（corral 侧只改了 `项目AGENTS模板.md`，提交 `649ca22`，**SKILL.md 一个字没动**）。drover 这边四道闸 + `DONE_MARK` 配置 + 检测器。owlet 的 `AGENTS.md` 已加并推送（`3035c55`）。
2. **引擎拆出来**——`drover loop` 独立进程，看板退回纯观察者。拆的时候揪出一个只有常驻进程才会暴露的 bug（`NOW` 不刷新 → 节流永远成立 → 查一次之后再也不查）。
3. **看板改 curses TUI**——`bin/drover-board` 1598 → 927 行，网页那一整层删光。派给 `drover/dev-tui` 做的，审了三轮。
4. **安装脚本 + launchd 模板**——派给 `drover/dev-install` 做的。**只写不跑**：真装、真挂 launchd 要人点头。

两份文档也写了：`docs/QUICKSTART.md`（纯步骤）、`docs/手册.md`（为什么这么设计 + 排查 + 止损）。

### 下一步：D2 第 3 层「自举」

drover 驱动自己的开发。**一律放行模式**（`TASK_GATE=1`，每件做完等人按 `g`），跑够 5 件任务、没有「没做完却判成做完了」，再上靶场 `~/Developer/personal_projs/drover-sandbox`。

**开跑之前先修下面第 1 笔欠账**，否则自举第一件就可能卡在已知 bug 上，污染「5 件零误判」这个验收信号。（**2026-09-21 已修完**，见顶上那节；这一节以下都是当天的历史记录。）

---

## 欠账（按要不要先修排）

1. ~~**废弃分支死锁**~~（**2026-09-21 修完**，`m6-branch-filter`，详见顶上那节）。`BRANCH_GLOB` 撞上一个**被遗弃、永不合并**的分支，门 2 就永远过不了，之后每件活全卡死；靶场上现成两个（`m4/parallel-scalable-generation`、`m4/planning`）。这不是危险方向的误判，是反过来——**做完了永远判不成做完**，而且看起来跟「主控还在干活」一模一样。
2. ~~**「做完的」栏记账整块**~~（**2026-09-21 做完**，`m7-accounting`）。
3. ~~**待定 4：读任务文件开头那行「路由：…」**~~（**2026-09-21 做完**，`m7-accounting`）。
4. ~~**TUI 详情区不滚动**~~（**2026-09-21 晚做完**，`m8-detail-scroll`，详见顶上那节）。
5. **判据第 3 条在看板上只显示命令、不显示结果**。要把核对结果写进交接目录（像 `.loop-wait` 那样归引擎所有、看板只读）才能上屏。`drover done` 里看得到，不急。
6. **`install.sh` 把安装时那条 shell 的整条 PATH 烤进 plist**。好处是常驻引擎一定找得到 `corral` 和 `git`；代价是换条 PATH 再装会拒绝（失败方向安全，有提示），装时若激活着 venv 会一直用那个 venv 的 `python3`。**真装的时候用干净的 shell。** 要改就是收成白名单加 `~/.local/bin`，但那样可能找不到 `corral`。

## 悬着等人定的

- ~~待定 3、待定 4~~：**2026-09-21 都定了并做完了**，见顶上那节。ROADMAP「待定」一节现在四条全部有结论。
- **本地领先 `origin/main` 12 个提交，一直没推**（9-21 那天之后攒下来的：m6、m7、m8 三件活加文档）。推之前要人点头，每次都要（`AGENTS.md`「先问人」）。公开仓库，推之前照例先扫一遍 `gitleaks` / `trufflehog`。
- **`~/.drover/board-notified.json`**：`drover/dev-tui` 测试疏忽漏出来的残渣，内容是合成仓库（`iota/main`）的条目。按「删东西先问人」留着没删。
- ~~两个 dev agent 关不关~~：**已关**（`drover/dev-tui`、`drover/dev-install`，2026-09-20 收工时用户定的）。明天要派活得重新 `corral start`，别忘了带免确认参数（`claude --dangerously-skip-permissions` / `codex --yolo`），见下面「派活的规矩」。

## 派活的规矩（这个仓库已经是 corral-dispatch 项目了）

`AGENTS.md`「开发方式（主控分派）」那节是今天加的：agent 名字 `drover/dev-`、任务文件放 `docs/任务/`、worktree 放 `../drover-worktrees/<分支>`、**本地合并、不自己推送**、收尾记号和 owlet 用同一套措辞。

> **远端有了，但推送规矩没变。** `origin` 指向公开仓库 `github.com/firegnu/drover`，推之前每次都要人点头（`AGENTS.md`「先问人」那一节）。派出去的 agent 一律只在自己分支上提交，不合并也不推。
>
> **公开仓库意味着写进去的东西都会公开。** 当天推之前扫过：`gitleaks` 和 `trufflehog` 全干净，没有绝对路径、没有邮箱。（**`.drover.conf` 当时并不在 `.gitignore` 里**——只是那会儿这个文件还不存在，所以没漏。2026-09-21 跑 `drover init` 时才补上，`drover init` 本来就会加这一行。）但文档里提到的 `owlet` 和 `jb-finetune` 是**私有仓库**——用户判断过：名字和工作流细节公开无妨，私有仓库本身访问不了。**往 `HANDOFF.md` / `ROADMAP.md` 里写那两个项目的细节时，心里有这条。**

今天派活时踩过的两个坑，别再踩：

- **照 SKILL.md 派活要通读整份再动手。** 按需跳读跳过了第 4 节「派出去」，结果漏了「被委派的 agent 一律免确认启动」（`claude --dangerously-skip-permissions` / `codex --yolo`），派出去的 Codex 两分钟就卡在权限框上。
- **别用 `pkill -f drover` 这类按名字批量杀进程**，主控和别的 agent 的命令行里都带着项目名和工作目录。要停就用起的时候记下的 PID。

## 绝对别碰

`AGENTS.md`「绝对不许碰」那张表照旧：真的 jb-finetune、`~/.review/`、`~/wt/`、herdr、`dev.herdsman.*` 的 launchd 任务、`~/.local/bin/` 里那六个老命令、`~/.config/review/`。**老 herdsman 此刻还在推一个真实项目。**

要真跑用靶场 `~/Developer/personal_projs/drover-sandbox`。
