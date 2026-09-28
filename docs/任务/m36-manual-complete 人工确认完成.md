# 任务：T36 人工确认完成后等待用户正常放行

2026-09-28，drover/main 交给新 Codex drover/dev-manual-complete（start --unique 的实际名另记）。重档：gpt-6-astra / xhigh。
路由：重 / 交叉审查要 / 影响面：碰要害（路由 tier、cross_review、impact 三项 verdict 均拿不准；主控依据：具体运行身份与状态写入并发、完成／放行核心规则，按技能表确定）。路由返回 tier level=常规、score=1.45、confidence=0.32，非有效 verdict，不当作确定结论。
你是被委派的 agent：照本文件做，不再开 agent。

## 先读

- 本仓库 AGENTS.md；HANDOFF.md 仅当前顶节。
- `/Users/firegnu/Developer/personal_projs/saddle/docs/任务/T36-Drover人工完成实施委托.md`（来源提交 11c106b），以及同项目 docs/DESIGN.md §49。均只读。
- `docs/人工完成JSON接口.md`：主控已在批准语义内固定的消费契约，按此实现。
- `bin/drover` 的 show / done / go / 状态写入；`bin/drover-board` 的事件折叠和引擎等待放行。

## 在哪里干活

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/m36-manual-complete`
- 分支 m36-manual-complete，从 main 46d769915901fb9f80c2f73cd26f0477c1a94353 建立。
- 范围：bin/drover、bin/drover-board 的必要逻辑、针对性测试、人工完成契约／本任务文件／必要用法文档。不要改主仓库工作区。

## 要做的

按公开契约实现 complete-manually 和 show 目标令牌、可读人工记录。限定为当前具体任务运行的人工覆盖，始终进入等待放行，保留检查真实状态，后续使用普通 go。

状态写入须与既有 CLI 状态写命令协调，防止另一个 done／go／next／drop 等基于旧状态决定后覆写人工 gate 或确认错运行；这是契约可靠目标写入的必要边界，限最小内部同步，不扩成通用事务／审计系统。查询仍只读。如现有引擎依赖 .loop-wait，保持用户放行后已有 loop 的继续路径，但不可改变 loop/pause 开关。

完成显示不得将人工确认说成检查通过；只做必要文案分支，不重做看板。通知六字段与稳定身份协议保持原样。

## 怎么算做完

用户批准结果（以下照抄实施委托）：

- 新增公开人工完成操作，让用户对当前具体任务运行填写原因并确认完成。支持未满足 Git 条件或未执行／失败的验收条件，不声称这些检查通过；不为人工确认重跑 CHECK_CMD。记录人工确认方式、原因、时间及当时检查结果／未执行状态，list／show 可读，旧历史不得倒填自动通过。
- 目标须绑定项目和具体任务运行，不能只按 T 编号；确认目标已变或无法可靠读取／写入时拒绝，不改成处理下一任务。具体命令、身份字段、成功／错误 JSON 及错误码由你在公开契约中明确，供 saddle 直接消费。
- 人工完成固定进入 Awaiting release，即使 gate 关闭也等用户放行；不调用 go／next，不改变 loop／pause，不停止 agent，不改 Git 文件、分支或提交。保留现有自动检查及普通 go 行为，自动引擎不得自行走人工覆盖路径。

验证预算：一个针对 T36 的自动化测试文件（真实 RED→GREEN，包含与上述身份／读取写入／放行边界直接相关的边角），加标准检查 `bash tests/drover.sh`、`bash tests/criteria.sh`、`python3 tests/show-json.py`、`python3 tests/list-json.py` 各一次，`git diff --check`。全部在独立 HOME/XDG/TMPDIR、合成项目、假 corral／通知发送器中；先阅读测试的隔离方式再运行。失败只定向修复／重跑受影响检查，不加覆盖矩阵、植入缺陷、录屏或重复基线。若需要预算外验证先报告理由。

## 不要做

- 不操作真实队列／配置／通知偏好／服务，不调用真实 done/go/next/人工完成，不运行真实 loop，不启停服务或安装。
- 不改 saddle、corral、全局技能、无关 T27。不要读 corral 源码／状态目录。
- 不做任务类型、分支归属／永久忽略、核心提取、通用审计、历史迁移。
- 不运行整套 tests/drover-board.sh（含 PTY），不做 PTY 录屏。不得按项目名／路径批量杀进程。
- 不合并、不推送、不发布、不清分支／worktree，不关闭任何用户主控。
- 契约内实现细节可自行定并记下；若必须改变已批准产品流程或公开契约，先报告主控，不自行扩张。

## 做完

本文件末尾追加「## 完成记录」：改了什么、RED/GREEN 和预算内实际验证结果、内部同步等取舍、未解决项。提交实现与记录在本分支，给出固定 SHA，保持 worktree 干净，保留现场待 saddle 隔离联调。命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 完成记录

2026-09-28，被委派实现者在 `m36-manual-complete` 完成，保留 worktree 待主控审查和 saddle 隔离联调。

### 改动

- 实现 `complete-manually Tn --target-token TOKEN --reason 原因 --json`；成功单个 JSON／退出 0，强制 `gate=true`，检查不满足和 tracked dirty 可接受，必要读取失败仍拒绝。原因去首尾空白，保存 manual 方法、确认时间、四项检查状态、既有验收样本及 workspace 快照，不运行 CHECK_CMD。
- show 增加只读目标令牌，绑定真实项目、包含具体 start 的事件全文及状态／配置文件版本；跨项目、重启同编号、已结束、状态／配置变化和重复确认均不能落到别的运行。查询不创建锁，快照不可用或读取中变化不给令牌。
- 完成事件折叠保留 `completion_record`，list JSON／show 可读，普通 list 显示人工原因和时间，go 后仍保留。旧事件不补自动通过，show 原 completion 历史作用域不变；看板中文等待项、步骤及英文等待／详情仅增加人工确认文案分支。
- 补公开契约的不可用原因和内部取舍说明、QUICKSTART 用法。通知六字段／稳定身份和自动完成判据未改。

### RED → GREEN 与验证

唯一新增测试文件为 `tests/manual-complete.py`，全部使用合成项目、独立 HOME/XDG/TMPDIR、假 corral／通知发送器。并发测试通过 socket 握手阻塞外部 Git／验收命令，所有子进程等待退出，不依赖固定睡眠。

- 主流程 RED：实现前 `show` 缺少 `manual_completion`，断言失败；实现后通过，覆盖 main 未前进、分支未合入、dirty、gate 关闭仍等待和普通 go 留存记录。
- 显示 RED：修正测试自身 set 序列化问题后，实际观察到旧看板仍说 `Checks passed`／「核对已通过」，目标断言失败；必要文案分支后通过。前一次夹具错误不算 RED。
- 发布边界 RED：模拟临时文件 fsync 期间配置被另一个写入者改动，旧实现在变化后仍退出 0；补发布前版本核对后返回 `target_changed`／退出 3，状态日志无完成事件。
- 读取边界 RED：无效 HANDOFF_DIR 含 NUL 时原实现 traceback／退出 1；补检查后返回 `configuration_unreadable`／退出 2。
- 最终 `python3 tests/manual-complete.py`：10 项通过（8.936 秒）。另覆盖跨项目／同编号新运行／配置改回原文仍过期、失败及损坏验收样本、不适用验收、Unicode 原因、历史字节保留、读取失败、原子发布失败、双方互斥和暂停／loop 放行继续路径；普通已完成历史无人工记录。
- 标准检查各一次：`bash tests/drover.sh` 通过；`bash tests/criteria.sh` 通过（损坏 ref 的中／法 locale 提示为该套件既有夹具输出）；`python3 tests/show-json.py` 16 项通过（9.598 秒）；`python3 tests/list-json.py` 通过。外层另设独立 HOME/XDG/TMPDIR 和假外部命令，均前台等待完成。
- `git diff --check`：通过。未运行整套 drover-board／PTY、录屏、植入缺陷、重复基线或预算外套件。

### 内部同步与取舍

- 交接目录 `.tasks.lock` 使用标准库 flock 非阻塞互斥。本版本 CLI 的 done／go／next／drop／hold／队列编辑／开关命令在读取决策前取得锁，直到验收、发送和写入结束；忙时退出 4。人工确认同锁复核目标后写入，查询完全不取锁。没有通用事务或审计层，不支持外部手改 tasks.state 并发；旧版已启动的 CLI 写进程不参与新锁协议。
- 人工完成在同目录临时文件中保留原事件前缀并附加一个 ASCII 转义 JSON 完成事件，fsync 后检查版本再原子替换；失败不发布完成事件。旧记录不回填，内部换行文字可恢复，Unicode 分隔符不会拆坏事件。
- 人工完成只提交这一份事件日志，不修改 loop／paused 或发送下一件；正常 go 放行人工记录时，若 loop 已开启再写既有 `.loop-wait`。这避免人工确认阶段跨两个文件半成功，并已验证暂停仍阻挡引擎、恢复后只发下一件。

### 未解决项与交付边界

本任务范围内无已知未解决项。主控审查、saddle 消费方及隔离联调尚待进行；该完成记录不代表已合并或已发布。未改主仓库、saddle、corral、全局技能、T27、真实队列／配置／通知偏好／服务；未安装、推送、合并或清理分支／worktree，未操作任何真实 agent。固定实现提交 SHA 随最终回复交付。
