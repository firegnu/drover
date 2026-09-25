# 任务：增加任务详情只读 JSON 接口

2026-09-26，drover/main 交给 drover/dev-show-json（Codex，常规：gpt-6-astra / high）。
路由：常规 / 交叉审查不要 / 影响面：改行为（路由：三项均拿不准；按技能回退）
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读
- AGENTS.md；docs/ROADMAP.md「完成判据」及任务记账相关节。
- bin/drover：setup、list、完成判定；bin/drover-board：task_view、card_vm、check_result_vm、wants_human、task_route、task_holds。
- tests/list-json.py、tests/check-result.py。

## 在哪里干活
- worktree：../drover-worktrees/m34-show-json，分支 m34-show-json。
- 只改本仓库 bin/ 中必要实现、相关定向测试、本任务文件、docs/任务详情JSON接口.md（最终公开契约）、docs/ROADMAP.md 中本功能说明。
- 不修改 saddle 或其他仓库；不读真实任务数据做测试。HANDOFF.md 由主控收尾更新。

## 目标与已批准的接口方案
增加独立 `drover show Tn --json`，可选 `--with-agent-status`。由调用 cwd 指定项目，只查询选定任务，覆盖 current/awaiting/history；默认不联系 corral，可选仅查询配置中主控的公开 status，无其他 agent 命令。调用者约每 5 秒刷新选中详情，返回列表停止查询。

按任务 ID 定位，任务完成后仍返回同一任务；不扩展 pending/未编号定位。顶层有 schema_version、ok、observed_at、task、timing、git、completion、last_check、routing、hold、attention、warnings。任务基本字段保留原文，task.location 区分 current/awaiting/history，status 沿用 doing/done/dropped。机器字段使用稳定键与原因码，why 为人读，不作为判定协议。

- timing：started_at/ended_at/released_at 与 elapsed_seconds/release_wait_seconds；current 耗时到观察时刻，awaiting 耗时到完成、等待到观察时刻；历史只使用已知事件端点。未知值 null，不冒充 0；保留 drop 未开始等缺失语义。
- git：start_head/start_main/end_head/observed_head/observed_main、range_commits、main_commits_since_start、main_tip_committed_at。区间提交数不是归属于本任务的提交数；end 是结束 HEAD，不冒充完成 main。历史没有完成 main 快照，不能伪造当时 main 进展。失败应有稳定不可用原因，只有成功得到零才给 0。
- completion：current/awaiting 只读重算，scope=current_repository；稳定 row id 为 completion_marker/main_advanced/branches_merged/check_command，给 ok（三态）、state、why。awaiting 的已记录 done 不因当前重算失败而改写。历史完整验收快照未存，rows=null、unavailable_reason=completion_snapshot_not_recorded，不套用当前任务判据。
- last_check：只读现有缓存，valid/stale/missing/invalid/unavailable，时间、ok、stale_reasons 等结构化字段。有效身份仍为 task/main/cmd，不新增完成判据；缓存不表示本次运行，也不能保证未提交内容未变。没有有效记录不等于从未运行过；命令未配置为不适用。不得把别的任务缓存当成选定任务的结果。历史最多展示属于该任务的留存样本，不能冒充完成验收快照。
- routing：复用任务文件读取，source=task_file_now；没有或读不了为 null，历史也不冒充当时不可变记录。Hold：当前使用正文/hold 事件；历史若恢复当时值需回放到对应事件，不能用现在值冒充历史；不能从 done.gate 单独推出 Hold。
- attention：awaiting 明确等待放行；历史 not_applicable；默认 current 不查 agent，标 unknown/agent_status_not_queried。可选 status 时沿用旧 wants_human 条件：主控 idle 达到观察阈值、非 agent 自发回合、存在未满足判据。未知不能猜，提示是关注推断，不证明停工。
- 错误：参数错误、未配置、任务不存在等非零并结构化错误；部分派生数据不可用返回基础任务和原因。单次查询尽量固定数据与 Git 端点；检测读期间变化则明确标记 snapshot_changed 或有限重读，不承诺全局原子快照。
- 可复用现有读取/判据；不得直接套 collect/project_state 全项目、全历史查询链。缓存校验若提取结构化辅助函数，旧看板保持原行为。旧 helper 吞 Git 错误为空字符串的行为不能让新接口伪造零；只在必要的读取边界处理，不改变核心判据语义。

最终契约文档写明准确命令、JSON字段与类型、枚举/缺失值/错误语义、current/awaiting/history 示例、只读与刷新成本限制、历史不能恢复的部分。不做 UI。

## 怎么算做完
以下照抄本轮用户授权中的要求：

> 范围覆盖 current/awaiting/history 的状态与位置、时间和耗时、Git 区间与当前进展、完成依据/判据与原因、上次验收缓存状态、路由/Hold/关注提示；默认不联系 corral，可选 with-agent-status 只允许公开 status 查询。
> 保留你评估中明确的历史缺失/当前重算/上次缓存边界，字段不可用不冒充零或通过，saddle 不解析 why 做判断。
> 核心约束：不改原任务状态机、完成判据或 list 行为；查询不执行验收命令、不写缓存/事件、不创建交接目录、不推进队列、不操作 agent。
> 若必须改变核心判定，先停下说明，不自行扩大。
> 按风险检查共享读取改造对旧看板和原命令的影响，仅用隔离合成数据验证，别推进无关真实任务。

## 验证预算与边界
按仓库 TDD 约定定向先 RED 再 GREEN。验证限：新增 tests/show-json.py 定向入口；标准 CLI 回归 bash tests/drover.sh 一次；共享判据 bash tests/criteria.sh 一次；缓存读取相关 tests/check-result.py 的非 PTY 定向用例；git diff --check。不跑包含 PTY 的全量看板入口、不录屏、不扩大到安装或其他项目测试。若共享读取实际未改，也说明哪些复用点保留原样。觉得预算不足先报告。

不操作真实队列、配置、loop、服务、安装或其他项目；不重启用户进程。不得调用真实 agent 验证接口；用假的 corral。不要按项目名批量杀进程。不合并 main、不推送，只在本分支提交。

## 做完
在本文件追加「## 完成记录」：改动、验证、实现取舍、限制和待主控决定事项。给出提交与最终契约路径。命令都在前台跑完，全部做完后，回复最后一行写 DONE。
