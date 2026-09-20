# 任务：写安装脚本和 launchd plist（只写不跑）

2026-09-20，drover/main 交给 drover/dev-install（Codex，常规档：`-m gpt-6-astra -c 'model_reasoning_effort="high"'`）。
路由：常规 / 交叉审查不要（路由：档=拿不准（常规 0.85），交叉审查=拿不准；推翻：无。档按「按任务文件写功能」定为常规；交叉审查定为不要——这件活**只写文件不执行**，危险全在内容里，由主控逐行审）。
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

1. `AGENTS.md` —— **必读「绝对不许碰」和「装的路子已经整个删掉了」两节。这件活的全部风险都在那里。**
2. `docs/ROADMAP.md` 的「D1 分步」第 5 步。
3. `bin/drover` 的用法说明（文件开头的 docstring），尤其 `drover loop` 和 `drover board`。
4. `git log --all -- install.sh` —— 老的安装脚本和两个 plist 在历史里，**可以参考写法，但不许照抄 Label 和路径**（照抄就会顶掉正在运行的任务）。
5. 本文件。

## 你在哪里干活

- worktree：`../drover-worktrees/m5-install`，分支 `m5-install`（已从 main 建好）。只在这里改。
- **只新建这几个文件**：`install.sh`、`launchd/dev.drover.loop.plist`（名字可以商量，Label 规则见下）。`README.md` 里补一节安装说明也可以。
- 不用装依赖：只用 Python 标准库和 shell。
- 同时在做的还有 `drover/dev-tui`，在分支 `m5-tui` 上，在大改 `bin/drover-board` 和 `tests/drover-board.sh`。**你一个字都不要碰 `bin/` 和 `tests/`。**

## 要做的

### 1. `install.sh`

把 `bin/drover` 和 `bin/drover-board` 装到 `~/.local/bin`。要求：

- **幂等**：跑第二遍不出错、不重复追加任何东西。
- **软链还是拷贝，你定**（软链的好处是仓库一改就生效，坏处是仓库挪走就断）。把理由写进「实现时的取舍」。
- 装之前**逐个检查目标文件在不在**，在的话要么是自己上次装的、要么就停下来报错，**绝不覆盖不认识的文件**。
- `~/.local/bin` 不在 PATH 时提示人自己加，**不要自己改任何 rc 文件**。
- 结尾打印下一步：`drover init <短名>`、往 `queue.md` 加任务、`drover loop`。

### 2. launchd plist

让**引擎** `drover loop` 被开机拉起、挂掉自动重启。注意是引擎，不是看板——看板是 TUI，人自己开。

- `KeepAlive` 真值，`RunAtLoad` 真值。
- `StandardOutPath` / `StandardErrorPath` 写到 `~/.drover/` 下。
- 程序参数就是 `drover loop`（默认常驻，间隔 5 秒）。

### 3. Label 和路径的硬要求（这件活唯一真正危险的地方）

本机上**正在运行**两个 launchd 任务，Label 是 `dev.herdsman.*`，它们属于另一套还在推真实项目的工具。

- **Label 绝对不能是 `dev.herdsman.*`**，也不能和它们撞。用 `dev.drover.*`。
- **装出去的命令名不能和 `~/.local/bin/{herdsman-init,review-board,review-map,review-task,request-review,review-archive}` 撞**——那几个是那套工具正在用的。
- **不要碰 `~/.config/review/`、`~/.review/`、`~/wt/`。** drover 自己的家是 `~/.drover/`。
- 脚本里**不许出现任何 `launchctl load / unload / bootstrap / bootout / kickstart` 的实际调用**。要装 launchd 任务，就把命令**打印出来让人自己跑**，并在打印前说清楚它会做什么。

### 4. 这件活只写文件，不执行

**写完不要跑 `install.sh`。** 不要往 `~/.local/bin` 拷任何东西，不要动 launchd，不要改 PATH。验收靠下面那套隔离跑法。

## 验收（先写测试，确认因为功能没实现而失败，再实现）

这件活没有现成的测试套件，**新建 `tests/install.sh`**（这是唯一允许你在 `tests/` 下新建的文件，不要改那里已有的任何文件）：

- 把 `HOME` 指到一个临时目录，在里面跑 `install.sh`，断言：两个命令装好了、`~/.drover/` 建出来了、**真实的 `$HOME` 一个字节都没被碰**。
- 再跑一遍，断言幂等：文件没变、没有重复内容。
- 目标位置先放一个内容不认识的同名文件，断言 `install.sh` **拒绝覆盖并以非零退出码停下**。
- plist 用 `plutil -lint`（macOS 自带）断言格式合法；断言它的 Label **不以 `dev.herdsman.` 开头**、且程序参数里有 `loop`。
- 断言 `install.sh` 的正文里**一个 `launchctl` 的实际调用都没有**（出现在 `echo` / 提示文字里可以）。
- 失败必须是因为目标行为还没实现；语法错、测试数据坏了不算。

## 不要做

- 不要碰 `bin/`、`tests/` 下已有的任何文件、`docs/ROADMAP.md`、`AGENTS.md`。
- 不要建 GitHub 远端，不要推送。这个仓库现在**没有远端**，这是故意的。
- 不要按项目名或路径批量杀进程（`pkill -f drover` 这类）：主控和别的 agent 的进程命令行里都带着项目名和工作目录，一条命令能把它们全杀掉。停自己起的服务用起的时候记下的 PID，或者固定端口后 `lsof -ti:<端口>`。
- 拿主意的地方（软链还是拷贝、plist 叫什么、日志放哪）写进本文件末尾的「实现时的取舍」，并在回复里列出。
- **遇到「不实际跑一下 launchctl 就没法验证」，停下来报告，等决定，不要自己跑。**
- 不合并到 main，不推送。只在 `m5-install` 上提交。

## 记录要求

做完在本文件末尾追加「## 完成记录」（在你的分支里提交）：做了什么、测试命令和结果、遇到的问题、没做的事、实现时的取舍。

## 回复

回复里只写：做完了哪些、测试结果、取舍各一句话、有没有要主控决定的事。命令都在前台跑完，全部做完后，回复最后一行写 DONE。
