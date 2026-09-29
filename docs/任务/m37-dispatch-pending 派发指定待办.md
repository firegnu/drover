# 任务：派发指定 Pending 任务的公开接口

2026-09-29，drover/main 交给 Codex drover/dev-dispatch-pending（start --unique 的实际名以返回值为准）。重档：gpt-6-astra / xhigh。
路由：重 / 交叉审查要 / 影响面：碰要害（路由 tier.verdict 拿不准，主控因并发目标校验和外部发送边界选重；cross_review.verdict=要，impact.verdict=碰要害）。
类型：功能变更
依据：用户授权 Drover 先提供指定 Pending 派发接口，Saddle 后续另行放行。
提示：围绕已确认的使用目标完成变更，优先沿用现有机制。
你是被委派的 agent：照本文件做，不再开任何 agent。

## 先读

- AGENTS.md；HANDOFF.md 顶节。
- 本任务下方用户委托原文。
- bin/drover：issue/start_task/cmd_next、list JSON、task_write_lock、已有人工操作 JSON。
- bin/drover-board：task_blocks/task_pending、corral 封装；只读 corral 的 docs/CONTRACT.md，不读源码/内部状态。
- docs/ROADMAP.md「全部动作」「D1 分步」与 docs/撤回JSON接口.md（已存在的写锁/令牌风格）。

## 在哪里干活

- worktree：/Users/firegnu/Developer/personal_projs/drover-worktrees/m37-dispatch-pending
- 分支：m37-dispatch-pending，从本任务提交后的 main 建立。
- 只改 bin/drover、必要时 bin/drover-board、直接相关合成测试和公开接口/使用文档、本任务完成记录。主仓库工作区不要改。

## 要做的 / 怎么算做完

下方用户委托中的「要交付的能力」「范围与边界」「交付回复」为原始要求，照做，不增加产品功能。
接口命名建议 `dispatch-pending --pos N --target-token TOKEN --json`，目标从 `list --json` 的每项 pending 上读专属字段；位置用于区分未编号/同名条目，token 校验完整展示身份。由你依现有代码确定最终参数、字段与错误契约，在 docs/指定派发JSON接口.md 写清楚并在回复中回报。无需实现 UI，也不向 Saddle 发任何消息。

验证预算：新增一份公开 CLI 合成专项，保留先 RED 后 GREEN，覆盖用户要求的身份变化、已有运行/暂停/awaiting、正常送达/拒绝/结果不确定、本地写入失败和写锁边界；只用临时合成项目、假 corral。回归一次 `bash tests/drover.sh`、`python3 tests/list-json.py`、`python3 tests/show-json.py`、`python3 tests/manual-complete.py`、`python3 tests/return-to-pending.py` 和 `git diff --check`。无需全仓库套件或另建覆盖矩阵，觉得预算不足在回复说明。不能运行包含 PTY 录屏的 tests/drover-board.sh 或 *pty* 检查。

## 不要做

- 不读写真实任务队列/状态/开关，不派发/恢复真实 T45、T29，不重载服务，不安装、不推送；不改 Saddle、corral、corral-dispatch、dispatch-log 或全局技能。
- 不按项目名批量杀进程，不关闭用户 agent；所有验证用合成数据，命令在前台跑完。
- 不把发送与本地记录说成原子事务，不自动重试，不用 move+next，也不另建一套任务状态机。
- 对既有 issue 的非确定传输结果和 MAIN_AGENT 未配置路径，要如实在机器字段区分实际发送与本地记账，不解析中文 stdout 充当结构化接口。若与复用现有规则有实质矛盾，停下向主控报告最小选择。
- 不合并 main。只在本分支提交；不做无关重构或文案整理。

## 做完

在本文件末尾追加「## 完成记录」：实现、验证、契约、取舍、未做项，各几句话，一并提交。回报提交 SHA 和契约文档路径。命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 用户委托原文

# 交接：Drover 派发指定待办任务的公开接口

用户已明确授权：
“你先让drover/main先实现这个接口。之后咱们再来saddle放行这个T45，我已经把这个任务从runnning放回到pending了”

原始需求：在 Tasks 列表增加按钮派发选中的任务，无需用户每次手工调整队列顺序。此次只交接 Drover 接口实现；Saddle T45 已撤回 Pending，接口完成后仍须由用户重新放行，不能自动启动 Saddle 实现。

## 要交付的能力
提供可被 CLI 和上层界面调用的“派发指定 Pending 任务”公开接口。Drover 负责目标核对、现有派发条件、调用既有 corral 发送路径和正确的任务状态记录。Saddle 后续只负责按钮和反馈。
现有 cmd_next 只取第一项，Current 存在时会重发 Current；公开 next 不接受任务目标。不能用上层拼接 move + next 代替这个接口，因为两条命令之间存在目标变化窗口，且失败会留下排序变化。

目标是在一次既有任务写锁内校验目标与正常派发条件并执行指定目标的既有派发路径。选择 Pending 不得变成重发 Current，不绕过暂停、当前进行中或等待放行约束。保持未选中待办的相对顺序，避免调用方先改队列顺序。复用现有派发/状态规则，不建立另一套流转。
公开契约需让调用方基于刚展示的目标识别/校验，避免列表变化后误派；接口命名、参数、JSON及退出码由你依现有规范确定。发送失败/结果不确定时如实返回，不把外部发送与本地落盘宣称为不可分割事务，不靠自动重试补救。

## 范围与边界
只改 Drover 必要代码、直接检查和接口/使用文档，按你仓库流程完成审查、合并和交接；不推送、不部署或重启常驻服务。若确需部署，单独说明原因和操作影响，等待用户授权。
不修改 Saddle、corral、corral-dispatch、dispatch-log 或全局技能。不得操作任何真实项目队列/开关/任务，尤其不得派发或推进真实 T45、T29；用临时合成项目、假 corral 验证。
这不是要求你绕过项目主控开发规范；按自己的项目流程办。如遇实质设计歧义或额外上游缺口，说明最小选择，不扩张范围。

## 交付回复
说明实现与验证结果、提交 SHA、公开命令示例、调用方如何读取目标/校验信息、成功/失败 JSON与退出码，以及旧CLI兼容和是否需重载。将契约写入你的 repo 文档并给出路径，供 Saddle 在后续放行后读取。
命令都在前台跑完，全部做完后，回复最后一行写 DONE。
