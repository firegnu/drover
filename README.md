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

**建设中。** 评审协议已经整个摘掉，配置、完成判据、corral 传输层都接好了（D1 第 0–3 步）。
剩下的是看板改造和安装方式（第 4、5 步）；脚本名字还是 herdsman 时代的（`review-task` / `review-board`），改名排在最后。

- 设计和分步：[docs/ROADMAP.md](docs/ROADMAP.md)
- 在这个仓库里干活的规矩：[AGENTS.md](AGENTS.md)

## 依赖

- [corral](https://github.com/firegnu/corral)
- `python3`（只用标准库）
- `git`
