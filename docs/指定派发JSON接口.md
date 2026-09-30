# 指定 Pending 派发公开接口（schema_version 1）

> 2026-09-30：以下是旧版记录。任务流转与观察器当前契约以[任务流转接口 v2](任务流转JSON接口.md)为准；旧 gate/loop/人工覆盖行为已退役。通知偏好 schema 1 保留，通知身份改用公开 notification_key。操作步骤见 [QUICKSTART](QUICKSTART.md)。


2026-09-29。供 CLI 和后续上层界面派发刚展示的指定待办，复用 `issue` 的 corral 发送路径及 `start_task` 的状态记录。不重排队列、不重发 Current，不越过暂停、进行中任务或等待放行。此次没有实现 Saddle 按钮。

## 读取与提交目标

在目标 Git 项目内运行 `drover list --json`。每项 `pending` 新增：

```json
{
  "id": "T2",
  "title": "调研",
  "body": "任务正文",
  "dispatch_pending": {
    "pos": 2,
    "target_token": "d1:不透明摘要",
    "unavailable_reason": null
  }
}
```

`pos` 从 1 开始，表示这次响应的 Pending 位置。消费者保存**展示时这一项**的 `pos` 和 `target_token`，不要用任务编号、标题或自行计算的摘要代替：

```sh
drover dispatch-pending --pos 2 --target-token '<展示时的 target_token>' --json
```

三个参数必填且唯一，顺序不限；位置必须为正整数。命令总是在 stdout 返回一个 JSON，包含 `schema_version:1`，错误也不混入文本输出。开发时用本 worktree 的绝对 `bin/drover` 路径，在临时合成项目内调用。

令牌是 `d1:` 加 64 位小写十六进制字符串，但消费者**不得解析或构造**。它绑定真实项目路径、交接目录、位置、配置全文、队列全文（含标题和正文）、状态日志及三个文件的版本。配置、待办增删／重排／改名／改正文、hold、派发／结束／撤回等状态变化均会使旧令牌失效；文件改回原文也不会复活旧令牌。跨项目或跨位置不能复用。令牌只用于并发确认，不是授权凭证。

字段缺失、token 为 null、`unavailable_reason` 非 null 或整个查询失败时，消费者禁用派发入口。失败后刷新，让用户重新确认；不得偷偷换上新 token 重试。当前有任务、暂停或等待放行时，仍可提供可靠的 Pending 身份令牌；**令牌可用不表示当前允许派发**，命令会重新检查条件。

用户已确认的歧义边界：沿用既有按编号、未编号按标题识别的规则。如果派发该项会同时隐藏另一项 Pending，就不提供令牌，原因是 `target_ambiguous`，命令也拒绝，要求先补不同编号。包括未编号同名条目、编号重复，以及选择某个编号任务会覆盖同标题未编号项的情况。不同编号的同名任务、无歧义的未编号任务均可派发；后者沿用最大已有编号加一，生成编号见响应。不会为绕开歧义而改写队列或另建身份状态机。

其余令牌不可用原因可能是 `not_configured`、`configuration_unreadable`、`state_unreadable`、`state_invalid`、`snapshot_unavailable`。旧 `list` 字段和普通文本输出保留；消费者应忽略未知新增字段。

## 成功及发送结果

正常确认送达并完成本地记录，退出 0：

```json
{
  "schema_version": 1,
  "ok": true,
  "task_id": "T2",
  "state": "current",
  "delivery": {
    "status": "confirmed",
    "attempted": true,
    "corral_exit_code": 0,
    "confirmed": true,
    "merged_with_draft": false
  },
  "record": {"status": "recorded"},
  "manual_text": null
}
```

`delivery` 与 `record` 必须分开解释：

| `delivery.status` | 含义 | 通常的 `record.status` / 退出码 |
|---|---|---|
| `confirmed` | corral 返回 0，且 JSON 明确 `ok:true, confirmed:true` | `recorded` / 0 |
| `unconfirmed` | corral 返回 3；或返回 0 但没有可靠确认（含未知 agent 的 `confirmed:false`、损坏／矛盾输出） | 沿用 issue 规则记 `recorded` / 8 |
| `rejected` | corral 拒绝：2 不存在、7 非 idle、8 人工操作避让、6 沙箱拒绝 | `not_attempted` / 8 |
| `unknown` | 包装层未拿到退出结果（超时／无法启动等），或未识别退出码 | 沿用 issue 规则，不记 start：`not_attempted` / 8 |
| `not_sent` | 未配置 `MAIN_AGENT`，没有调用 corral | 沿用手动模式记 `recorded` / 0，正文在 `manual_text` |
| `not_attempted` | 目标或本地前置条件未通过，未进入发送调用 | `not_attempted` / 对应错误码 |

`attempted:true` 仅表示进入了 corral 调用，**不证明进程成功启动或文字已送出**。`corral_exit_code` 是实际拿到的子命令退出码，未拿到为 null。`confirmed`、`merged_with_draft` 保留 corral 回包中的布尔值，缺失或非布尔为 null；判断结果以 `delivery.status` 为准。`merged_with_draft:true` 表示与用户草稿拼接提交，应提示检查，不重送。

未配置 `MAIN_AGENT` 时，`ok:true` 表示既有手动记账流程完成，**并未自动送达**；调用方须显示 `manual_text` 让人自行粘贴。不能仅依据 `ok` 或 `state:current` 显示“已送达”。

## 拒绝、不确定与落盘失败

旧目标被拒绝，退出 3：

```json
{
  "schema_version": 1,
  "ok": false,
  "task_id": null,
  "state": null,
  "delivery": {
    "status": "not_attempted",
    "attempted": false,
    "corral_exit_code": null,
    "confirmed": null,
    "merged_with_draft": null
  },
  "record": {"status": "not_attempted"},
  "manual_text": null,
  "error": {"code": "target_changed", "why": "供人阅读的说明"}
}
```

| `error.code` | 退出码 | 含义 |
|---|---|---|
| `target_changed` | 3 | 位置不存在，或项目／配置／队列／状态版本与令牌不符 |
| `state_busy` | 4 | 另一个 CLI 写操作持有同一交接目录的锁 |
| `current_exists` / `paused` / `awaiting_release` | 8 | 已有运行、暂停或等待放行；未发送，也不改变这些约束 |
| `send_rejected` | 8 | corral 明确拒绝；看 `delivery.corral_exit_code` 区分原因 |
| `delivery_unconfirmed` | 8 | 发送未确认，仍按既有规则记开始；查看主控，不重送 |
| `delivery_unknown` | 8 | 实际发送结果未知，没有尝试记开始；查看主控和本地状态，不自动重试 |
| `invalid_arguments` | 2 | 缺少参数、重复／未知参数、位置或令牌格式不合法 |
| `target_ambiguous` | 2 | 现有编号／标题规则会同时匹配其他 Pending，先补不同编号 |
| `repository_unavailable` | 2 | 无法确定 Git 项目 |
| `not_configured` / `configuration_unreadable` | 2 | 缺少或无法可靠读取配置 |
| `state_unreadable` / `state_invalid` | 2 | 无法读取日志，或日志损坏／运行身份不可靠 |
| `snapshot_unavailable` | 2 | 队列无法读取，或读取期间版本变化 |
| `write_failed` | 2 | 取锁或发送后的本地记录／等待标记处理失败 |

只按稳定的 code 和结构化字段判断，不解析 `why` 或旧 CLI 的中文 stdout。遇到多项问题，返回先检查到的一项；歧义检查早于令牌比较。

`record.status` 有三种值：`not_attempted`（没有尝试记 start）、`recorded`（start 追加完成）、`unknown`（追加失败，可能没写、部分写或已经写完）。记录失败不抹掉发送结果，例如 `error.code:write_failed` 可以同时有 `delivery.status:confirmed`、`record.status:unknown`。如果 start 已经追加，只在清理 `.loop-wait` 时失败，则保留 `recorded` 和 `state:current`。

`state` 是本次结果所知的本地状态：记录完成为 `current`，记录不可靠为 `unknown`，已经选定任务但没有尝试记账为 `pending`，前置拒绝未进入派发为 null。`task_id` 在进入 issue 后才非 null，不能把错误响应中的 null 当作“任务不存在”。

## 写锁与兼容边界

一次既有 `.tasks.lock` 覆盖重新读配置／队列／状态、核对目标和条件、调用 corral、记录 start 与清理等待标记；与 next、done、go、drop、edit、move、hold、pause、resume 等既有写命令互斥。查询只读，不创建锁或交接目录。发送前再复核文件版本；绕过锁直接写文件仍不受互斥保证，尤其是发送已经开始后的改动。

`queue.md` 完全不写，未选中待办保持相对顺序。没有 CHECK_CMD 执行、队列 move、额外 corral 查询／强制发送或自动重试。拒绝或未知结果时不新增 `.loop-wait` 来安排一次后续 next；已经存在的 loop 开关／等待标记保持。独立引擎仍按原有开关和状态工作，本命令不承诺停止既有自动推进。

**外部发送与本地记录不是原子事务。** 发送已到达但写入失败、进程中断、CLI 输出丢失，都可能使调用方无法确认最终状态；追加事件仍沿用既有写入机制，不增加崩溃恢复保证。调用方应刷新并人工核对主控，不根据“仍显示 Pending”就自动重送，也不要把退出非零当作“确定没有送出”。

旧 `next` 仍取第一项、有 Current 时重发 Current，其文本、退出码和原有循环行为不变。没有新增任务事件或修改折叠状态机。普通 CLI 每次启动加载脚本，合入后即可使用新接口；**本功能无需重载常驻引擎或重新安装**，支持本次基线事件格式的引擎也可读取同样的 start 事件。本次已通过主控及独立审查并本地合入 main，未推送、部署、重启服务或操作真实队列；没有进行 Saddle 联合验证或恢复 T45。
