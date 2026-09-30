# 任务流转接口 v2

2026-09-30。本任务分支实现；等待 Saddle 接入、审查和统一发布，不能单独切换真实 CLI。
本页取代任务详情、人工完成、撤回、指定派发接口中 schema 1 的操作契约。通知偏好接口仍为 schema 1。

## 行为与职责

```
Pending --dispatch-pending--> Running --done--> Awaiting release --go--> Done
   ^                              |                  |
   +-------return-to-pending------+------------------+
```

- 主控明确 `done` 提交已选任务；用户接受交付时调用 `go`。两者均不查询 Git、不执行测试、不派发下一项。
- Running 与 Awaiting 均能退回，须填写原因并明确 `--work-stopped`。恢复派发时的正文到队首，保留工作、交付与退回记录；不隐式暂停。已有 `paused` 原样保持。
- 串行容量不变：有 Running 或 Awaiting 时不能派发另一个任务；Pending 的遗留分支不参与任何转换。
- Git、测试只供主控审查参考，开发交付仍按任务要求验证、审查、合并、清理。Drover 不判断交付质量；worktree 操作完全不变。
- `next`、`loop`（包括 on/off/once）、`hold`、`complete-manually` 退役，退出 2、`command_retired`，不执行旧行为。无参 `go` 或无目标令牌的 `done` 返回用法错误。Running 必须先提交，不能直接接受。
- 不新增并发、类型、分支归属、自动识别、重试或提醒系统。`pause/resume` 仅控制明确派发；resume 不发任务。

## 唯一调用方式

在已有 `.drover.conf` 的目标项目内调用（从当前目录向上定位，遇到另一个 Git 根边界即停止；流转定位不依赖 Git 可执行文件）。始终使用**用户刚确认的那份响应里的令牌**：

```sh
drover list --json
drover show T57 --json
# list.pending[N-1].actions["dispatch-pending"]
drover dispatch-pending --pos N --target-token TOKEN --json
# show.task.actions.done
drover done T57 --target-token TOKEN --json
# 重新读取 Awaiting，用户接受；show.task.actions.go
drover go T57 --target-token TOKEN --json
# Running / Awaiting 的 show.task.actions["return-to-pending"]
drover return-to-pending T57 --target-token TOKEN --reason '需要修改' --work-stopped --json
```

这些 `--json` 与 `--target-token` 是必填项；不另保留绕过目标核对的简写。
令牌格式为不透明的 `v2:<64 hex>`，绑定项目真实路径、动作、目标编号/待办位置、配置、队列、事件文件、暂停状态及文件版本。Git 分支、提交、测试缓存不进入令牌。文件内容恢复原样也不保证旧令牌恢复。

目标过期、重复操作、旧运行请求均拒绝；调用方刷新后让用户重新确认，不自动换令牌重试。状态锁从重新读取目标一直持有至发送/写入完成。普通 queue 编辑与 pause/resume 也使用同一写锁；人工编辑文件不参加锁协议，仍通过文件版本复核拒绝可观察到的变更。

## 读取结果

`list --json`：

```json
{"schema_version":2,"ok":true,"project":"/real/project","paused":false,
 "current":null,"awaiting":null,"pending":[],"history":[]}
```

- `current` 为 Running 或 null；`awaiting` 为 Awaiting 或 null；`history` 包含全部 Done/旧 dropped，倒序，不再重复包含 Awaiting。纯文本 list 仅列最近十项历史。
- 任务至少含 `id/title/body/status/actions`；未编号 Pending 的 `id` 为 null，明确派发时分配编号。
- `status` 为 `pending/running/awaiting_release/done`；保留既有 `dropped` 历史及 Pending 的 drop 操作，不增加主流程状态。Running 的 drop 不再作为绕开验收的出口，先退回 Pending。
- 有运行记录时包含 `run_id`、`start/main/t0`；旧 Git 端点可能为空。`t1` 是提交或旧完成时间；`t2` **只有存在真实接受记录才出现**。旧自动完成不补 t2。
- `submission` 保留本运行提交原事件（新 `submitted` 或旧 `done`）；`completion_record` 保留旧人工覆盖记录。`return_history` 保留本运行退回记录；再次派发后，之前整个运行进入 `previous_runs`，其中交付/退回事实保留。无提交的运行不补 submission。
- `actions` 仅列状态允许的动作，每项为 `{"target_token":"v2:…","unavailable_reason":null}`。Pending 动作还含 `pos`。因 paused/已有 Running/已有 Awaiting/编号标题歧义而不能派发时令牌为 null，原因分别为 `paused/current_exists/awaiting_release/target_ambiguous`。旧运行缺正文时退回目标为 null，原因 `body_unavailable`；提交和接受仍可用。
- 当前/历史任务的 `notification_key` 仅在 Awaiting 非 null，是下述通知身份字符串；其余为 null。Pending 无此字段。
- 删除旧 `mode.loop/gate`、`dispatch_pending`、`manual_completion`、`return_to_pending`、`completion.met` 等 schema 1 操作与门槛字段，不用假值维持旧模式。

`show Tn --json` 返回 `schema_version/ok/project/task/evidence`。`task` 使用上述同一模型，Pending 可按已有编号查看。默认不联系 Corral；可加 `--with-agent-status`，增加 `agent_status`（Corral 公开 status 响应或未配置时 null），不影响动作目标。

`evidence`：

- `scope="repository_reference"`、`controls_transition=false`、`observed_at`：观察时刻的**仓库参考**，不是该任务专属工作或历史验收快照。
- `git.state=available/unavailable/stale`；含 `head_sha/main_sha/tracked_changes/unmerged_local_branches`。所有本地未合入 main 的分支都列作参考，不猜归属；查询失败时不能把空数组解释为已通过。前后 refs 改变为 stale。
- `last_check.state=passed/failed/unknown/stale/unavailable`，含原 `record` 和 `reason`。不运行 CHECK_CMD，也不生成新检查缓存。旧缓存无 run_id 一律仅作 stale 参考，原 `ok=false` 和原因仍保留；不据此宣称当前任务通过。看板中缺少 Git 区间端点/查询失败的提交数显示 unknown，不填 0。带 run_id 的记录也必须匹配任务、运行、main、命令才可显示 passed/failed；损坏、过大或读不了为 unavailable。
- 旧 CHECK_CMD 仅用于解释已有缓存是否陈旧；TASK_GATE、DONE_MARK、hold、loop、.loop-wait、.criteria-checked 不再控制运行。

读取失败返回非成功 JSON，不把损坏事件当作空队列；show 读取期间任务快照改变也拒绝，不混用旧目标和新证据。看板同样显示不可用，不提供写目标。

## 写入结果与退出码

提交、接受、退回成功：

```json
{"schema_version":2,"ok":true,"task_id":"T57","run_id":"…",
 "state":"awaiting_release","record":{"status":"recorded"}}
```

通用失败：`{"schema_version":2,"ok":false,"error":{"code":"target_changed","why":"…"}}`。

| 退出码 | 含义 / error.code |
|---|---|
| 0 | 操作已记录；或明确派发的发送和记账符合成功条件 |
| 2 | invalid_arguments、command_retired、task_not_found、not_configured、repository_unavailable、state_unreadable、state_invalid、body_unavailable、target_ambiguous |
| 3 | target_changed、invalid_state、current_exists、awaiting_release、paused |
| 4 | state_busy |
| 5 | write_failed；不得报告流转成功 |
| 8 | send_rejected、delivery_unconfirmed、delivery_unknown；必须分开检查 delivery 和 record |

旧完成门槛退出码 9 不再出现。队列 add/edit/move/drop 的文本入口仍保留，`--expect` 冲突仍为 10；它们与通知偏好不冒充 schema 2 流转响应。

派发额外包含：

- `delivery={status,attempted,corral_exit_code,confirmed,merged_with_draft}`，status 为 `not_sent/confirmed/unconfirmed/rejected/unknown`。
- `record.status=not_attempted/recorded/unknown`；`run_id` 在记录成功后才返回；`state=pending/running/unknown`。
- 未配 MAIN_AGENT：不联系 Corral，记录 Running，返回 `manual_text` 给人粘贴，delivery=not_sent，退出 0。
- Corral 0 且 ok/confirmed 均 true 才是 confirmed。0 缺确认或 3：记录 Running，退出 8，不重发。拒绝/超时/未知：如实报告，不猜已经开始、不自动重发。
- 发送已经发生后本地写入失败/目标变化：保留真实 delivery，record=unknown、state=unknown、ok=false。必须核对，不能把失败当作安全重发的依据。

状态写入采用临时文件、fsync、替换；退回先恢复队列正文再发布事件。第二步失败可能留下队列排序/正文变化，但原 Running/Awaiting 保留，不伪造退回成功。无跨文件事务、恢复守护进程或自动重试承诺。

## 旧数据与通知

事件仍写入原 `tasks.state`，队列仍是原 `queue.md`。读取时集中解码 `start/done/go/return/drop/hold`；新 start 增加随机 run_id，新增 `submitted/accepted/returned` 明确事件绑定该 run_id。旧运行由 start 事件位置、任务编号、原时间和已存 Git 字段导出稳定 legacy 身份，**只在内存中导出，不补写历史、Git 基线或完成事实**。

已有 Running 可以明确 done→Awaiting，再经用户 go。已有 Awaiting 继续等待接受或退回；已有 Pending 保持 Pending；历史 gate=false 的 done 保持旧完成事实，不改为新待验收、不伪造接受。缺失旧正文只阻止无法可靠恢复正文的退回，不阻止 done/go。

旧版 Running go 可能留下 `done gate=false → go`，解码保留这个真实 go 的时间为 t2；只有 done 而无 go 时仍不补 t2。此兼容仅限旧 go 事件，新 accepted 仍必须从 Awaiting 转移，重复接受仍拒绝。

T57/T55 按用户提供的现场：升级后 T57 可明确提交、再由用户接受，无需删除 T55 分支或補基线；T55 仍 Pending。此任务不执行这些真实操作。

```sh
drover notifications status --json
drover notifications on --json
drover notifications off --json
drover notifications watch [--once] [--projects FILE] [--interval 60]
```

watch 只读任务状态，写通知去重文件，不调用 Git/Corral、不调用流转入口。每次启动、偏好 revision 变化或去重数据失效均先建立基线，不补弹已有 Awaiting；同进程观察到新 Awaiting 才发送。同一身份发送前记去重，失败不重试，不改变任务状态。`--once` 也建立启动基线，适合核对观察边界，不是通知历史回放。

通知身份为 JSON 紧凑字符串 `[project真实路径, task_id, run_id, "awaiting_release"]`（ASCII 转义，无分隔空格）。Saddle 应消费公开 `notification_key`，不重新从 Git 推导；保留其既有启动基线、渠道设置和去重策略。通知偏好字段/版本及已有无补弹规则保持。

## 审查后联合切换顺序

本分支不执行以下部署操作：

1. Saddle 先接入 schema 2，去掉 loop/gate/人工覆盖操作和旧完成文案；以显示目标调用新命令，旧目标拒绝后重新确认。Corral 无需改动。
2. 用隔离临时仓库/状态及假 agent 做 Drover+Saddle 联合验证；保留真实数据备份。
3. 获用户发布授权后，先退出**旧常驻推进引擎及其 launchd KeepAlive**，确认旧进程消失。不能先换 CLI 再仅 kickstart；旧引擎仍可能按旧判据调用旧/new 路径。
4. 协调切换 Drover CLI 与 Saddle。新模板沿用既有 `dev.drover.loop` 标签/日志路径，仅 ProgramArguments 改为 `drover notifications watch`，避免同时留下两份服务。旧 plist 不同，安装脚本会拒绝覆盖，须发布时人工核对更换；不靠加开关维持旧引擎。
5. 启动唯一的新通知观察器；第一轮基线无补弹。只读核对 Running/Pending/Awaiting/历史与暂停状态不变，再恢复明确操作。

新事件写入后，旧二进制不理解它们，不能直接降级后继续操作。若需回退，先停观察/写操作，协调消费方版本并保留整个新事件日志，不能删除新事件、倒填旧完成或静默放行来“兼容”。
