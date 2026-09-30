# Running 撤回 Pending 公开接口（schema_version 1）

> 2026-09-30：以下是旧版记录。任务流转与观察器当前契约以[任务流转接口 v2](任务流转JSON接口.md)为准；旧 gate/loop/人工覆盖行为已退役。通知偏好 schema 1 保留，通知身份改用公开 notification_key。操作步骤见 [QUICKSTART](QUICKSTART.md)。


2026-09-29，用户授权 drover 与 saddle 主控直接实施。只结束这次运行，不记 Done/Dropped，不停止或注入 agent，不更改 dispatch-log。用户必须确认实际工作已经停止；agent 的 idle 不能替代此确认。

## 查询与确认

在目标项目 Git 工作目录运行 `drover show Tn --json`。顶层增加：

```json
{"return_to_pending":{"target_token":"不透明字符串","unavailable_reason":null}}
```

只有可靠的 current 且非 awaiting 提供目标令牌。不可用时 token 为 null，原因是 `target_changed`、`state_invalid` 或 `snapshot_unavailable`。旧派发缺少标题或正文时为 state_invalid，拒绝猜测恢复内容。Git 判据或验收缓存不参与撤回目标的可用性判断。令牌为独立的 `r1:` 格式，消费者不可自行构造或解析；它绑定真实项目路径、具体 start 所在状态日志及文件版本、配置和队列版本。同编号重新派发不复用令牌。人工完成令牌不能用于撤回。

消费者缺少整个字段、缺少令牌或读取失败时禁用入口。UI 确认弹层必须保留打开时的 id 和 token，不能刷新后偷偷换成新令牌重试；失败后刷新并让用户重新确认。保留原 schema 的已有字段，忽略不认识的新增字段。

```sh
drover return-to-pending Tn --target-token '<令牌>' --reason '撤回原因' --work-stopped --json
```

id、token、去首尾空白后非空的 reason、`--work-stopped` 和 `--json` 必填。原因内部换行与文字保留。`--work-stopped` 表示用户明确确认相关实际工作已经停止，drover 不向 corral 查询或发送消息，不运行 CHECK_CMD。

成功退出 0，stdout 是单个 JSON：

```json
{"schema_version":1,"ok":true,"task_id":"T1","state":"pending","paused":true,"return_record":{"dispatched_at":1790000000,"returned_at":1790000100.5,"reason":"撤回原因","work_stopped":true}}
```

时间为 Unix 秒。同编号、派发时的标题和正文回到 pending 首位；原 queue.md 中该编号的块（或其未编号的同标题原块）被替换，其他任务顺序不变。运行期间手改的本任务正文不覆盖派发快照。队列暂停，current/awaiting 为空；不改变 loop 开关，不派发任何任务。后续由用户 `resume` 并 `next`；恢复后原有 loop 条件若已满足，也可能按既有规则派发。

## 历史与详情

`list --json` 的 pending/current/awaiting/history 任务对象，以及 `show --json` 的 task 对象，增加可选 `return_history`，按撤回时间正序保存上述 return_record。旧任务没有该字段，不补造历史。重新派发、再次撤回、之后完成或放弃均保留此数组。

撤回后 `show.task.location`、`show.task.status` 都是 `pending`；`timing` 保留刚结束运行的起止时间；`completion` 为 `{scope:"not_applicable",rows:null,unavailable_reason:"task_pending"}`，不推导通过。该任务不进入 list.history，也不计入 Done/Dropped。show 在新一次派发后显示新运行，而 return_history 继续保留之前的派发/撤回时间和原因。从未派发的普通 pending 沿用原 show 不查询的规则。

## 拒绝与失败

```json
{"schema_version":1,"ok":false,"error":{"code":"target_changed","why":"供人阅读的说明"}}
```

| code | 退出码 | 含义 |
|---|---|---|
| `target_changed` | 3 | 不再是同次 current、awaiting、重复确认、跨项目，或状态/配置/队列版本变化 |
| `state_busy` | 4 | 同一交接目录存在其他 CLI 写操作 |
| `invalid_arguments` | 2 | 参数、令牌格式、空原因或停止确认不合法 |
| `repository_unavailable` | 2 | 无法确定 Git 项目 |
| `not_configured` | 2 | 未配置交接目录 |
| `configuration_unreadable` | 2 | 配置无法可靠读取 |
| `state_unreadable` | 2 | 状态日志无法读取 |
| `state_invalid` | 2 | 日志损坏或运行身份不可靠 |
| `snapshot_unavailable` | 2 | 队列无法可靠读取 |
| `write_failed` | 2 | 发布失败，刷新核对当前状态 |

消费者只按 code 判断，why 不作协议。共享写锁覆盖读取、目标校验和发布，和 next/done/go/drop/edit/move/pause/resume 等命令互斥。目标验证失败不发布撤回事件。

多文件按安全顺序发布：先准备并 fsync 临时内容，复核版本，再暂停、原子替换队列，最后原子发布完整撤回事件。不是跨文件数据库事务：**write_failed 或进程中断可能留下暂停及队列排序变化，但在正文恢复前不会结束运行**。失败后刷新，不把错误当成成功，也不自动恢复队列。原事件日志前缀保留。

## 部署与常驻引擎

CLI 每次启动加载新版，已有软链指向本仓库时无需重装。单次 `show` / `return-to-pending` 不依赖重启；但旧版常驻引擎/看板不能解释新增 return 事件，必须重新启动才能加载新代码。在让常驻引擎处理含 return 的项目之前，应完成重载，不能把 CLI 更新当成引擎已升级。所有项目 loop off 时，旧引擎的推进路径不处理任务；独立通知检查仍可能更新去重记录。

对已加载的本机 LaunchAgent，用户授权后可运行以下公开系统命令（本次仅列出，未执行）：

```sh
launchctl kickstart -kp "gui/$(id -u)/dev.drover.loop"
launchctl print "gui/$(id -u)/dev.drover.loop"
```

第一条停止旧实例并立即启动新版，打印 PID；第二条核对新 PID 和 running 状态。无须重新安装、修改 plist/PATH 或新开第二个 loop。正在运行的旧 curses 看板也需退出后重开。

**重启可能推进其他真实队列。** 引擎启动后立即检查全部登记项目，沿用各自已有 loop 开关：启用的项目可能核对当前任务、执行 CHECK_CMD、记 done，或按 gate/待办/暂停等条件派发下一件。`pause` 只阻止发新任务，不阻止当前任务被检查和记完成。重启本身不修改项目开关，但不是“只加载代码、不干活”的操作。

若要求不推进任何真实队列，应在执行前重新只读核对所有登记项目 loop 均关闭，并确认没有进行中的 drover 写命令；若不是，不要直接重启，先取得对各项目后续操作的授权。不能仅暂停目标项目就假定其余项目不受影响。loop 全关只保证不推进任务，通知去重等引擎内部文件仍可能更新。

2026-09-29 本轮只读核对：服务仍为 PID 37103（2026-09-28 20:10:54 启动），drover/jb-finetune/saddle 的 loop 均关闭；这是瞬时观察，不替代部署前复核。本次未重启服务或改变真实项目开关，真实 T29 实验仍由用户执行。
