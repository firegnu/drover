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

## 完成记录

2026-09-26，drover/dev-show-json 完成实现，提交 **`749012e`**。
最终公开契约：[docs/任务详情JSON接口.md](../任务详情JSON接口.md)。

### 改动

- `bin/drover` 新增独立 `show Tn --json [--with-agent-status]` 入口，在原 setup 之前分流，不创建交接目录。按事件中的同一 ID 覆盖 current/awaiting/history，返回原始任务文本、时间/Git/判据/缓存/路由/Hold/关注与结构化错误。
- `bin/drover-board` 的配置解析支持传入一次读取的文本；Git 判据增加可选读取器；提取原缓存的有界读取和格式校验。原调用使用默认路径，旧判据、缓存身份和看板文案不变。
- `tests/show-json.py` 新增 15 项公开 CLI 定向测试；公开契约列出类型、枚举、原因码、缺失与历史边界、三种位置示例和刷新成本；ROADMAP 仅追加本次已批准功能说明。

### 验证与前台证据

所有命令均在前台等待退出；仅使用临时合成仓库/事件/配置及假 corral，未运行真实 agent。

- 初始 RED：`python3 tests/show-json.py` 因原版不识别 `show T1 --json` 返回 2 而失败；实现基本查询后 GREEN。
- 逐步 RED→GREEN：时间/Git/判据用例先因缺少 timing 失败；缓存/路由/Hold/关注用例先因字段不存在失败；并发写入用例先因缺少 snapshot_changed 失败，不可读事件先误报 task_not_found。分别实现后通过。
- 收尾定向 RED→GREEN：`python3 tests/show-json.py ShowJSON.test_unreadable_routing_path_is_optional` 复现路径含 NUL 导致新增快照检查抛 ValueError，修复新接口路由读取边界后完整定向入口通过。
- 最终 `python3 tests/show-json.py`：**15 项通过，退出码 0**。覆盖 current→awaiting→history、固定结束时间、drop 未开始、HEAD/main 分离、分支未合入、Git 非零退出不伪造零/通过、缓存身份/格式、历史 Hold 回放、不从 gate 推 Hold、只调用主控 status、并发变化、原文保留与全部查询只读。
- `bash tests/drover.sh`：**仅运行一次，通过，退出码 0**。
- `bash tests/criteria.sh`：**仅运行一次，通过，退出码 0**，包含损坏引用、多语言错误、收尾记号四道检查。
- `python3 tests/check-result.py CheckResult.test_deep_json_and_parser_recursion CheckResult.test_board_matching_results CheckResult.test_board_stale_results CheckResult.test_board_missing_and_invalid_results CheckResult.test_record_and_reason_limits CheckResult.test_future_time_and_collection_skew CheckResult.test_check_row_is_selected_by_number CheckResult.test_board_not_applicable_is_not_missing`：**8 个非 PTY 用例通过，退出码 0**。验证提取格式校验后旧看板的匹配/过期/坏记录/读取上限/时钟容差/按行号覆盖/不适用行为。
- `git diff --check`、提交前 `git diff --cached --check` 均通过。没有运行全量看板、PTY 录屏、安装套件或额外项目测试。

### 实现取舍与限制

- 沿用 task_fold、task_route、task_holds/task_held 和已有完成判据，不调用 collect/project_state，也不对每件历史任务做 Git 查询。任务事件仍需整体读取和折叠以确定选中位置和 Hold。
- 新接口捕获本地分支 SHA 和 HEAD，Git 查询严格检查退出码；查询错误时 Git 判据组保守降级为 unavailable。旧 helper 吞错误的默认行为留给旧调用，不改状态机或完成判定。
- completion 不把缓存当成本次执行；last_check 单独表示上次样本。历史没有完成 main 或完整验收快照，相关字段明确 null/原因码；awaiting 的已记录 done 不受当前重算影响。routing 明确来自现在的文件，历史 Hold 截至结束事件回放。
- 关注仅是原条件的推断：默认 unknown，显式选项只对 current 发一次配置主控的公开 status。信息不足不猜测，awaiting/history 无需查询 agent。
- 读取期间变化用 warnings.snapshot_changed 表达，Git 复核失败单独说明；不承诺全局原子快照。每约 5 秒刷新是调用建议，不是响应时限；具体超时与成本见公开契约。
- 严格留在 `m34-show-json` worktree/分支；未委派、合并、推送，未改 HANDOFF.md，未操作真实队列、配置、loop、服务、安装、用户进程或其他仓库。

待主控决定事项：无新增设计待决；实现与契约待主控审查，本分支未合并。

### 首轮审查返工：合法 ref 中的 U+2028（2026-09-26）

- 主控发现 `ShowGit.read_refs()` 使用 `splitlines()`，将合法分支名 `feature/name\u2028tail`（实际 U+2028）拆成两条记录，使查询退出 1 并输出 ValueError traceback。
- 仅将新读取器的记录分隔改为 ASCII `\n`，跳过末尾空记录；不截断、替换或忽略合法 ref，不改共享 `task_branches`、完成判据或公开 JSON 字段/原因码。公开契约无需变更。
- 新增 `ShowJSON.test_unicode_line_separator_in_branch_name`：在隔离 fixture 建立实际含 U+2028 的未合入分支，经公开 CLI 检查 JSON 成功返回、分支名称原样显示、判据为 unmet；合入后检查同名分支判据为 met、main 区间计数为 1、无快照误报。沿用文件快照断言保证查询只读，并确认不调用 corral。
- RED：`python3 tests/show-json.py ShowJSON.test_unicode_line_separator_in_branch_name` 在修改实现前退出 1，明确复现 `read_refs` 的 ValueError；修复后同一命令 GREEN，退出码 0。
- `python3 tests/show-json.py`：**16 项通过，退出码 0**；`git diff --check` 通过。全部命令前台跑完，未重跑已通过的 CLI/criteria/cache 套件。
- 仅改新读取器、该定向测试和本完成记录；在原 `m34-show-json` 分支提交，未合并、推送或操作真实数据。无新增待决事项，待主控复核。
