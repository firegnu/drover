# 在 drover 仓库里干活的规矩

## 先读

- **`HANDOFF.md`：现在在哪、下一步干什么、有什么悬着。每次开工先读它。**
- `README.md`：drover 是什么，三层怎么分。
- `docs/ROADMAP.md`：设计、分步、验证计划、待定项。所有决定的来源。改设计先改这里。
- `docs/QUICKSTART.md` / `docs/手册.md`：怎么装、怎么跑、出事了怎么查。

## 这个仓库现在到哪了

从 herdsman clone 来，第一个提交砍掉了评审协议（`4545f68`）。**2026-09-20：D1 全部做完（第 0–5 步）**，下一步是 D2 第 3 层自举。当天的细节和欠账清单在 `HANDOFF.md`，这里只记不会天天变的：

- 两个可执行文件：`bin/drover`（队列 + 推进 + 判据 + `init` + 引擎 `loop`）和 `bin/drover-board`（TUI + 数据模块）。`drover board …` 转给后者。
- **外层循环的引擎是 `drover loop`，独立进程。** 看板是纯观察者，开不开都不影响循环转不转——从 `board serve` 的线程里拆出来的，**别再往回塞**。
- **看板是 curses TUI**，网页那一整层（CSS / JS / HTTP 服务 / 令牌）已经整个删掉，别再加回来。推进靠按键，写操作一律转给 `bin/drover`——判据和队列解析只能有一份实现。
- **`bin/drover-board` 同时是数据模块**：`bin/drover` 和几个测试都 import 它。交接文件的解析、完成判据、`loop_tick` 都在里面，改那些函数的签名会把另外三个套件一起带塌。
- **有安装路径了**：`sh install.sh` 软链到 `~/.local/bin` + 生成 launchd 模板。**写好了不等于能跑**——真装、真挂 launchd 在「先问人」那一节里。开发时照旧用相对路径：`python3 ./bin/drover …`。
- 要查被删掉的东西当初为什么那么设计，`git log` 全在，别凭空猜。

## 开发方式（主控分派）

- 这个项目的开发任务由主控拆开，派给别的 agent 做。主控负责拆任务、写任务文件、审查、合并，不自己写功能代码。分派时按 corral-dispatch 技能做。
- 被委派的 agent（任务文件里写明了身份）照任务文件做，不再往下派。
- agent 名字以 `drover/dev-` 开头；任务文件放 `docs/任务/`；每个任务一个分支，worktree 放 `../drover-worktrees/<分支>`，交叉审查用 detached worktree `../drover-worktrees/review-<分支>`。
- 审查：主控审查每个任务。
- 合并：审查通过后本地合并进 main。**不推送**——远端 `origin`（`github.com/firegnu/drover`，公开）2026-09-20 建好了，但推送仍旧在「先问人」那一节里，每次都要人点头。
- 收尾记号：一件活合并完、worktree 和分支清干净之后，在 main 上补一条空提交（`git commit --allow-empty`），首行写「收尾: 」加一句话说明这件活是什么。只记真正落地的活；说好不合并、停在审查的不记。
- 收尾之后更新 `HANDOFF.md`：现在在哪、下一步干什么、有什么悬着。设计和理由进 `docs/ROADMAP.md`，别写进交接文件。
- 开出来的 agent：清掉某个 worktree 时，把住在里面的那个一并关掉（它的工作目录没了，接不了新活）；其余的用户说关才关。
- 不要按项目名或路径批量杀进程（`pkill -f drover` 这类）：主控和别的 agent 的进程命令行里都带着项目名和工作目录，一条命令能把它们全杀掉。停自己起的服务用起的时候记下的 PID（`cmd & echo $!`），或者固定端口后 `lsof -ti:<端口> | xargs kill`。

## 硬规矩

这几条是 drover 成立的前提，破一条整套定位就垮了。

### 只能往下依赖

```
drover ──只依赖──> corral-dispatch（很薄：活干完会以合进 main 的分支落地；项目填了收尾记号的，还多一条空提交）
   └──只依赖──> corral（send / status / ls）
```

1. **不许改 corral，也不许改 corral-dispatch。** 两个都在 `~/Developer/personal_projs/corral`，`cd` 过去就能改——这是最容易破的一条。drover 缺什么信息，先看能不能用现有命令组合出来；真觉得要给 corral 加东西，**停下来问人**，不要自己动手。
2. **只认 corral 的契约，不读它的源码。** 要知道某个命令怎么用、输出有哪些字段，读 `~/Developer/personal_projs/corral/docs/CONTRACT.md`。不读 `src/`，不读 corral 的状态目录，不依赖任何没写进契约的行为。
3. **不要求主控为 drover 多做任何事。** 完成判据只能从 git 和主控本来就会写的任务文件里读。**绝不解析自然语言结论**（比如任务文件里「## 主控审查」那一节的「结论：通过」）——主控换个措辞就崩。

   **唯一的例外是「收尾记号」**（2026-09-20 定，全过程和理由见 ROADMAP 完成判据那一节）：主控一件活收尾时，在 `main` 上补一条空提交，首行是固定前缀加一句话。破例是有意的——没有它判不出「这件活完了」，外层循环整个不成立。它不算反依赖，靠三条撑着，**少一条就得重新评估**：

   - 约定住在**项目自己的 `AGENTS.md`** 里（来源是 corral 的 `corral-dispatch-skill/项目AGENTS模板.md`，提交 `649ca22`），和「本地合并还是开 PR」同级。**corral-dispatch 的 SKILL.md 一个字没动**，主控不知道 drover 存在。
   - 模板里明写着**「不写照样能跑」**。不填这条的项目，内循环照常工作。
   - **漏打只会让 drover 卡住，不会让它误进。** 失败方向是安全的：假阴性你一眼看得出，假阳性不可能发生。

   这条线原本是写死不许碰的——herdsman 的 ROADMAP 里「三个会破坏它的诱惑」第 2 条就是「让主控写个 done 标记文件」（`bc9fda3` 写下，`f3036aa` 建 drover 时随 ROADMAP 精简掉了）。**现在是明知故犯，不是不知道。**
4. **drover 不开、不关、不接入任何 agent。** 只用 `send`、`status`、`ls`。主控由人开、由人关。

### 反依赖的四个探针

上面那条例外是贴着线走的，所以留四个信号。**符合任何一条，就是反依赖正在发生，停下来问人**（corral 主控 2026-09-20 给的）：

1. corral 的 `SKILL.md` 里出现「为了让外面能认出来」这类理由。
2. 有人提议给 corral 加字段或命令，理由是「drover 需要」。
3. 项目模板里那条从「项目可以删」变成「必须有」，或者「不写照样能跑」那句被删掉。
4. **corral 的测试里出现依赖这个约定的断言。** 最隐蔽的一条：一旦 corral 断言了它，删掉那行会让 corral 的测试挂掉，那就真反依赖了。所以**这条约定不进 corral 的任何测试**。drover 自己的测试当然要断言检测器好用（合成仓库里造标记），那是 drover 依赖 drover，不算。

### 随时要能通过的验证

拆掉 drover，目标项目照常工作——人手动往主控喂任务，一切如常。这条可以真跑，不是口号。

## 技术约束

- **只用 Python 标准库**，不装第三方包。不依赖 tmux、herdr 或其他终端工具——herdr 的依赖在第 3 步全换成 corral 了。
- 两个脚本 `drover`、`drover-board` 都是 Python，新写的也用 Python。
- 看板不存自己的状态，**刷新等于重跑**。这条是它一直好用的原因，不要为了性能破例。
- 看板是深色（`color-scheme:dark` 那套 CSS 变量），不为浅色折中。

## 测试

- 测试不依赖真的 corral、不依赖真的 agent、不花钱：用**假的 `corral` 命令**模拟（沿用老仓库模拟 herdr 的做法），用**合成 git 仓库**验完成判据。
- 行为改动和修 bug 先写测试，确认它因为目标缺陷而失败，再实现。

## 先问人，不要自己定

- 改 ROADMAP 里已经定下的设计；动 ROADMAP 的待定项。
- 给 corral 加任何东西。
- 推送、建 GitHub 远端、安装到 `~/.local/bin`。
- 删除东西；关掉不是自己开的 agent。

## 绝对不许碰（会弄坏正在用的东西）

本机上还跑着**老的 herdsman**，它在推进一个真实项目。下面这些是它的，动了就坏：

| 不许碰 | 是什么 |
|---|---|
| `~/Developer/personal_projs/jb-finetune` | **真的**那个项目，还跑在老 herdsman / herdr 上。一个字节都不要改 |
| `~/Developer/personal_projs/herdsman` | drover 的前身，已冻结 |
| `~/.review/` | 老 herdsman 的交接目录，**看板的默认输出和项目清单都在这里** |
| `~/wt/` | 老 herdsman 的评审 worktree |
| herdr | 不要关窗格、不要 `herdr server stop`、不要往里面的 agent 送任何话 |
| launchd 任务 `dev.herdsman.*` | 看板的定时生成和常驻服务，此刻正在运行 |
| `~/.local/bin/{herdsman-init,review-board,review-map,review-task,request-review,review-archive}` | 老 herdsman **装出去的副本**，真实项目正在用的就是这几个 |
| `~/.config/review/` | 老 herdsman 的全局配置 |

### 装的路子已经整个删掉了

本仓库原来从 herdsman 继承了 `install.sh` 和两个 launchd plist。**它们已经删除**，因为跑一次就会覆盖上面那几个装出去的命令、覆盖 `~/.config/review/`，并顶掉两个正在运行的 `dev.herdsman.*` 任务（那两个 plist 的 Label 就是它们的名字）——一条命令拆掉整套。

所以现在**没有任何安装路径**，这是故意的：

- **写**新的安装脚本是 D1 第 5 步的活（装到哪、叫什么、用不用 launchd，连同脚本改名一起定）。但**跑**它是另一回事：往 `~/.local/bin` 拷东西、动 launchd，在「先问人」那一节里，写完也要人点头才能执行。
- 不要 `launchctl load / unload / bootstrap / bootout` 任何东西。
- 不要往 `~/.local/bin` 拷任何文件，不要改 PATH。
- 开发中要跑这些脚本，用仓库里的相对路径：`python3 ./bin/drover …`。

老的那三个文件在 git 历史里（`git log --all -- install.sh`），要参考 launchd 怎么写可以去看，但不要照抄 Label 和路径。

## 测试靶场

要真跑的时候用 **`~/Developer/personal_projs/drover-sandbox`**（从 jb-finetune clone 来的副本，远端已全删，随便折腾）。看它顶上的 `DROVER-SANDBOX.md`。**不要用真的 jb-finetune。**

## 回复

中文，简洁，先说结论。
