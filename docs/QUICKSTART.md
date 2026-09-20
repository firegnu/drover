# QUICKSTART

从零到「队列自己往前走」。**纯步骤**，为什么这么做看 [手册](手册.md)。

每条命令的参数和退出码看 `drover --help` / `drover board --help`，这里不重复。

---

## 0. 前提

- `python3`、`git`（只用标准库，不装任何第三方包）
- [corral](https://github.com/firegnu/corral) 装好了，`corral ls` 能跑
- 目标项目的主控**已经由你开着**（`corral start <项目>/main --cwd <仓库> -- claude`）。drover 不开、不关、不接入任何 agent

## 1. 装

```sh
cd <drover 仓库>
sh install.sh
```

它做的：把 `bin/drover` 和 `bin/drover-board` **软链**到 `~/.local/bin`，把 launchd 模板生成到 `~/.drover/dev.drover.loop.plist`。

它**不**做的：不动 `launchctl`，不改任何 shell 配置，不覆盖任何它不认识的文件（撞上就非零退出、一个字节都不写）。

> **用干净的 shell 跑。** 它会把当前 PATH 烤进 plist，装的时候若激活着某个 venv，常驻引擎会一直用那个 venv 的 `python3`。

`~/.local/bin` 不在 PATH 就自己加。后面所有命令都假设 `drover` 能直接敲。

## 2. 接一个项目

```sh
cd <目标项目>
drover init <短名>          # 短名只能是小写字母、数字、连字符
```

写出 `<项目>/.drover.conf`（已自动加进 `.gitignore`）、建交接目录 `~/.drover/<短名>/`、把仓库登记进 `~/.drover/projects`。

编辑 `.drover.conf`，**至少填 `MAIN_AGENT`**：

```sh
MAIN_AGENT=<项目>/main      # 主控在 corral ls 里的名字。留空 = 不自动送，只把任务正文打出来让你自己粘
BRANCH_GLOB=m[0-9]*         # 里程碑分支的匹配模式，直接交给 git branch --list。留空 = 这个项目不用里程碑分支
CHECK_CMD=uv run pytest -q  # 默认验收命令，退出码 0 才算过。留空 = 没有验收命令
DONE_MARK=收尾              # 收尾记号的前缀，见下一步
TASK_GATE=1                 # 1（默认）每件做完等人放行；0 做完直接发下一件
```

> `BRANCH_GLOB` 别写 `m*`，它会把 `main` 自己匹配进来。两个真实项目都能用 `m[0-9]*`。

## 3. 往项目的 AGENTS.md 加一行

`drover init` 会把这一行打印出来。贴进目标项目 `AGENTS.md` 的「开发方式（主控分派）」那一节，挨着「合并：」那行：

```markdown
- 收尾记号：一件活合并完、worktree 和分支清干净之后，在 main 上补一条空提交（`git commit --allow-empty`），首行写「收尾: 」加一句话说明这件活是什么。只记真正落地的活；说好不合并、停在审查的不记。
```

**这一行是 drover 判断「这件活完了」的唯一依据。** 不加的话 drover 判不出完成，循环开着也不会自动记 done，只会停下等你按一下。前缀要和 `.drover.conf` 里的 `DONE_MARK` 一致。

（新项目按 corral 的 `项目AGENTS模板.md` 建的话本来就有这条，核对一下前缀就行。）

## 4. 加任务

```sh
drover add "重构导出模块" "接口保持不变" "验收：uv run pytest -q tests/export"
```

或者直接编 `~/.drover/<短名>/queue.md`——它只归你，drover 不写它：

```markdown
## 重构导出模块

接口保持不变。
验收：uv run pytest -q tests/export

## 补上导出的集成测试
```

`## 标题` 开一块，编号可省（发出时自动补 `T1`、`T2`…），文件里的先后就是执行顺序。正文里写一行 `验收：<命令>` 可以按任务覆盖 `CHECK_CMD`。

## 5. 手动走一遍（先别开循环）

```sh
drover next        # 把队首那件送进主控
drover list        # 看现在什么状态
```

送出去的就是任务正文本身，和你手动粘一段进去一模一样。主控开始干活。

等它干完、合并、清 worktree、打上收尾记号之后：

```sh
drover done T1     # 只读核对判据；过了就记完成
drover go          # 放行，允许发下一件
drover next
```

**整个过程 drover 对目标仓库只读，一个字节都不写。**

## 6. 打开看板

```sh
drover board
```

一个 curses TUI，建议**单开一个终端标签**常驻。按键：

```
↑↓ / j k  选项目      g  放行        n  发下一件
p  暂停 / 恢复         a  加任务（开 $EDITOR 编 queue.md）
l  循环开 / 关         r  刷新        q  退出
```

日常推进按键就行，不用敲命令。

## 7. 让它自己走

两个开关叠起来是三档，**默认全关**：

| loop | `TASK_GATE` | 行为 |
|---|---|---|
| off | — | 什么都不自动（默认） |
| on | 1 | 自动核对判据、自动记 done，**下一件等你按 `g`** |
| on | 0 | 全自动，无人值守 |

```sh
drover loop on     # 告诉引擎「这个项目要转」（在项目目录里跑，或看板里按 l）
drover loop        # 引擎本身：常驻，默认每 5 秒一跳
```

> **开关不是引擎。** `drover loop on` 只是标记这个项目要转；**真正推动它的是常驻的 `drover loop` 进程**。引擎没跑，开关开着也不会动。

第一次用**先走中间档**（`TASK_GATE=1`）：让 drover 只证明它认得出完成，别让它自己往下发。

## 8. 让引擎开机自启（可选，要你自己跑）

`install.sh` 只生成 plist，**不动 launchd**。真要挂上去，自己跑它打印出来的那三条：

```sh
mkdir -p ~/Library/LaunchAgents
ln -s ~/.drover/dev.drover.loop.plist ~/Library/LaunchAgents/dev.drover.loop.plist
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/dev.drover.loop.plist
```

挂上之后**别再手动跑 `drover loop`**，两个引擎会互相打架。

---

## 拆掉

```sh
drover loop off                      # 每个项目一次
launchctl bootout gui/$UID/dev.drover.loop   # 挂过才需要
rm ~/.local/bin/drover ~/.local/bin/drover-board
```

`.drover.conf` 和 `~/.drover/` 删不删随你。**拆掉之后目标项目照常工作**——你手动往主控喂任务，一切如常。那行收尾记号留着也没坏处，`git log --grep '^收尾:'` 一敲就是做完了哪些活。
