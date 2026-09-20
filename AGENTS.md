# 在 drover 仓库里干活的规矩

## 先读

- `README.md`：drover 是什么，三层怎么分。
- `docs/ROADMAP.md`：设计、分步、验证计划、待定项。所有决定的来源。改设计先改这里。

## 这个仓库现在到哪了

从 herdsman clone 来，第一个提交砍掉了评审协议（`4545f68`），之后 D1 第 0–4 步都做完了：评审协议整个摘干净，配置、完成判据、corral 传输层、看板「当前这件活」块、外层循环闭合，都在了。

**只剩 D1 第 5 步**：装出去、脚本改名、写文档。所以现在：

- 脚本已经改名（第 5 步）：只剩两个可执行文件，`bin/drover`（队列 + 推进 + 判据 + `init`）和 `bin/drover-board`（面板）。`drover board …` 转给后者。
- **还没有安装路径**，只能用仓库里的相对路径跑：`python3 ./bin/drover add "标题"`。装到哪、用不用 launchd 是第 5 步剩下的事。
- 要查被删掉的东西当初为什么那么设计，`git log` 全在，别凭空猜。

## 硬规矩

这几条是 drover 成立的前提，破一条整套定位就垮了。

### 只能往下依赖

```
drover ──只依赖──> corral-dispatch（很薄：只依赖「活干完会以合进 main 的分支落地」这一条约定）
   └──只依赖──> corral（send / status / ls）
```

1. **不许改 corral，也不许改 corral-dispatch。** 两个都在 `~/Developer/personal_projs/corral`，`cd` 过去就能改——这是最容易破的一条。drover 缺什么信息，先看能不能用现有命令组合出来；真觉得要给 corral 加东西，**停下来问人**，不要自己动手。
2. **只认 corral 的契约，不读它的源码。** 要知道某个命令怎么用、输出有哪些字段，读 `~/Developer/personal_projs/corral/docs/CONTRACT.md`。不读 `src/`，不读 corral 的状态目录，不依赖任何没写进契约的行为。
3. **不要求主控为 drover 多做任何事。** 完成判据只能从 git 和主控本来就会写的任务文件里读。**绝不解析自然语言结论**（比如任务文件里「## 主控审查」那一节的「结论：通过」）——主控换个措辞就崩。
4. **drover 不开、不关、不接入任何 agent。** 只用 `send`、`status`、`ls`。主控由人开、由人关。

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
