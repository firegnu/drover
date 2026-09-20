# drover

把一条任务队列，一件接一件地送进一个正在工作的 agent 主控，人不在场时也继续往前走。

drover 是赶牲口走长途的人：它不决定去哪，只负责队伍一直在走。

## 三层

| 层 | 是什么 | 认识什么 | 时间尺度 |
|---|---|---|---|
| [corral](https://github.com/firegnu/corral) | 基础设施 | 只认识「开 agent、送话、看状态」。不认识任何流程 | 进程级 |
| corral-dispatch（corral 仓库里的技能） | **内循环** | corral 的命令；一件活怎么拆、交给谁、审不审 | 分钟到小时，主控在场 |
| **drover** | **外循环** | corral 的命令；队列、闸门、什么时候叫醒、怎么记账 | 天级，无人值守 |

**只能往下依赖。** drover 对内循环的依赖薄到：内循环全靠人手工做的项目，drover 照样能跑。

## 它做什么

1. 往主控送一句话（任务正文）
2. 只读核对 git，判断这件活做完没有

就这两个动作。**它一个 agent 都不开、不关、不接入**——那些是人的事。用到的 corral 命令只有三个：`send`、`status`、`ls`。

配套的是一个只读看板（HTML，深色），显示队列、主控在干什么、分支进展、什么时候需要你。

## 它不做什么

- 不做评审协议、不做 findings、不做轮次、不做证据门槛（那些是它的前身做的，见下）
- 不开、不关、不接入任何 agent；不自动重开主控
- 不解析主控写的自然语言结论
- 不读 corral 的内部文件，不安装、不升级、不管理 corral
- 不为自己的需求去改 corral 或 corral-dispatch

## 出身

drover 从 [herdsman / bounded-adversarial-review](https://github.com/firegnu/herdsman) clone 而来，历史全留。那个项目是「一个写手 agent 实现，一个评审 agent 挑错」，跑在 herdr 上。

分家的原因：corral 和 corral-dispatch 出现之后，评审这件事由内循环用更轻的方式承担了；herdsman 剩下的、也是它真正独一份的价值，是队列、看板和记账——那是外循环。所以这个仓库的第一个提交就是砍掉评审协议（`4545f68`），留下外循环。

老仓库冻结，不再维护。要查被删掉的东西当初为什么那么设计，`git log` 全在。

## 状态

**建设中。** 评审协议整个摘掉了；配置、完成判据、corral 传输层、看板改造、外层循环闭合都做完了（D1 第 0–4 步），脚本改名成单命令 `drover`，完成判据有了依据（收尾记号），外层循环的引擎也从看板里拆成了独立的 `drover loop`。

剩下第 5 步：删看板的 agent 块、看板改 TUI、QUICKSTART 和手册。安装脚本与 launchd 模板已提供；实际安装、启用要人点头。开发时仍用仓库里的相对路径跑：`python3 ./bin/drover …`。

- 设计和分步：[docs/ROADMAP.md](docs/ROADMAP.md)
- 在这个仓库里干活的规矩：[AGENTS.md](AGENTS.md)

## 依赖

- [corral](https://github.com/firegnu/corral)
- `python3`（只用标准库）
- `git`

## 安装（人工确认后执行）

在准备长期保留的仓库目录运行 `sh ./install.sh`。脚本把 `drover`、`drover-board` 以绝对软链装到 `~/.local/bin/`，建立 `~/.drover/`，并生成 `~/.drover/dev.drover.loop.plist`。仓库更新会直接生效；不要安装到随后会删除的临时 worktree，仓库挪走也会让软链失效。

安装前会一次检查所有目标：命令只接受指向当前仓库的原有软链，生成的 plist 只接受内容完全一致的普通文件，其他情况非零退出、拒绝覆盖。相同配置重复安装不会改写文件。`~/.local/bin` 不在 PATH 时只提示自行添加，不修改 shell 配置。

launchd 模板中的 `__HOME__` / `__PATH__` 由安装脚本展开并作 XML 转义；不要直接加载仓库里的模板。生成文件记录安装时的 HOME 和 PATH（优先加入 `~/.local/bin` 并去重），供引擎找到 `python3`、`git`、`corral`。其他 PATH 配置变化或 plist 已被手改时，重装会拒绝覆盖，请先人工核对旧文件。

**脚本不运行 launchctl，也不写 `~/Library/LaunchAgents/`。** 它只打印人工启用命令：把生成文件链接到该目录，再以 `dev.drover.loop` 加载引擎。启用后立即启动 `drover loop`，以后用户登录时启动，退出后自动重启；用户 LaunchAgent 不会在尚未登录时启动。标准输出和错误分别写入 `~/.drover/loop.stdout.log`、`~/.drover/loop.stderr.log`。目标已存在或服务已加载时先核对，不要覆盖或重复加载。

在目标项目里执行 `drover init <短名>`，配置 `.drover.conf` 的主控，把任务写到交接目录的 `queue.md`，再执行 `drover loop on` 开启该项目。未启用 launchd 时，另一个终端运行 `drover loop`（默认每 5 秒检查一次）；启用后不要重复手动启动引擎。看板仍由人单独打开。

隔离验收：`sh tests/install.sh`（macOS，临时 HOME + 写入沙箱，不执行真实 launchctl）。
