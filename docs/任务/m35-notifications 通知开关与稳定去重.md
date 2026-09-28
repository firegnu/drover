# 任务：用户级通知开关与稳定去重

2026-09-28，drover/main 交给新开 drover/dev-notifications（名称以 corral --unique 返回为准），Codex 常规档 gpt-6-astra / high。
路由：常规 / 交叉审查不要 / 影响面：改行为（路由：tier、cross_review、impact 均拿不准；按技能回退。任务状态机和判据不改，仅通知行为及偏好持久化）。
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

- AGENTS.md；HANDOFF.md 顶部当前交接。
- docs/ROADMAP.md 的系统通知约定（看板节、系统通知挪进引擎、怎么算成功）。
- /Users/firegnu/Developer/personal_projs/saddle/docs/任务/任务通知-Drover实施委托.md。
- /Users/firegnu/Developer/personal_projs/saddle/docs/任务/任务通知-接口与集成约定.md（共同契约，已核对 saddle 提交 40be7f0；只读，不能改 saddle）。
- docs/任务详情JSON接口.md 的任务字段、attention 及只读边界。

## 在哪里干活

- worktree：/Users/firegnu/Developer/personal_projs/drover-worktrees/m35-notifications
- 分支：m35-notifications；起点 ed8a860b1dceb3def64e225c645887975af6c6e4。
- 只改 bin/drover 的通知相关部分及命令分派/帮助、tests/notifications.py、tests/drover-board.sh 的通知相关断言、docs/通知JSON接口.md、docs/ROADMAP.md 通知相关约定、本任务文件完成记录。
- 不拆 board，不改 bin/drover-board 或共享函数签名。不动主工作区及其未跟踪 T27 文档。

## 用户原话与授权

「对，我的理解就是关键点谈就好了，而且我们已经有了attention入口」
「我个人觉得这个可以放到settings里面，由settings决定是系统弹还是saddle内部弹。」
「对，我有点担心的是drover那块。」
「可以，按照你的计划开干吧」

用户本次要求：「阶段止于审查通过保留待集成，禁止提前合并、推送、发布、启停真实服务或推进真实队列。勿动现有无关 T27 文件。」
共同契约是用户批准分工后整理的实施约定，不伪装成逐字验收原话。

## 要做的

实现共同契约 v1：用户级 notifications status/on/off JSON CLI、通知偏好持久化、仅任务完成且正在等待放行的系统提示、稳定运行身份去重及启动/切换基线。关闭通知或通知异常不阻断任务推进。保持现有同步发送边界，只用标准库；不引入消息服务或投递重试。

公开命令不依赖 cwd 或项目 init：

```text
drover notifications status --json
drover notifications on --json
drover notifications off --json
```

成功退出 0，stdout 单个 JSON 对象，字段固定为：

```json
{"schema_version":1,"ok":true,"scope":"user","system_enabled":false,"revision":3,"application":"next_notification_check"}
```

- system_enabled 为布尔；revision 非负整数，缺失配置为 0，仅实际偏好改变递增，重复 on/off 幂等。
- 缺失配置默认开启；status 只读、不创建文件。损坏、不可读、写失败等非零，stdout 为带 ok:false、error.code、error.message 的 JSON，错误码在公开文档定清。
- 保存成功不表示常驻引擎已应用。后续通知检查读取偏好；约 60 秒不是时限保证，不能撤回在途发送或旧横幅。首次部署须更新旧引擎，留待联合发布，当前不操作。
- 通知偏好唯一事实来源由 Drover 管理；Drover 不读取/调用 saddle。关闭通知不放行、不推进、不清除 Attention。
- 只提示“完成且等待放行”，不提示自动模式完成后直接下一件，不提示 idle 判据未满足；原看板、公开 attention、任务判据保持。
- 首次升级/首次开启/渠道切换/应用启动，首次成功读取的已有 awaiting 集合作为基线、不补弹。读取失败不能当空基线；同渠道正常重启不忘记已处理身份。
- 同一次运行不因刷新、文案变化或短暂观察缺失重弹；去重不能用本轮可见集合覆盖全部已见身份。revision 变化触发新基线，支持轮询间关→开。
- 身份候选为规范化仓库绝对路径、task.id、task.t0、task.start、task.main、事件类型；从现有字段给出精确定义和表示供 saddle 照用，不改任务事件造 UUID。必需字段缺失保留 Attention、跳过自动提示。仓库搬迁/备份恢复/队列重置的身份延续不保证。
- 尽力提示，不承诺系统送达、用户看见或跨渠道精确一次。通知记录不是通知历史；不扩展离线补发、重试、多实例选举。

内部偏好路径和具体错误码由你在共同契约内决定，写成 docs/通知JSON接口.md。ROADMAP 仅更新已授权通知设计：持续状态保留、弹出范围收窄、新偏好/去重规则；不夹带旧文案清理。

## 怎么算做完

完成上述已批准委托和共同契约；交付固定提交 SHA、公开接口文档、可运行命令绝对路径、验证结果及未解决事项，保留分支待 saddle 联调。

验证预算：一条定向入口 `python3 tests/notifications.py`（先建立有效 RED，再实现 GREEN；覆盖本次开关与推进隔离、去重和切换边界）；标准 CLI 回归 `bash tests/drover.sh` 一次；`git diff --check`。均使用临时合成数据和假 corral/假发送器；内部测试可组织必要用例，勿扩成额外套件。认为预算不足请报告，不自行扩大。

## 不要做

- 不改 cmd_next/cmd_done/cmd_go、loop_tick 内部、criteria/find_done_mark、wants_human/show_attention 语义；不修改任务事件格式。
- 不修改 corral、corral-dispatch、saddle、安装脚本或 launchd，不读取 corral 内部状态/源码。
- 不执行真实队列、真实 loop、真实验收正文、真实 OS 通知；不改真实配置、通知渠道或服务，不安装、不启停服务。
- 不跑 PTY 录屏、截图、真实浏览器或完整 tests/drover-board.sh（末尾间接含 PTY）；不跑安装套件或扩大回归预算。
- 不按项目名/路径批量杀进程，不关闭任何其他 agent。
- 不合并、不推送、不发布、不清理 worktree，不打收尾空提交，不更新主分支 HANDOFF；只在本开发分支提交本任务内容。
- 共同契约若不能在通知层成立，报告具体缺口，停止相关实现，不擅自扩大功能、错误语义或权限范围。

## 做完

本文件末尾追加「## 完成记录」并在本分支提交：修改、验证（含真实 RED/GREEN）、取舍、未做事项，各几句话。回复附 SHA、公开契约路径、命令绝对路径和要主控决定的事项。保留 worktree 和 agent。
命令都在前台跑完，全部做完后，回复最后一行写 DONE。
