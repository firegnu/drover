# 任务详情 JSON 接口（schema_version = 1）

在目标项目仓库或其子目录运行：

```sh
drover show T5 --json
drover show T5 --json --with-agent-status
```

任务 ID 必须是 `T` 加数字，位于选项之前；两个选项可以交换顺序，不能重复。
`--json` 必填。项目由调用 cwd 的 Git 顶层目录确定，从该目录读取 `.drover.conf`。
只定位已有 start/done/drop 事件的任务，不支持 pending、未编号任务或按标题查找。
同一 ID 完成或放行后仍可查询；`task.location` 区分位置。

标准输出始终是单个 JSON 对象，文本使用 JSON 转义，解码后保留任务原文（包括换行、控制字符）。
调用者应安全显示文本，不把原始正文作为终端转义指令执行。
成功退出码 0；基础查询失败退出码 2。部分派生数据不可用仍返回 0、`ok: true` 和基础任务。
`ok` 表示查询成功，不表示任务通过验收。判定只用结构化字段；**不得解析 `why`**。

## 顶层与任务

成功响应固定包含以下字段；错误响应见后文。下文 `number` 均为有限 JSON 数字，时间是 Unix 秒，耗时是秒。

| 字段 | 类型 | 含义 |
|---|---|---|
| schema_version | integer | 当前为 1 |
| ok | boolean | 成功响应为 true |
| observed_at | number | 本次查询开始的观察时刻 |
| task | object | 事件流折叠后的原始任务字段，加 location |
| timing | object | 事件时间与耗时 |
| git | object | 保存的起止点和当前观察的 Git 信息 |
| completion | object | 当前只读重算或历史缺失说明 |
| last_check | object | 现存验收缓存的读取与身份校验结果 |
| routing | object / null | 现在的任务文件路由 |
| hold | object | 正文与 hold 事件给出的做完停状态 |
| attention | object | 等待放行或关注提示 |
| warnings | array of objects | 本次读取一致性提示；没有提示为 [] |

`task` 保留现有事件折叠的字段和缺失语义，不从现在的 queue.md 补写历史正文：

| 字段 | 类型 / 是否存在 | 含义 |
|---|---|---|
| id, title, body, key, start | string / 必有 | 编号、原始标题、原始正文、记账匹配键、开始 HEAD；未记录文本/起点为空字符串 |
| status | string / 必有 | doing、done、dropped |
| location | string / 必有 | current、awaiting、history；awaiting 的 status 仍为 done |
| main | string / 有 start 时存在 | 发出时的 main；旧事件缺失时为空字符串 |
| t0 | number / null / 有 start 时存在 | 开始时间 |
| end | string / 有 done 时存在 | done 记录的结束 HEAD；**不是完成时的 main** |
| t1 | number / null / 有 done/drop 时存在 | 完成或放弃时间 |
| t2 | number / null / 有 go 时存在 | 放行时间 |
| reason | string / 有 drop 时存在 | 放弃原文 |

未开始就 drop 没有 t0/main/end；body 没有被保存，折叠结果的空字符串不证明当时正文为空。

## timing

所有字段必有，类型均为 `number | null`。

| 字段 | 计算端点 |
|---|---|
| started_at / ended_at / released_at | t0 / t1 / t2；缺失为 null |
| elapsed_seconds | current：started_at → observed_at；awaiting/history：started_at → ended_at |
| release_wait_seconds | awaiting：ended_at → observed_at；history：ended_at → released_at；current 通常为 null |

端点未知或顺序倒置时耗时为 null；只有已知端点相等才是 0。
自动完成后无 go 事件的历史等待时长为 null，不是 0。放弃前未开始的耗时为 null。

## git

| 字段 | 类型 | 含义 |
|---|---|---|
| start_head / start_main / end_head | string / null | 事件记录的 start / main / end，空字符串转 null |
| observed_head / observed_main | string / null | 本次读取的 HEAD 和 main 提交 ID |
| range_commits | integer / null | current：start_head..observed_head；awaiting/history：start_head..end_head 的 rev-list 计数 |
| main_commits_since_start | integer / null | current/awaiting：start_main..observed_main 的计数；history 恒为 null |
| main_tip_committed_at | integer / null | **当前观察到的** main 顶端提交的 committer 时间；历史查询也只代表现在 |
| unavailable_reasons | object | 不可用字段名 → 稳定原因码；可用字段不出现在此映射 |

区间计数是 Git 可达集合之差，**不是归属于该任务的提交数**。
历史没有保存完成时 main，不能用 end_head 或现在的 main 伪造当时进展。
成功读出 0 才返回 0；无效对象、查询失败、Git 错误都不冒充零。

原因码：`start_head_not_recorded`、`start_main_not_recorded`、`end_head_not_recorded`、
`observed_head_unavailable`、`main_unavailable`、`git_query_failed`、`completion_main_not_recorded`。
observed_head/observed_main 本身不可用时使用 `git_query_failed`；main 的确不存在也归入此类。

## completion

| 字段 | 类型 | 含义 |
|---|---|---|
| scope | string | current/awaiting 为 current_repository；history 为 recorded_history |
| rows | array / null | 当前仓库的四行依据/判据；历史为 null |
| unavailable_reason | string / null | 历史固定 completion_snapshot_not_recorded；当前为 null，问题落在各行 |

行结构：`{id: string, ok: boolean|null, state: string, reason: string, why: string}`。
行顺序和 id 固定：`completion_marker`、`main_advanced`、`branches_merged`、`check_command`。

| state | ok | reason |
|---|---|---|
| met | true | marker_found / criterion_met |
| unmet | false | marker_not_found / criterion_unmet |
| unavailable | null | start_main_not_recorded / main_unavailable / git_query_failed |
| not_applicable | null | marker_not_configured / check_not_configured |
| not_run | null | check_not_run |

复用已有收尾记号四道检查、main 前进和分支合入判据，固定本次读取的本地分支端点。
可选读取器只用于新接口：遇到 Git 错误保守地把 Git 判据组标为 unavailable；旧判据入口不变。
`check_command` 始终不执行，只表示是否配置了命令；上次缓存放在 last_check，不混入本次判据。
awaiting 的已记录 done 不因现在判据 unmet/unavailable 改写。历史未保存完整验收快照，绝不套用当前仓库判据。
这里也不承诺涵盖工作区干净、agent 工作状态等推进命令的全部前置条件，不是新的推进授权。

## last_check

| 字段 | 类型 | 含义 |
|---|---|---|
| status | string | valid / stale / missing / invalid / unavailable |
| applicable | boolean | 当前配置是否有 CHECK_CMD |
| scope | string | current/awaiting 为 current_identity；history 为 retained_sample |
| checked_at | number / null | 属于选定任务的有效格式记录时间；没有则 null |
| ok | boolean / null | 身份有效时的原记录 ok；其他情况为 null |
| record | object / null | 仅属于选定任务的有效格式样本，字段见下 |
| stale_reasons | array of strings | task_changed / main_changed / command_changed；没有为 [] |
| unavailable_reason | string / null | 下表原因；无则 null |

`record` 只含 `task/main/cmd/why`（string）、`ok`（boolean/null）、`t`（number）。
读取 `.check-result` 最多 65537 字节，超过 65536 字节、why 超过 4096 字符、格式或编码无效、
非有限时间、时间超过 observed_at + 5 秒等按 invalid 处理；沿用旧看板的格式校验。

| 情况 | status | unavailable_reason / 返回样本 |
|---|---|---|
| 未配置 CHECK_CMD | unavailable | check_not_configured；applicable=false，不读取样本 |
| 文件不存在 | missing | cache_missing |
| 文件格式不合格 | invalid | cache_invalid |
| 文件不可读 | unavailable | cache_unreadable |
| 属于其他任务 | stale | cache_for_other_task；仅 stale_reasons=[task_changed]，record/checked_at/ok 均为 null |
| 同任务但无法确认当前 main | unavailable | main_unavailable；保留 record，ok=null |
| 同任务，main 或命令改变 | stale | 原因为 null，详见 stale_reasons；保留 record，ok=null |
| task/main/cmd 都匹配 | valid | 原因为 null；ok 等于保存值 |

valid 仅表示已有样本匹配**当前身份**；**不表示本次执行了验收，不保证未提交内容没有改变**。
没有有效记录不等于从未运行过。历史的 retained_sample 最多是该任务留存的一次样本，
其身份也与现在的 main/CHECK_CMD 比较，永远不是完成验收快照。该缓存不参与完成判定。

## routing、hold、attention

`routing` 为 null，或 `{source: "task_file_now", tier: string, cross: boolean, overridden: boolean}`。
tier 是现有解析器读出的档位文字（通常为 `轻/常规/重`，不限定枚举）。沿用任务正文的显式任务文件引用，或 TASK_FILE_DIR 中标题前缀匹配。
没有文件、未配置目录、读不了或没有可解析路由均为 null。历史也读**现在的文件**，不是当时路由快照。

`hold` 为 `{enabled: boolean|null, scope: string, unavailable_reason: string|null}`。
current/awaiting 的 scope=current_events；history 为 task_end_events，回放 hold 事件到该任务最后的 done/drop。
enabled 复用正文的“做完：等我放行”与 hold 事件；**不从 done.gate 推出 Hold**。
未保存正文且没有明确开启依据时 enabled=null，原因 task_body_not_recorded；其余原因为 null。
历史 drop 未开始时尤其可能无法恢复原正文的 Hold。

`attention` 固定包含 `state/reason`（string）、`unmet_rows`（行 id 数组）、`agent`（object/null）、`inference`（boolean）。

| state | reason | 含义 |
|---|---|---|
| awaiting_release | awaiting_release | 明确等放行，inference=false |
| not_applicable | historical_task | 历史不判断关注，inference=false |
| unknown | agent_status_not_queried | current 默认不查 agent |
| unknown | main_agent_not_configured / agent_status_unavailable / agent_state_unknown / agent_observation_incomplete / criteria_unavailable | 信息不足，不猜 |
| none | agent_not_idle / agent_self_turn / idle_below_threshold / no_unmet_criteria | 这次观察不产生关注提示 |
| suggested | idle_with_unmet_criteria | 达到旧 wants_human 条件的关注推断 |

current 的 inference=true；它不是“已经停工”或“需要干预”的证明。
可选 `--with-agent-status` 仅对 current 查询一次配置中的 `corral status <MAIN_AGENT>`，不查询其他 agent。
awaiting/history 即使带该选项也不查 agent。
suggested 要求主控 idle、idle_for ≥ 120 秒、输入来源明确为 send/human，且至少一条只读重算的依据/判据 ok=false。
agent 自发回合被排除，缺字段或未知值不给出肯定推断。上次验收缓存不参与此推断。
agent 非 null 时只含 `name/state/last_input_source`（string/null）及 `idle_for`（number/null），name 为配置名称；未知值转 null。

## 一致性、只读边界与成本

一次查询读取一份配置和事件文本，捕获 HEAD 与本地分支 SHA，派生 Git 查询使用捕获的端点。
读完检查配置、事件、缓存、候选任务文件/目录的元数据，以及 Git refs/HEAD 是否改变。

warnings 元素为 `{code: string, sources: string[]}`：

- `snapshot_changed`：检测到读取期间变化。sources 为 configuration、tasks.state、check_cache、routing_file、routing_directory、git_refs、git_head 中的一项或多项。可在下一刷新重试，不把此响应当成一致快照。
- `snapshot_verification_unavailable`：无法完成 Git 端点复核，sources=[git]。

这不是全局原子快照，无法发现所有瞬时改变后恢复的竞争；不会锁仓库或队列。
不调用 collect/project_state，不逐项查询其他任务的 Git 历史；需要顺序读取 tasks.state 才能确定位置和 Hold。
成本随事件文件大小、选定任务的 Git 区间和本地分支数增长；路由前缀匹配可能枚举任务目录。
本接口不持久缓存派生数据。建议只在详情打开时约每 5 秒刷新一次，上一请求结束后再发下一次，回列表即停止。
Git 子命令各有 30 秒超时，可选 status 最多等 10 秒；**5 秒是调用建议，不是响应时限保证**。

查询不执行 CHECK_CMD、不写缓存/事件、不建交接目录、不推进队列、不改变任务状态、配置或服务。
默认零 corral 调用；可选仅 status，无 send/ls/start/attach/stop。
旧 list 文本/JSON、看板和推进命令的原行为保持。

## 错误

```json
{"schema_version":1,"ok":false,"observed_at":1800000000,"error":{"code":"task_not_found","why":"没有该任务的开始或结束记录；不查询待办"}}
```

全部退出码 2，错误响应不带成功对象中的 task/timing 等字段。稳定 error.code：
`invalid_arguments`、`not_repository`、`repository_unavailable`、`not_configured`、
`configuration_unreadable`、`state_unreadable`、`state_invalid`、`task_not_found`。
交接目录/事件文件不存在按没有任务处理，不创建目录。事件文本损坏时拒绝返回可能错误的任务位置；不修改旧命令的宽容解析规则。

## 三种位置示例

下面为同一任务先 current、后 awaiting、最后 history 的**字段节选**，省略字段仍按前文完整返回。
`a…/b…` 表示完整提交 ID，示例数字为合成事件时刻。

current（查询时刻 130，任务开始于 100）：

```json
{
  "schema_version": 1, "ok": true, "observed_at": 130,
  "task": {"id":"T5","title":"示例","body":"原始正文","key":"示例","start":"a…","main":"a…","t0":100,"status":"doing","location":"current"},
  "timing": {"started_at":100,"ended_at":null,"released_at":null,"elapsed_seconds":30,"release_wait_seconds":null},
  "git": {"start_head":"a…","start_main":"a…","end_head":null,"observed_head":"b…","observed_main":"b…","range_commits":1,"main_commits_since_start":1,"main_tip_committed_at":120,"unavailable_reasons":{"end_head":"end_head_not_recorded"}},
  "completion": {"scope":"current_repository","rows":[
    {"id":"completion_marker","ok":true,"state":"met","reason":"marker_found","why":"发现空收尾提交"},
    {"id":"main_advanced","ok":true,"state":"met","reason":"criterion_met","why":"main 已前进"},
    {"id":"branches_merged","ok":true,"state":"met","reason":"criterion_met","why":"没有未合并分支"},
    {"id":"check_command","ok":null,"state":"not_run","reason":"check_not_run","why":"本次只读查询不执行验收命令"}
  ],"unavailable_reason":null},
  "last_check": {"status":"missing","applicable":true,"scope":"current_identity","checked_at":null,"ok":null,"record":null,"stale_reasons":[],"unavailable_reason":"cache_missing"},
  "routing": null,
  "hold": {"enabled":false,"scope":"current_events","unavailable_reason":null},
  "attention": {"state":"unknown","reason":"agent_status_not_queried","unmet_rows":[],"agent":null,"inference":true},
  "warnings": []
}
```

awaiting（done 于 160，观察时刻 180；当前重算结果与已记录 done 分开）：

```json
{
  "task": {"id":"T5","status":"done","location":"awaiting","end":"b…","t0":100,"t1":160},
  "timing": {"started_at":100,"ended_at":160,"released_at":null,"elapsed_seconds":60,"release_wait_seconds":20},
  "completion": {"scope":"current_repository","rows":[
    {"id":"completion_marker","ok":null,"state":"unavailable","reason":"git_query_failed","why":"Git 或任务起点不可用，无法重算"},
    {"id":"main_advanced","ok":null,"state":"unavailable","reason":"git_query_failed","why":"Git 或任务起点不可用，无法重算"},
    {"id":"branches_merged","ok":null,"state":"unavailable","reason":"git_query_failed","why":"Git 或任务起点不可用，无法重算"},
    {"id":"check_command","ok":null,"state":"not_run","reason":"check_not_run","why":"本次只读查询不执行验收命令"}
  ],"unavailable_reason":null},
  "attention": {"state":"awaiting_release","reason":"awaiting_release","unmet_rows":[],"agent":null,"inference":false}
}
```

history（go 于 190；之后再查不会继续累计耗时）：

```json
{
  "task": {"id":"T5","status":"done","location":"history","end":"b…","t0":100,"t1":160,"t2":190},
  "timing": {"started_at":100,"ended_at":160,"released_at":190,"elapsed_seconds":60,"release_wait_seconds":30},
  "git": {"start_head":"a…","start_main":"a…","end_head":"b…","observed_head":"b…","observed_main":"b…","range_commits":1,"main_commits_since_start":null,"main_tip_committed_at":120,"unavailable_reasons":{"main_commits_since_start":"completion_main_not_recorded"}},
  "completion": {"scope":"recorded_history","rows":null,"unavailable_reason":"completion_snapshot_not_recorded"},
  "last_check": {"status":"missing","applicable":true,"scope":"retained_sample","checked_at":null,"ok":null,"record":null,"stale_reasons":[],"unavailable_reason":"cache_missing"},
  "routing": null,
  "hold": {"enabled":false,"scope":"task_end_events","unavailable_reason":null},
  "attention": {"state":"not_applicable","reason":"historical_task","unmet_rows":[],"agent":null,"inference":false}
}
```
