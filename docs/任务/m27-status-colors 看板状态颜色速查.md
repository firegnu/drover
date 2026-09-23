# T18：补充看板状态颜色速查说明

2026-09-23，主控 drover/main 委派给 drover/dev-status-colors-1（Codex，轻档：gpt-5.6-luna / medium）。
路由：轻 / 交叉审查不要（路由：轻 1.0，交叉审查不要；无推翻）
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

1. AGENTS.md、HANDOFF.md、README.md。
2. docs/ROADMAP.md 的「生命周期状态配色」，包括同日补全。
3. bin/drover-board 的 init_colors、status_color、task_heading、detail_sections、draw，以及 docs/QUICKSTART.md 第 6 节。
4. 本文件。

## 工作目录

- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/m27-status-colors`。
- 分支：`m27-status-colors`，从 main 创建；无需安装依赖。
- 只在这个 worktree 工作；产品文档只改 `docs/QUICKSTART.md` 第 6 节，本任务文件仅追加完成记录。
- 无其他开发任务并行。不要改主仓库、HANDOFF.md、AGENTS.md、ROADMAP.md 或其他项目。

## 工作与验收

用户需要一件简单任务体验看板的进行中、agent 与待放行界面。请在看板章节补一张简短 Markdown 状态颜色速查表，对照实现与已定设计核对。

- 覆盖 Idle、Manual、Looping、loop on/off、corral 连接正常/异常、待放行、完成与明确失败；英文标签照当前界面写。
- 说明队列暂停与 loop 开关是独立状态，暂停不代表正在执行的任务或 agent 被暂停。
- 颜色描述与当前显示一致；少色/无色终端仍可根据文字和符号识别，可用一句话说明。
- 不把 loop on 当成任务正在运行，不把 Idle 当成任务完成；尚未满足判据不等于明确失败。
- 表格简短可读，不重写教程，不新增状态、命令或设计。
- 文档任务不制造 RED，不运行全套测试。人工对照源码与 ROADMAP，运行 `git diff --check` 并检查改动范围即可；不要执行教程中的实际操作命令。

## 禁止事项

- 不改代码、测试、设计、配置、服务、corral 或 corral-dispatch；不读 corral 源码和内部状态文件。
- 不操作真实队列，不运行 drover next/done/go/loop，不启用引擎，不安装，不操作 launchd。
- 不合并 main，不推送，不清理 worktree/分支，不关闭 agent，不按项目名批量杀进程。
- 不接触真实 jb-finetune、旧 herdsman 或其他项目。
- 有设计冲突就报告，不自行修改设计。

## 完成记录与回复

完成后在本文件追加「## 完成记录」：做了什么、核对命令及结果、取舍、待主控决定的问题。只在自己的分支提交 QUICKSTART 和完成记录。

命令都在前台跑完，回复给出提交 SHA、改动与核对结果，最后一行写 DONE。主控负责审查、本地合并和收尾；之后由用户放行。

## 完成记录

- 做了什么：在 `docs/QUICKSTART.md` 第 6 节增加简短的英文看板状态颜色速查表，覆盖 Idle、Manual、Looping、loop on/off、agent 进行中/空闲、corral 正常/异常、Needs you、Ready to release、完成与明确失败；补充 loop 开关与队列暂停的独立性、`Idle`/`loop on`/未满足判据的语义边界，以及少色/无色终端的文字和符号回退。
- 核对命令及结果：人工对照 `docs/ROADMAP.md` 生命周期状态配色、`bin/drover-board` 的 `init_colors`/`status_color`/`task_heading`/`detail_sections`/`draw` 与本节内容；`git diff --check` 通过；改动范围仅为本任务文件和 `docs/QUICKSTART.md`。
- 取舍：不扩展状态、不改实现、不运行教程中的实际操作命令或全套测试；将明确失败限定为带结构化失败证据的 `✗`，普通未满足判据保持灰色。
- 待主控决定的问题：无。

## 返工记录

- 按主控审查修正：将 `Idle`、`Manual`、agent `idle` 分开说明，明确 agent `idle` 只表示本轮结束/空闲，任务可能仍进行中且不代表完成；将 agent `starting` 从 `working` 中拆出，说明其为启动中，可能尚未完成启动或正在等待信任框。
- 核对：仅修改上述两处表格含义并追加本记录；未运行业务命令或全套测试，待提交前运行 `git diff --check`。
