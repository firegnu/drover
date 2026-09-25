# T21：队列待办详情交互设计

2026-09-25，主控 drover/main 委派给新开的 drover/dev-pending-details（名称以 corral start 返回为准），Claude Code 常规档：opus[1m] / high。只设计，方案经用户确认后再安排实现。
路由：常规 / 交叉审查不要 / 影响面：看得见（路由：tier 拿不准，cross_review 不要，impact 拿不准；模型 jev-1.13.0；主控回退：交互方案需结合现有界面取舍，定常规；只写待审阅方案、不改变运行行为，定看得见）
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 目标
看板的 Up next 现在只能看编号和标题。想在任务发出前，从看板里看到任意一件待办的正文；正文引用了任务文件的，也能看到任务单内容。

## 先读

- AGENTS.md；docs/ROADMAP.md 的「看板」及相关交互设计。
- docs/QUICKSTART.md 第 6 节；bin/drover-board 的 queue_vm、detail_sections、key_action 和 tui。
- T19 快捷键帮助页任务及届时的实现，核对入口与按键是否冲突。

## 怎么算做完
- 给一个最简单可用的方案：怎么进入、怎么选、怎么返回，附一张文字线框。
- 列出要我决定的取舍。
- 只出方案，不写代码。

## 执行与边界

- 验证仅静态核对当前交互与设计文档、执行 `git diff --check`；不跑测试套件，不做录屏、截图或可执行原型。
- worktree：`/Users/firegnu/Developer/personal_projs/drover-worktrees/m32-pending-details`；分支：`m32-pending-details`，从 main 创建。无需安装依赖；只在本文件末尾追加方案与完成记录，验证预算以上一条为准。
- 只写本任务文件；尚未确认的方案不写成 ROADMAP 已定设计，不改产品代码、测试、配置或操作手册。
- 不扩展为任务编辑、排序、搜索、批量操作或历史详情功能，不改变队列推进与完成判据。
- 不操作真实队列推进、loop、服务、安装或其他项目，不修改 corral / corral-dispatch，不推送。
- 开发 agent 不再委派，不合并 main；只在自己的分支提交设计和完成记录。主控按项目规则审查与归档；设计任务完成不代表功能已经实现，实施需用户另行确认。

命令都在前台跑完，全部做完后，回复最后一行写 DONE。
