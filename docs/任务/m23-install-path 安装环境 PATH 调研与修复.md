# 任务：T14 安装环境 PATH 调研与修复

2026-09-22，drover/main 交给新开的 drover/dev-install-path（Codex，重档 gpt-6-astra / xhigh；实际名字以 corral start 返回为准）。
路由：重 / 交叉审查要（路由：重 0.99、安全隐私 0.84；当前先调研，实施后安排独立审查）
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

1. HANDOFF.md、AGENTS.md、README.md。
2. docs/ROADMAP.md 安装脚本与 launchd 段，docs/QUICKSTART.md、docs/手册.md 的安装/循环说明。
3. install.sh、launchd/dev.drover.loop.plist、tests/install.sh、docs/任务/m5-install 安装脚本和 launchd.md。
4. 本文件。corral 如需参考只读其 docs/CONTRACT.md，不读源码或状态目录。

## 位置与范围

- worktree：/Users/firegnu/Developer/personal_projs/drover-worktrees/m23-install-path，分支 m23-install-path，从 main 建立。
- 只用 Python 标准库，无需安装依赖。主仓库 HANDOFF 由主控维护，不改。
- T14 已正式收到派发，队列末尾“仅加入待办”是之前排期文字，已被本次派发取代。原 T4 的放弃记录保留。
- 本轮只做第一阶段调研，在本文件追加报告并提交；不改生产代码、测试或 ROADMAP。探针与输出放临时目录，给出可复核命令与证据路径。后续实施仍在同一任务、同一 worktree，等主控发送明确范围。

## 第一阶段：先查清再定方案

现状：install.sh 将安装时 PATH（前置 ~/.local/bin、去重）写进 plist。换 PATH 重装会因内容不同拒绝覆盖；激活虚拟环境时可能让后台依赖临时 Python。不要直接把白名单当成既定方案。

1. 列出现有行为矩阵：干净系统/Homebrew 环境、激活 venv、conda/pyenv 等路径或 shim（可用合成目录模拟，不安装它们）、自定义位置的 corral、PATH 顺序/无关目录变化、空/相对 PATH 分量、旧 plist 已存在。明确实际坏在哪里、何时只是安全拒绝，避免“总能找到 corral”这类无依据绝对结论。
2. 至少复现换无关 PATH 后重装拒绝、临时解释器优先级被写进 plist，以及简单白名单漏掉自定义 corral 路径这三类。使用临时 HOME、合成命令，不调用真实 corral/agent、不启动引擎。可以执行沙箱内安装以观察生成物；“只写不跑”禁止真实安装，不禁止隔离验证。
3. 核对实际命令解析链：脚本 shebang、引擎对子命令的启动、corral 的外部运行时依赖。只看本仓库代码；不要读 corral 源码、真实 corral 可执行文件内容或内部状态。外部工具不可知的依赖明确标成边界。
4. 提出最小推荐方案，最多再给一个有意义的备选；说明 Python/git/corral 怎么找、如何避免临时环境、重复安装如何保持幂等、旧配置如何处理、未知目标拒绝覆盖如何保留。不要扩成通用运行时管理器，不新增不必要配置。
5. 对照现有 ROADMAP 与安装契约逐条标注：哪些只是实现修复，哪些改变已定设计、需用户决定。先完成可审阅的具体方案，不提前要求用户泛泛批准。
6. 给出后续 tests/install.sh 的最小用例与有效 RED→GREEN 计划；既有未知目标/预检/隔离/不启动服务断言保留。现有“原样保存 PATH”断言若需变更，精确解释。

## 安全边界

- 临时 HOME 和合成环境沿用 tests/install.sh 的 sandbox-exec 写入隔离，拒绝执行 /bin/launchctl；不得运行真实 install.sh 安装到用户 HOME。沙箱不可用就报告，不换成真实环境验证。
- 不运行任何 launchctl 操作，不修改真实 PATH/shell rc、~/.local/bin、LaunchAgents、~/.drover 或真实队列/tasks.state；不操作真实 done/go/next/loop、不改 TASK_GATE。保留手动 n → g → n。
- 不修改 corral 或 corral-dispatch，不读其源码/状态目录，不访问受保护真实项目与服务（AGENTS.md 表格）。不运行真实 corral 作为探针、不发消息、不新建或关闭 agent。
- 不恢复/删除 T8 stash，不按项目名批量杀进程；只处理自己记录 PID 的临时进程。
- 不安装第三方包、不改其它文件、不合并 main、不推送、不清 worktree/分支、不打收尾记号。

## 记录与回复

报告包含环境/行为矩阵、实际复现命令和结果、最小方案、兼容影响、需裁定点与后续定向测试计划。事实与推断分开；未执行的场景不能写成已验证。不跑全仓库套件；可以跑现有隔离安装套件了解基线。

在本文件末尾追加“## 第一阶段完成记录”，只在自己分支提交这份文档。命令都在前台跑完，回复写主要发现、推荐方案、提交号和待决定事项，最后一行写 DONE。DONE 仅表示调研阶段结束，不表示 T14 已完成。
