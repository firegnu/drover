# T7 / m16-kanban-ui 独立交叉审查

2026-09-22，drover/main 交给 drover/dev-review-ui（新 Codex，重档 gpt-6-astra / xhigh）。
路由：重 / 交叉审查要（用户明确要求独立 Codex；按 corral-dispatch 重档审查）
你是被委派的独立审查 agent，不再委派。

## 背景与先读

开发 agent drover/dev-kanban-ui-1 在 m16-kanban-ui 完成 4cc7a91，主控已审查关键显示路径、测试 diff、AST 范围；主控看板与 drover 两套回归全过，重录 28 个真实 PTY 会话并检查长内容末尾可达。不是功能扩展，只优化 curses 显示。

先读 AGENTS.md，以及主仓库任务文件 /Users/firegnu/Developer/personal_projs/drover/docs/任务/m16-kanban-ui 字符网格视觉优化.md（含主控审查、验收限制），再读本文件和被审 diff。ROADMAP 只读本次 TUI 相关小节。设计参考 /Users/firegnu/Desktop/字符网格方案交付/grids.js 和 Drover 看板设计方案.dc.html；已批准任务边界优先。

## 工作区与写权限

- 你自己的 detached worktree：/Users/firegnu/Developer/personal_projs/drover-worktrees/review-m16-kanban-ui，固定提交 4cc7a91。
- 被审 diff：git diff e6cd857..4cc7a91；只读，不改代码、不提交、不切分支、不改开发 worktree。
- **唯一允许写的仓库文件就是本文件**：/Users/firegnu/Developer/personal_projs/drover/docs/任务/m16-kanban-ui 交叉审查.md。它在主仓库，不在你的 worktree；只追加意见。
- 可在 /tmp 创建独立合成数据、定向探针及证据；用假 corral，必要时测试基于临时副本。不要运行真实队列或 agent，不向 corral 发话。
- 主控已验证两套、开发四套已全过，不要重复全仓库审查/四套测试。运行 python3 tests/board-layout.py，按新发现做定向复现；确有证据需要时运行相关套件一次。不可为了多跑而跑。

## 重点审查（7 条）

1. 业务边界：只显示层；不改变任务状态、完成判据、依据、队列事件、档位、刷新频率、命令调用/超时、输入映射。共享数据模块的既有调用是否仍正确。
2. 双栏与窄屏：120×32 单项目约 70:45、120 多项目有效宽度降级单栏、80×24 单栏/项目标签；所有尺寸的顶部、消息、按键、滚动提示不遮正文，不崩溃/不越界。
3. 可达性：实际 draw + key_action 翻页，完整标题/指标、正文、长失败原因、agent 路径、全部待办与原有历史范围、消息均能看到；两栏长短交换、条目超过一页、窄小窗口也无永久漏行。
4. 视口：切项目重置、同项目内容变化只夹限、合法偏移保留、窗口大小/双栏切换后上下翻页正确；VM 不变，仅允许内存显示状态。
5. T6 消息：g 输出优先级和超时不变；缺收尾警告、拒绝原因、已放行/未放行仍可见，长消息全部可读；不要新增核对运行状态。
6. Unicode/样式：列宽、组合字符、NBSP/U+2028 合法名称不被空白折叠改写；界限处不会截丢内容。颜色之外保留文字/符号，无色/小终端可用。
7. 测试证据质量：旧断言只是为新布局更新，没有删除或弱化内容/安全断言；tests/drover.sh 的唯一两行历史断言是否等价。合成场景是否掩盖真实 VM 边界。不要把真实 PTY 文本当作已完成桌面字体/配色验收。

## 主控待验收项（勿擅自关闭）

- 桌面 Terminal 的读取被 Computer Use 安全限制拒绝；主控未绕过。真实 PTY 排版已验证，桌面字体/配色目视尚待补齐或用户明确调整要求。审查可给“代码可以合并，视觉门槛仍待补齐”，但不能宣称全任务验收通过。
- 开发记录称用户授权修改 tests/drover.sh 一条视觉断言，主控已询问用户核实，待答复。技术等价性照常审，不把该声称当已验证事实。

## 禁止事项

不合并、不推送、不做收尾、不改 HANDOFF、不操作真实 done/go/next/loop、不启停真实 agent。不安装、不改 PATH/launchd/~/.local/bin。不碰真实 jb-finetune、herdsman、~/.review、~/wt、herdr、dev.herdsman.*、~/.config/review。不能读 corral 源码或内部状态，契约仅看其 docs/CONTRACT.md。不要按项目名/路径批量杀进程；只清自己临时启动的确切 PID。

## 输出

在本文件末尾追加“## 审查意见”：一句代码结论（可以合并 / 改完再合并）；每条写必须改/建议改/可以不改、位置、可复现证据、影响、最小改法；逐条评议开发取舍，并列验证命令/结果与仍缺的视觉验收。已接受设计不得重新争论。
回复只写代码结论、各级条数及未完成验收项。命令都在前台跑完，全部做完后，回复最后一行写 DONE。
