# 任务：增加 drover list --json

2026-09-25，主控 drover/main 委派给新开的 drover/dev-list-json（名称以 corral start 返回为准），Codex 常规档：gpt-6-astra / high。
路由：常规 / 交叉审查不要 / 影响面：改行为（路由：tier 常规，cross_review 不要，impact 改行为；模型 jev-1.13.0；无推翻）
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 目标

让脚本能够读取现有 `drover list` 的队列信息，无需解析面向人的中文文本。

## 范围

- `bin/drover` 的 list 命令、参数处理，以及直接相关的测试。
- 复用已有队列解析和状态折叠结果，不另写一套解析器，不改 `bin/drover-board` 的公共函数签名。

## 怎么算做完

- drover list --json 输出现有 list 的模式、暂停状态、当前任务、待放行任务、待办和最近历史。
- 保持队列顺序，正确区分未编号、进行中、已完成和放弃。
- 普通 drover list 输出保持原样。
- 只读现有数据，不改队列、不联系 agent。

## 执行安排

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/m31-list-json`；分支：`m31-list-json`，从 main 创建。
- 先读 AGENTS.md，以及 `bin/drover` 的 cmd_list、fold、pending、setup、main 和 `tests/drover.sh` 的合成 CLI 测试方式。
- 只改 `bin/drover` 的 list 命令与参数处理、直接相关测试及本文件完成记录；不改 QUICKSTART、ROADMAP、命令帮助字段说明、HANDOFF 或其他任务文件。
- 验证预算：新增一条定向测试入口 `python3 tests/list-json.py`，先确认因缺少目标行为而 RED，再实现到 GREEN；标准回归运行一次 `bash tests/drover.sh`，另做 `git diff --check`。预算不足时在回复中报告，不自行扩大。
- 只用临时合成仓库与假的 corral，不操作真实数据；不录屏、不做覆盖矩阵或缺陷注入，不跑无关套件。
- 不需要安装依赖；只用 Python 标准库。完成记录写做了什么、验证结果、取舍和未做事项。

## 边界

- 不改队列语义、完成判据、引擎、存储格式、corral 或 corral-dispatch，不重构无关 CLI 命令。
- 不操作真实队列推进、服务、安装或其他项目，不推送。
- 与 `m30-keyboard-help` 是两件独立任务，各自触发、验收和收尾；共享文档如有改动，后执行者基于最新 main 接续。
- 开发 agent 不再委派，不合并 main；只在自己的分支提交，并在本文件追加完成记录。主控依项目规则审查、本地合并和收尾。

命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 开发完成记录（2026-09-25）

- 已增加 `drover list --json`，复用现有 `fold()` / `pending()` 结果。顶层输出 `mode`（`loop` / `gate` 布尔开关）、`paused`、`current`、`awaiting`、`pending`、`history`；当前及待放行任务不存在时为 `null`。
- 待办沿用队列文件顺序，未编号的 `id` 为 `null`；当前与历史沿用折叠后的 `doing` / `done` / `dropped` 状态及已有任务字段。最近历史与普通 list 一致，取最后 10 条并倒序展示；不新增排序规则。普通 list 的文本分支保持原样。
- JSON 路径只读取已有配置、队列及状态；`setup` 在该路径跳过交接目录创建，不调用 corral。只改 `bin/drover`、新增 `tests/list-json.py` 及本完成记录。
- 定向验证：`python3 tests/list-json.py` 修改前 RED，明确因 `drover list --json` 尚不支持而返回退出码 2（普通 list 原文本断言已先通过）；修改后 GREEN。验证队列顺序、未编号/进行中/已完成/放弃、待放行任务、最近 10 条历史、普通文本，以及文件字节/修改时间/目录清单不变且假 corral 未被调用。交接目录不存在时也不会创建。
- 标准回归：仅运行一次 `bash tests/drover.sh`，退出码 0，全部通过；`git diff --check` 通过。命令均在前台等待结束，未扩大验证预算。
- 取舍及未做事项：直接输出现有解析和折叠字段，不另建解析器或改变队列语义；JSON 使用标准转义。未改看板公共签名、引擎、判据、存储、帮助字段说明或其他文档；未跑无关套件、覆盖矩阵、缺陷注入或录屏，未操作真实队列、agent、服务、安装或其他项目，未合并 main、未推送。提交留在本任务分支，交主控审查。

## 主控审查

- 通过。核对 `8b17900` 的实现、定向测试和完成记录，四条用户原话验收均落实；改动限于 list/参数处理、确保 JSON 路径只读的初始化分支、定向测试及本记录。
- 主控重跑一次 `bash tests/drover.sh`，全部通过；`git diff --check main...m31-list-json` 通过。开发侧定向 RED/GREEN 记录与测试内容一致，未另跑套件、录屏或交叉审查。
- 同意复用折叠结果、用 loop/gate 布尔值表示模式、以 null 表示无当前/待放行任务及未编号 id、沿用最近 10 条历史与标准 JSON 转义；普通文本路径保持原样，JSON 路径不创建交接目录、不调用 corral。
- 已本地合并；随后清理开发分支/worktree 与自开的 agent 并打收尾记号。未推送，未操作真实任务推进、loop、服务或安装；等待用户放行。
