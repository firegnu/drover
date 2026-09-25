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
