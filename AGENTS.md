# 在 drover 仓库里干活的规矩

## 先读

- `README.md`：drover 是什么，三层怎么分。
- `docs/ROADMAP.md`：设计、分步、验证计划、待定项。所有决定的来源。改设计先改这里。

## 这个仓库现在是半成品

从 herdsman clone 来，第一个提交砍掉了评审协议（`4545f68`）。所以：

- `install.sh`、`tests/` 里还引用着已删除的文件，脚本名字还是 herdsman 时代的（`herdsman-init`、`review-task`、`review-board`、`review-map`）。
- 这是**故意的**，不是坏了。怎么收拾按 ROADMAP 的分步来，不要自己先动手重命名或大扫除。
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

- **只用 Python 标准库**，不装第三方包。不依赖 tmux、herdr 或其他终端工具。
- 留下来的脚本里 `review-task`、`review-board` 是 Python，`review-map` 是 Python。新写的也用 Python。
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

### `install.sh` 已经被锁死，不要绕过

本仓库的 `install.sh` 是从 herdsman 原样继承的。跑一次就会覆盖上面那几个装出去的命令、覆盖 `~/.config/review/`，并 `launchctl bootout` 再 `bootstrap` 掉两个正在运行的 launchd 任务——**一条命令拆掉整套正在用的东西**。

所以脚本开头加了守卫，直接 `exit 2`。**不要设 `DROVER_INSTALL_REWRITTEN=1` 绕过它，也不要手工照着它的步骤装。** drover 装到哪、叫什么、用不用 launchd 是 D1 第 1 步和第 5 步要定的事；重写完那个脚本，再删掉守卫。

同理：不要 `launchctl load / unload / bootstrap / bootout` 任何东西，不要往 `~/.local/bin` 拷任何文件，不要改 PATH。想在开发中跑这些脚本，直接用仓库里的相对路径（`./bin/review-task …`）。
| `~/Developer/personal_projs/owlet`、`corral` | 别人的项目，只读；要改先问 |

### 测试看板的时候尤其小心

`bin/review-board` 是从老 herdsman 原样继承的，**它的默认路径全指向上面那些活的东西**：

- 输出默认写 `~/.review/board.html` —— launchd 定时任务也在写它，人正看着
- 项目清单默认读 `~/.review/projects`
- 项目发现默认扫 `~/Developer/personal_projs/*/.review.conf` —— 会扫到真的 jb-finetune
- **`review-board serve` 会起 `loop_tick`**，读真 jb-finetune 的 `.loop-wait`，然后往 herdr 里真的写手窗格注入文字

所以在默认路径改掉之前：

- 跑看板**一律加 `--out <临时路径> --projects <临时清单>`**，两个都加，不许用默认；
- **不许跑 `review-board serve`**，也不许 `loop_tick` 连到真环境；
- 临时清单里只放靶场和合成仓库，不放任何真项目。

把默认路径改成 drover 自己的（不再是 `~/.review/`）是 D1 第 1 步「配置文件」要解决的事，改完这一节的限制才解除。

## 测试靶场

要真跑的时候用 **`~/Developer/personal_projs/drover-sandbox`**（从 jb-finetune clone 来的副本，远端已全删，随便折腾）。看它顶上的 `DROVER-SANDBOX.md`。**不要用真的 jb-finetune。**

## 回复

中文，简洁，先说结论。
