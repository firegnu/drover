# 人工完成公开接口（T36，schema_version 1）

2026-09-28，drover/main 在 saddle DESIGN §49 和 T36 实施委托批准语义内固定。本文是 saddle 消费方契约；实现审查通过前不是可用功能声明。本阶段只在实现 worktree 交付，不合并安装。

## 查询目标

在目标项目 Git 工作目录执行 `python3 <drover绝对路径> show Tn --json`。
保留既有字段，新增顶层 `manual_completion`：

```json
{"target_token":"不透明字符串", "unavailable_reason":null}
```

仅当前运行、身份和读取快照可靠时提供令牌；其他情况 `target_token:null`，`unavailable_reason` 是机器可读原因。消费者不可组装或解析令牌。令牌绑定真实项目路径、具体 start 事件及所读取的任务状态／配置版本，不能仅绑定 T 编号。相同 T 编号重新开始也不是同一运行。查询无副作用，不执行 CHECK_CMD，不创建锁文件。已有 show 的检查和 last_check 字段供弹层展示；本次人工操作不运行验收命令。令牌不要求 Git 条件满足。

成功查询中的 `unavailable_reason` 为 `target_changed`（不在当前运行位置）、`state_invalid`（事件无法可靠确定运行）或 `snapshot_unavailable`（必要快照不可读或查询期间有变化）。查询本身失败仍沿用 show 的错误结构。任何任务事件或配置文件版本变化都会使旧令牌失效；Git 条件变化不单独使令牌过期，确认时重新只读采样并保存结果。

## 人工确认命令

```sh
python3 <drover绝对路径> complete-manually Tn --target-token '<show返回的令牌>' --reason '用户填写的原因' --json
```

必须在同一目标项目调用。reason 为去掉首尾空白后非空字符串，保留内部文字。确认时重新核对当前运行和令牌；过期或跨项目、已经结束／等待放行的目标一律拒绝，刷新后由用户重新确认，不能操作后继任务。重复提交旧令牌不会追加第二次完成记录。

成功退出 0，stdout 为单个 JSON：

```json
{"schema_version":1,"ok":true,"task_id":"T1","state":"awaiting_release","completion_record":{"method":"manual","reason":"用户填写的原因","confirmed_at":1790000000.0,"completion":{"scope":"current_repository","rows":[],"unavailable_reason":null},"last_check":{},"workspace":{"state":"dirty","tracked_dirty":true}}}
```

`completion` 和 `last_check` 使用 show 现有同名结构，保存确认时快照而非事后重算结果；rows 保留现有四个检查 ID 与状态枚举。`check_command` 是 `not_run` 或 `not_applicable`，last_check 仅为带有效性和陈旧原因的留存样本，不等于本次执行通过。`workspace` 为 `{state:"clean"|"dirty",tracked_dirty:boolean}`，沿用仅检查 tracked 工作区的范围。`confirmed_at` 为 Unix 秒数。method 固定 manual。

失败 stdout 同样为单个 JSON：

```json
{"schema_version":1,"ok":false,"error":{"code":"target_changed","why":"供人阅读的说明"}}
```

错误码：`invalid_arguments`（参数／空原因／令牌格式错误）、`target_changed`（令牌与当前项目运行或状态／配置不符）、`state_busy`（无法取得操作互斥）、`repository_unavailable`、`not_configured`、`configuration_unreadable`、`state_unreadable`、`state_invalid`、`snapshot_unavailable`（无法可靠获得检查快照）、`write_failed`。target_changed 退出 3，state_busy 退出 4，其他失败退出 2。消费者按 code 判断，why 不作协议。失败不产生人工完成事件，不改为确认下一任务；锁等内部协调文件不算任务状态。

## 完成记录与放行边界

成功以一个可折叠的完成事件持久化 receipt，固定 gate=true，即使 TASK_GATE=0。`list --json` 的 current／awaiting／history 任务对象及 `show --json` 的 task 对象增加可选 `completion_record`，值就是上述人工记录；普通历史未记录此信息时省略，不倒填自动通过。人工记录不会被后续 go 清除。原 show.completion 仍是其既有作用域，人工快照只读 task.completion_record，二者不得混淆。

人工完成不执行 CHECK_CMD，不调用 go／next、不发送任务、不更改 loop 或 pause 开关、不停止 agent、不改 Git 文件／分支／提交。既有普通 go、自动判据和引擎保持原语义；引擎无人工覆盖入口。人工完成后保持等待放行，用户正常 go 后才解除，loop 若本来开启可按既有引擎流程继续。可维护既有等待放行标记以支持该流程，但不可打开原本关闭的 loop。面向用户的等待文案须区分人工确认与自动检查通过。

未满足 Git 判据、工作区 dirty、验收未执行／失败均允许人工确认；身份、任务状态或必要快照的读取错误不能当作判据未满足而略过。缺失／损坏但可读取的验收缓存按既有 last_check 状态如实保留。公共状态写命令之间须保证确认目标校验和记录不会相互穿插造成错运行或绕过 gate；具体内部同步方式不属于消费契约。

实现取舍：同一交接目录的 CLI 写命令使用非阻塞互斥，涵盖读取决策、验收／发送及事件写入；忙时拒绝，普通写命令也以退出码 4 提示重试。人工事件经临时文件、fsync 和原子替换发布，旧事件内容保持；不向旧历史补写记录。人工确认只发布任务状态，普通 go 放行时为原本开启的 loop 写入既有等待标记，避免确认阶段分两份文件提交。互斥协调本版本的 CLI；不把手工改写内部状态文件变成受支持的并发写入方式。

## 阶段和调用路径

实现分支 `m36-manual-complete`，已审查 CLI：
`/Users/firegnu/Developer/personal_projs/drover-worktrees/m36-manual-complete/bin/drover`。
联调仅允许独立 HOME/XDG/TMPDIR、合成项目、假 corral／禁用真实 OS 通知发送器。实现固定 SHA：`b50d36091d54085ba56beba6768fb28f215fe6cf`，主控与独立审查均通过；包含审查归档的最终交付 SHA 见交付消息。此阶段不要调用真实项目的写命令。
