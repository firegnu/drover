# 通知 JSON 接口（schema_version = 1）

> 2026-09-30：以下是旧版记录。任务流转与观察器当前契约以[任务流转接口 v2](任务流转JSON接口.md)为准；旧 gate/loop/人工覆盖行为已退役。通知偏好 schema 1 保留，通知身份改用公开 notification_key。操作步骤见 [QUICKSTART](QUICKSTART.md)。


用户级偏好，由 Drover 保存，是系统通知开关的唯一事实来源。命令不依赖 cwd、Git 仓库或项目 init：

```sh
drover notifications status --json
drover notifications on --json
drover notifications off --json
```

参数必须按上面的顺序给出。成功退出 0，stdout 只有一个 JSON 对象，固定六个字段：

```json
{"schema_version":1,"ok":true,"scope":"user","system_enabled":false,"revision":3,"application":"next_notification_check"}
```

- `system_enabled` 是布尔值；缺失偏好文件默认为 true。
- `revision` 是非负整数；缺失文件为 0，仅实际开关变化递增。重复 on/off 幂等；默认开启时执行 on 仍为 revision 0。
- `status` 只读，不创建目录、偏好或锁文件。写操作使用文件锁串行化读改写，临时文件原子替换偏好。
- 保存成功只表示偏好已保存，**不表示常驻引擎已确认应用**。后续通知检查读取它；目前检查间隔约 60 秒，受进程调度和同步发送影响，不是生效时间上限。不能撤回在途发送或旧横幅。
- 首次部署必须使旧引擎加载新版；安装新 CLI 不会升级已经运行的进程。此项留待联合发布，本次未安装或启停真实服务。

## 错误

失败统一退出 2，stdout 仍只有一个 JSON 对象，固定 `schema_version`、`ok`、`error`：

```json
{"schema_version":1,"ok":false,"error":{"code":"preferences_invalid","message":"通知偏好格式损坏"}}
```

| error.code | 含义 |
|---|---|
| invalid_arguments | 命令、参数或顺序不符合上面的用法 |
| preferences_invalid | 偏好不是合法 UTF-8 JSON 对象，版本不支持，或开关/revision 类型、取值错误 |
| preferences_unreadable | 偏好存在但不能读取，包括路径是目录等 I/O 错误 |
| preferences_write_failed | 建目录、打开/锁定锁文件、临时写入或替换失败 |

`error.message` 供人阅读，不是稳定判据。消费者必须兼容未知错误码；错误时不猜渠道，不把它显示成保存成功。损坏文件不会由 on/off 自动覆盖。异常中断/进程崩溃不保证能输出 JSON。

## 偏好与提示范围

内部文件是当前 HOME 下的 `~/.drover/notifications.json`，写锁为同路径加 `.lock`；去重记录为 `~/.drover/board-notified.json`。这些是 Drover 内部实现，消费者不得直接读写；联调通过隔离 HOME 使用公开 CLI。XDG 不改变这些路径。

关闭只抑制本用户跨登记项目的 Drover 系统通知；不放行、不推进、不清除 Attention，不控制 Hammerspoon、agent 自身或其他渠道。Drover 不读取或调用 saddle；saddle 未运行也不自动恢复系统通知。

只提示现有任务事件折叠结果中的 `awaiting`（`list --json` 的 awaiting 对象，或 `show` 中 `task.location=awaiting`、`attention.state=awaiting_release`）。自动模式完成并直接进入下一件不弹；主控 idle 且判据未满足不弹。看板持续状态、公开 attention、任务判据和 next/done/go、loop_tick 保持原样。通知检查只读已登记项目配置及任务事件，复用原任务折叠函数，不跑完成判据、验收命令或 corral 查询。

## 稳定运行身份 v1

双方以六元组判等。所有元素为字符串；按以下顺序表示为 JSON 数组：

```json
["/absolute/canonical/repo","T1","4059000000000000","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","awaiting_release"]
```

| 元素 | 来源与规范化 |
|---|---|
| 仓库路径 | 登记的仓库根目录绝对路径；展开 `~`、消除 `.`/`..`、解析符号链接（Python `os.path.realpath`）。不额外折叠大小写或做 Unicode 归一化。saddle 使用自己的项目仓库路径作同等规范化，不用仓库简称。 |
| task.id | 现有 start 事件折叠的非空字符串，原样保留，不用标题或队列位置替代 |
| task.t0 | start 事件的 `t`，有限 JSON number，布尔/null/缺失无效；转换为 IEEE 754 binary64，±0 统一为 +0；取大端 8 字节，编码成 16 位小写十六进制字符串。示例 100 和 100.0 都是 `4059000000000000`。这避免跨语言十进制序列化差异。 |
| task.start | start 事件的 `sha`，非空字符串原样保留；是开始 HEAD，不是 done 的 end |
| task.main | start 事件的 `main`，非空字符串原样保留；是发出时 main，不是当前 main |
| 事件类型 | 固定 `awaiting_release` |

字段来自已有 list/show 任务对象，详见[任务详情 JSON 接口](任务详情JSON接口.md)。不增加 UUID，不改变任务事件格式。比较的是六元组的值，不是 JSON 空白或转义风格；Drover 内部用 ASCII 转义、无空格 JSON 数组字符串存键，saddle 可用自己的等价元组表示。

任何必需字段缺失、为空或时间不可表示时，保留既有 Attention，跳过自动提示；不按标题/T 编号猜身份。标题、正文、结束时间、当前 main 或通知文案都不参与判等。同 ID 的另一运行只要上述起点身份不同即可分别提示。仓库搬迁、备份恢复、队列重置后的身份延续不保证。

## 基线、去重与失败边界

- 每次引擎进程启动、首次升级/开启、偏好 revision 改变时，以每个项目首次成功读取的已有 awaiting 为基线，不补弹。新登记项目也先立基线。这样能捕捉两次检查间的 off→on，即便最终开关仍是 on。
- 读取项目清单失败不建立基线；单个项目配置/事件缺失、不可读或损坏时跳过该项目，待下次成功读取再立基线。空但成功读取的事件文件可以建立空基线。其他成功读取的项目照常处理。
- 已处理身份集合持续保留，不随本轮可见集合覆盖；刷新、改文案、短暂缺失后恢复、同渠道重启都不会忘记已处理身份。禁用期间成功观察到的身份也记入集合；重新开启仍先立新基线。
- 旧版文字键记录、缺失或损坏的记录以新的基线迁移/恢复，不补弹当前事项。记录无法读取或写入时跳过本次提示；任务状态和推进不受影响。
- 发送前写下已处理身份。假发送器/OS 返回失败、命令缺失或 10 秒超时均不重试；通知异常不使 `loop --once` 的通知部分报失败，不阻断后续推进。发送保持同步，可能延后后续检查。
- 记录仅用于减少重复，不是通知历史、送达回执或待投递队列。正常保留已见集合，不按当前可见集裁剪；不提供离线补发、重试、多实例选举或远程消息服务。

这是尽力提示，不承诺系统送达、用户看见或跨渠道精确一次。渠道保存到引擎应用之间有窗口，系统和 saddle 内部提示仍可能各出现一次；不以消息事务扩展本契约。

## 隔离验证

定向入口为 `python3 tests/notifications.py`，使用临时 HOME、合成项目、假 corral 和假发送器；不触发真实 OS 通知。联调直接使用本 worktree 的 `bin/drover`，不提前安装或合并。
