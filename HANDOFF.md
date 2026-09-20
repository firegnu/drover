# 交接

新开主控先读这份，再读 `AGENTS.md`。**只写「现在在哪、下一步干什么、有什么悬着」**，设计和理由在 `docs/ROADMAP.md`。

---

## 2026-09-20

**D1 全部做完了**（第 0–5 步）。四个套件全绿：`tests/criteria.sh`、`tests/drover.sh`、`tests/install.sh`、`tests/drover-board.sh`（10 块）。工作区干净，只有 `main` 分支，没有远端。

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

**开跑之前先修下面第 1 笔欠账**，否则自举第一件就可能卡在已知 bug 上，污染「5 件零误判」这个验收信号。

---

## 欠账（按要不要先修排）

1. **废弃分支死锁**（必修，明天会踩）。`BRANCH_GLOB` 撞上一个**被遗弃、永不合并**的分支，门 2 就永远过不了，之后每件活全卡死；靶场上现成两个（`m4/parallel-scalable-generation`、`m4/planning`）。这不是危险方向的误判，是反过来——**做完了永远判不成做完**，而且看起来跟「主控还在干活」一模一样。
   修法已经写死在 ROADMAP 里：**只看这次任务开始之后才出现的分支**——分支的第一个提交不在 `base_sha` 的历史里，才算这次的。和门 1 同一个基准，不引入新配置项。第 1 层合成测试测不出来（它造的分支都是这次新建的），所以要先写一条造「历史遗留分支」的测试。
2. **「做完的」栏的「派了几个 agent、返工几轮」+ 记账整块**——卡在待定 3，**要人先拿主意**。
3. **待定 4：要不要读任务文件开头那行「路由：…」**——要人拿主意。倾向「读，但降级处理」。
4. **TUI 详情区不滚动**，超出就截断并提示还有几行。队列长了会不够用。
5. **判据第 3 条在看板上只显示命令、不显示结果**。要把核对结果写进交接目录（像 `.loop-wait` 那样归引擎所有、看板只读）才能上屏。`drover done` 里看得到，不急。

## 悬着等人定的

- **待定 3（记账记什么）、待定 4（路由行）**——见 `docs/ROADMAP.md`「待定」。这两个不定，欠账 2、3 就动不了。
- **`~/.drover/board-notified.json`**：`drover/dev-tui` 测试疏忽漏出来的残渣，内容是合成仓库（`iota/main`）的条目。按「删东西先问人」留着没删。
- **两个 dev agent 关不关**：`drover/dev-tui`、`drover/dev-install`，活都干完合并了，worktree 已删（`git worktree list` 只剩 main）。留着的话下一件活可以直接给它们，省一次开机。

## 派活的规矩（这个仓库已经是 corral-dispatch 项目了）

`AGENTS.md`「开发方式（主控分派）」那节是今天加的：agent 名字 `drover/dev-`、任务文件放 `docs/任务/`、worktree 放 `../drover-worktrees/<分支>`、**本地合并不推送**（没有远端）、收尾记号和 owlet 用同一套措辞。

今天派活时踩过的两个坑，别再踩：

- **照 SKILL.md 派活要通读整份再动手。** 按需跳读跳过了第 4 节「派出去」，结果漏了「被委派的 agent 一律免确认启动」（`claude --dangerously-skip-permissions` / `codex --yolo`），派出去的 Codex 两分钟就卡在权限框上。
- **别用 `pkill -f drover` 这类按名字批量杀进程**，主控和别的 agent 的命令行里都带着项目名和工作目录。要停就用起的时候记下的 PID。

## 绝对别碰

`AGENTS.md`「绝对不许碰」那张表照旧：真的 jb-finetune、`~/.review/`、`~/wt/`、herdr、`dev.herdsman.*` 的 launchd 任务、`~/.local/bin/` 里那六个老命令、`~/.config/review/`。**老 herdsman 此刻还在推一个真实项目。**

要真跑用靶场 `~/Developer/personal_projs/drover-sandbox`。
