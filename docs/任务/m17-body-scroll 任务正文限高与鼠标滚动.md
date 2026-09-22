# 任务：T8 任务描述限高，支持鼠标滚轮局部滚动

2026-09-22，drover/main 交给 drover/dev-body-scroll（Codex，重档 gpt-6-astra / xhigh）。
路由：重 / 交叉审查要（路由：tier 重，概率0.94；cross_review 不要；推翻：用户明确要求独立Codex交叉审查）
你是被委派的开发 agent：照本文件做，不要再开别的 agent。只派 Codex，不派 Claude。

## 先读

1. AGENTS.md、HANDOFF.md、README.md。T7已经用户记完成，T8已正式进入进行中；HANDOFF的旧队列描述以此与实时状态为准。
2. docs/ROADMAP.md 的看板、字符网格视觉排版、记done折进go；docs/QUICKSTART.md、docs/手册.md 的操作说明。
3. bin/drover-board 的 detail_sections/detail_lines、wrap_lines、detail_viewport、draw、key_action、tui、run_drover，以及相关 VM 契约。
4. tests/drover-board.sh、tests/board-layout.py、tests/board-demo.py、tests/board-tab-pty.py、tests/drover.sh 的既有相关检查；m16任务与交叉审查末尾R1及取舍。
5. 本任务文件。设计已定，不再另做设计，不重开T7已接受的A1–A6取舍。

## 工作区与范围

- worktree：/Users/firegnu/Developer/personal_projs/drover-worktrees/m17-body-scroll，分支 m17-body-scroll，已从 main 建好。
- 无需装依赖，只用 Python 标准库。没有并行开发任务。
- 允许修改 bin/drover-board 的显示/鼠标输入路径、tests 下直接相关回归和合成演示、docs/ROADMAP.md、本任务文件；必要时仅同步 README/QUICKSTART/手册的本次操作说明。tests/drover.sh 若因新布局需机械调整视觉期望，可以最小调整并记录理由；不能改变业务期望或削弱断言。
- 不改 bin/drover，不改采集/判据/事件/引擎/执行超时或30秒刷新契约，不改全局cell/width/trunc契约，不做其它欠账。原 VM 数据契约与共享模块调用保持兼容。
- HANDOFF由主控收尾；不要改主仓库或他人worktree。后续独立审查、合并、清理与收尾均归主控，不由你执行。

## 用户任务

目标：长任务描述不能把下面的完成依据和判据挤出首屏。给任务描述区域设置最大高度，超出后在区域内部滚动；用户明确要用鼠标滚轮或触控板，不依赖按键翻页查看正文。

交互和布局：
- 短描述按实际行数展开，不占多余空白；长描述限制高度。默认上限随终端高度调整，以24行终端最多6行正文、32行终端最多8行为基准，窄小窗口按可用空间降级，给下方信息留位置；不加配置项。
- 鼠标指针位于任务描述区域时，滚轮/触控板上下滚动只移动正文，无需先点击，不移动下面的判据、旁边的agent/待办/历史或项目选择。
- 区域显示简洁的位置提示，例如“1–6 / 38 行”，让用户知道还有内容。行数按当前列宽换行后的显示行计算，正文必须能完整滚到末尾。
- 原有PgUp/PgDn整页翻页保留，用于判据、待办等其他内容自身过长的情况；不要引入Tab焦点模式、正文折叠或无关新快捷键。描述区域以外的滚轮先不扩展新行为，不能误触发项目切换或队列操作。
- 宽屏双栏、窄屏单栏、多项目布局均支持；切换任务/项目时正文滚动归零，同任务刷新不无故跳回开头，正文变化/窗口缩放后偏移保持合法、不漏内容、不越界。

边界：
- 这是基于T7的局部滚动交互优化，不改变任务推进、判据、依据、队列事件、档位、命令调用/超时或刷新频率。所有写操作仍交给bin/drover。
- 仅Python标准库和现有curses。滚动状态只在内存中，不存文件，不增加后台采集；纯滚轮操作只重绘，不重新采集git/corral状态或执行核对。
- 保住T7的中文列宽、合法Unicode、Tab展示副本处理和完整内容可达性；保住T6放行警告、拒绝原因的可见性。长标题、操作消息、判据等不得被误归入受限正文区。
- 不改corral/corral-dispatch，不碰受保护真实项目和服务；T4继续暂缓。开发及独立交叉审查仍只用Codex。

完成标准：
- 行为改动先有效RED再GREEN：覆盖正文限高后下方信息仍可见、滚轮命中区域与边界、上下界、短正文、长正文最后一行、项目/任务切换、刷新与缩放。
- 使用合成数据和假corral。验证滚轮不调用业务命令、不重跑采集、不改VM/原文；现有键盘映射与整页翻页无回退。新增显示状态仅按需要保存在内存。
- 定向实际curses/PTY验证120×32、80×24、窄小窗口和单/多项目，核对最终屏幕而非仅中间字符串；在用户常用终端实测鼠标滚轮/触控板能否送达并且只滚正文。工具受限制时明确留给用户手动验收，不绕过、不把合成事件测试写成真实设备已验收。
- 主控写任务文件并按项目流程委派、主控审查、独立Codex交叉审查；实现取舍写ROADMAP，相关回归通过后按规矩本地合并收尾和更新HANDOFF。不推送，不操作真实done/go/next，不开启真实循环。

## 实施边界与可核对细节

- 正文是 card 的 body，不按标题文本匹配区域；用户正文即使包含“完成依据和判据”等字样，也不能被误判为界面区块。长标题/操作消息/依据/判据仍保留T7原有可达性。
- 标准120×32、80×24的首屏，普通标题/消息条件下应显示正文限高区域及其下方完成核对信息；正文很长本身不能把后者推出首屏。极小窗口不能承诺放下全部内容，采用合理退化，完整内容仍可访问。具体高度预算和滚动步长写取舍，保持简单，不加配置。
- 正文区域的鼠标命中用当帧实际绘制坐标；整页已翻动、项目栏切换、缩放、部分区域被裁切后都不能用旧坐标误中判据/侧栏。描述不在当前可见屏幕时不能隔空滚动。仅上下滚轮处理正文，点击/移动/拖动及区域外事件不触发业务操作；不做通用鼠标交互框架。
- 局部偏移与detail_offset分离。正文滚轮不改变外层偏移、项目选择或其它区域内容/坐标。只有内存显示状态可改；同任务刷新保留合法偏移，任务身份改变重置（不能只看项目repo），空任务移除区域状态，缩短且仍溢出要夹到非零末页而非总归零。
- 对实际curses鼠标能力和当前环境进行必要核对，不能假定所有常量/滚轮方向都存在。明确鼠标不支持时的行为，既有键盘/退出必须可用；若完整正文可达性与能力退化存在无法兼容的设计冲突，先报告，不偷偷增加焦点键或丢内容。
- T7的Tab→四空格仅限显示副本规则和实际最终屏幕回归必须继续成立。允许因正文改为局部视口而调整演示/测试如何访问末尾，但保留中文、NBSP/U+2028、组合字符、内部双空格、完整命令及VM不变的断言。不得靠删检查过GREEN。
- 合成演示入口应支持此次局部滚轮交互，并仍禁用真实g/n/p/a/l命令。实际设备/桌面限制已知：Computer Use已因安全限制拒绝访问Terminal，不重复尝试/不绕过；自动化验证清楚区分纯事件、真实PTY/curses与真实设备。受限部分按用户任务明确交回用户手动验收，不能声称通过，也不要据此停止可完成的实现和合成验收。

## 验证要求

1. 先写/定位自动化用例并在未实现状态跑出目标RED，记录命令/退出码/关键行；导入错误、fixture坏掉不算。最少覆盖限高后判据首屏可见，以及滚轮只改变正文视口。
2. 覆盖正文短/空/超长，24行6行与32行8行上限、宽窄/多项目、上下边界和正文最后一行。核对实际最终画面，不只断言中间行数。
3. 按坐标验证区域内部、四边界、区域外、整页翻动后的实际可见范围、缩放后重算、无当前任务。方向正确，不先点击，普通按键功能不变。
4. 真tui输入分发用假的边界/合成鼠标事件验证：计数或哨兵守住滚轮不再collect/view_model、不执行run_drover/edit_queue、不写文件；纯输入映射不得偷改输入state/VM，实际更新由tui完成。
5. 同任务刷新保留合法偏移、正文缩短但仍溢出夹到非零末页、切不同任务/等长项目重置、恢复窗口尺寸、长正文/长外层同时存在时末尾均可达。
6. 跑新增定向测试及相关看板回归（包括T7 Tab最终屏幕），必要时跑drover套件守住T6消息。无需反复跑全仓库四套；不真实安装。git diff --check、语法检查。
7. 用临时生产副本做至少两项聚焦缺陷植入，证明测试能抓住：例如让滚轮走到采集、命中区域忽略坐标、切任务不重置或覆盖Tab尾部。不得改真实项目，避免复制实现式测试。

## 禁止事项

不合并main、不推送、不打收尾记号、不删worktree/分支，不用git add -A；只在m17-body-scroll提交明确文件。
不操作真实done/go/next/loop、~/.drover真实队列或真实agent，不装依赖、不动launchctl、PATH、~/.local/bin。不处理T4。
不改corral/corral-dispatch，不读源码/内部状态；契约只读corral/docs/CONTRACT.md。
不碰真实jb-finetune、herdsman、~/.review/、~/wt/、herdr、dev.herdsman.*、~/.config/review/与老安装命令。
不得按项目名或路径批量杀进程，只停止自己启动并记下的确切PID。

## 记录与回复

在本文件末尾追加“## 完成记录”：实现范围、RED/GREEN/缺陷植入证据、测试结果、实际curses/PTY画面与重跑命令、取舍、旧断言调整清单、真实鼠标/触控板尚需用户手动验收的项目。ROADMAP记录本次批准设计和理由。
回复只写完成内容、测试/证据、取舍和需要主控决定的事项。命令都在前台跑完，全部做完后，回复最后一行写 DONE。

## 完成记录

2026-09-22，开发 agent 在 `m17-body-scroll` 完成实现和自动化验证，交主控及独立 Codex 审查。实际鼠标/触控板验收仍由用户完成。

### 实现范围与取舍

- 生产仅改 `bin/drover-board` 的 `detail_sections/draw/key_action/tui`，新增 `init_mouse`。`detail_sections` 增加可选正文展示参数，默认完整逻辑文本保持兼容；VM、原始正文、`cell/width/trunc`、采集、判据、命令调用、超时与引擎函数未改。AST 对比确认上述范围，`bin/drover` 与基线逐字相同。
- 高度为 `max(1, min(h // 4, room - 7))` 再取正文实际换行行数的较小值：24 行最多 6 行、32 行最多 8 行；短正文不填满空白。位置提示按实际展示行计数。长标题、消息和所有核对信息保持外层可达性，不归入限高正文。
- 先固定正文占位，再按当帧外层裁切结果填入正文。鼠标矩形仅含可见正文行和所在栏的横向空白，区块标题/位置提示/分隔线/其它区块不命中。正文上部或下部被裁切时，以实际可见行数夹限局部偏移，仍可仅用滚轮读到首尾。
- 每次最多滚三行，且不超过当帧可见正文行数；小窗口不会跨过未显示内容。鼠标映射不修改输入 state/VM，`tui` 单独更新 `body_offset` 并直接重绘。`detail_offset`、项目选择与正文外画面保持原位置，不触发 collect/view_model、业务命令或文件打开。
- 正文身份为 `(repo, card.id)`，等长任务/项目切换也归零；同任务刷新保留合法位置；正文缩短仍溢出时夹到非零末页，合法旧偏移不动。缩放重算行数/命中矩形；绘制后、输入前突发缩放的旧坐标事件丢弃。空任务/空正文移除正文偏移与身份，矩形清空。
- 只订阅上下滚轮，核对两个 curses 常量和 `mousemask` 返回能力；普通点击、移动、拖动、区域外滚轮均不触发业务操作。原 PgUp/PgDn、业务按键、r/KEY_RESIZE 刷新和 30 秒 getch 超时不变。
- **能力退化是实际存在的限制**：本机默认 `/opt/homebrew/opt/python@3.14/bin/python3.14` 和系统 Python 的 ncurses 6.0 均没有 `BUTTON5_PRESSED`。这种环境明确显示「滚轮不可用」，恢复完整正文的 PgUp/PgDn；因此也恢复长正文占据整页的旧布局。已安装的 `/opt/anaconda3/bin/python3` 使用 ncurses 6.4、有双向常量，本次用它验证支持路径。没有猜测按钮编码、解析自制鼠标协议或改装系统环境。能力依据已链接到 ROADMAP 的 ncurses 官方接口说明。
- 新增 `tests/board-body-scroll.py`、`tests/board-body-pty.py`，接入 `tests/drover-board.sh`；合成演示新增 `body` 场景并支持局部滚轮，g/n/p/a/l 仍只显示禁用提示。ROADMAP 与 QUICKSTART 同步操作说明。HANDOFF 留给主控。

### 有效 RED → GREEN

所有 RED 均在相应实现之前运行，错误为行为断言；导入、语法和 fixture 调整不计入 RED。

| 阶段 / 命令 | 未实现时的有效 RED | 最小实现后的 GREEN |
|---|---|---|
| `python3 -B tests/board-body-scroll.py`（最初仅首屏检查） | 退出 1，80×24 / 120×32 / 160×32 × 单/多项目六项均报「长正文把判据挤出了首屏」 | 退出 0，6/8 行上限、判据标题和收尾记号实际留在首屏，VM 不变 |
| `python3 -B tests/board-body-scroll.py BodyScroll.test_tui_wheel_only_redraws_body` | 退出 1，第二帧仍是 `BODY-01`，缺 `BODY-04`：「下滚三行必须改变正文视口」 | 下滚到 04、上滚回 01；正文/提示外所有最终字符不变；collect/view_model 各只调用一次，命令与文件哨兵未触发 |
| `python3 -B tests/board-body-scroll.py`（加入能力退化检查后） | 退出 1，仅报「能力退化必须明确提示」 | 显示滚轮不可用，PgDn 仍能找到 `BODY-38`，q 正常 |
| `python3 -B tests/board-body-scroll.py BodyScroll.test_tiny_body_scroll_does_not_skip_lines` | 退出 1，20×6 只有一行正文时固定三行步长漏掉 `BODY-02/03/...` | 步长受实际可见行数约束，38 行逐行都能出现 |
| `python3 -B tests/board-body-scroll.py BodyScroll.test_partially_clipped_body_can_reach_both_ends_by_wheel` | 退出 1：「裁去上部后仍须能从正文开头读起」 | 上裁切和下裁切两种情形均可局部滚至 01/38，外层偏移不动 |

最终 `python3 -B tests/board-body-scroll.py` **10 项通过**。还覆盖四边界、区域外、部分/完全裁切、短/空/超长正文、正文中的区块标题字样、等长项目重排、同任务刷新、仍溢出的 30→6/3→3、缩放恢复、鼠标读取错误及 resize 竞态。每次纯输入调用后立即对比 state/VM，避免上下操作相互抵消而漏掉副作用。

### 回归、实际 curses/PTY 与证据

1. `bash tests/drover-board.sh`：最终代码退出 0，日志 `/tmp/m17-board-regression.log`。既有 VM、宽度、键盘/整页视口、引擎隔离与相关 20 项检查通过，并运行布局、T7 Tab、T8 的 10 项与 8 组退化 PTY。局部裁切补强后只重跑这一相关套件；没有重复全仓库四套。
2. `bash tests/drover.sh`：退出 0，日志 `/tmp/m17-drover-regression.log`。包含真实命令在合成仓库中的 T6 g/go 警告、拒绝原因、40/80 列最终消息和慢 go 期限。**本任务没有修改 `tests/drover.sh` 或任何业务期望。**
3. `/opt/anaconda3/bin/python3 -B tests/board-body-pty.py --record /tmp/m17-body-pty`：**8 个真实 PTY 会话、208 帧**，120×32、80×24、40×10、160×32 × 单/多项目。合成 SGR 4/5 滚轮字节经 PTY → curses `getch/getmouse` → 生产 `tui`，验证方向、首屏核对信息、全 38 行、上/下界、区域外无动作、正文外字符/辅栏不动、collect/view_model 次数不变、r 保留正文、等长项目切换及真实 SIGWINCH 缩放。`.json` 保存完整最终屏幕与调用次数，`.ansi` 保存终端输出，另生成同名 `.txt` 便于逐帧复核；所有 stderr 为空。
4. `python3 -B tests/board-body-pty.py --record /tmp/m17-body-pty-fallback`：默认 Python 的 **8 个真实 PTY 会话、54 帧**，明确走能力不足分支，完整正文通过整页翻页可达，退出正常。
5. `/opt/anaconda3/bin/python3 -B tests/board-tab-pty.py`：支持滚轮的真实 curses **8 组全过**（120×32/80×24 × 有/无 Tab × 首段/36 行占位后）。默认 Python 的 8 组退化路径也在看板套件通过。完整 `python3 -m pytest tests/checkout/test_coupon_validation.py --verbose`、NBSP/U+2028、组合字符、内部双空格及原 VM 不变断言全部保留。
6. `/opt/anaconda3/bin/python3 -B tests/board-demo.py --record /tmp/m17-demo-visual`：**32 个会话、270 帧**，八类场景 × 单/多项目 × 120×32/80×24，含局部滚动、整页翻页和缩放。核对 long 场景的标题/正文/判据/路径/历史/消息末尾及最后待办实际出现在最终 curses 屏幕中，body 场景正文末尾可见，全部 stderr 为空。
7. 六个相关 Python 文件 `compile()`、`bash -n tests/drover-board.sh`、`git diff --check` 均通过。AST 对比与 `bin/drover` 字节比对守住范围。

已逐帧核对的典型画面：120×32 单项目正文 01–08 与核对信息同时可见，滚到底为 31–38、右侧 agent/待办/历史和判据仍在原位；80×24 多项目为 01–06 → 33–38，项目标签与核对信息不动；40×10 退化为一行正文，01 至 38 不漏行，其余内容仍可整页访问。

### 临时副本缺陷植入

使用 Python `TemporaryDirectory` 创建生产脚本副本，通过 `DROVER_BOARD_BIN=<副本>` 跑下列定向检查，副本先 `compile()`。每项均退出 1 且命中目标断言；末尾逐字确认工作树生产文件未变。日志在 `/tmp/m17-body-evidence/`。

| 副本中的单项缺陷 | 定向检查与结果 |
|---|---|
| 删除 tui 的 `body_scroll` 分支 `continue`，使其落入采集 | `BodyScroll.test_tui_wheel_only_redraws_body` 报「滚轮不得重跑采集」；`wheel-collect.log` |
| 坐标范围判定换为永不拒绝 | `BodyScroll.test_hit_bounds_and_paging_use_current_visible_rows` 在区域外事件期望 None 时失败；`ignore-coordinates.log` |
| 正文身份仅用 repo、忽略 card.id | `BodyScroll.test_identity_refresh_shrink_and_resize` 报「task 等长正文必须归零」；`ignore-task-id.log` |
| 每次固定滚三行 | `BodyScroll.test_tiny_body_scroll_does_not_skip_lines` 报「极小正文视口不能每次跨过未显示的行」；`fixed-three-lines.log` |
| 撤去 `wrap_lines` 展示副本的 Tab→四空格 | 用支持滚轮的解释器跑 `tests/board-tab-pty.py`，两组 120×32 Tab 正文报最终屏幕缺完整命令，六组对照通过；`tab-overwrite.log` |

### 旧断言调整清单

- `tests/board-layout.py` 的布局状态显式启用局部正文视口；遍历外层页时也遍历正文偏移。原标题/正文/判据/路径/历史/消息末尾、最后待办、Unicode、VM 和键盘断言保留；增加 body 场景后输出文案从「七类」改为「各类」。
- `tests/board-tab-pty.py` 按实际 curses 能力启用正文视口，后续内容用局部滚动访问；不支持时仍用 PgDn。原「长正文必须真的经过 PgDn」调整为「局部滚动或退化后的 PgDn」，仍要求多帧。完整命令与 Unicode 精确断言、组合矩阵、VM 不变断言未削弱。
- `tests/drover-board.sh` 仅追加两个新测试入口，旧断言未改。`tests/drover.sh` 未改。

### 用户手动验收与主控事项

**未完成真实设备验收，也未重试或绕过已被拒绝的 Terminal Computer Use。** 上述证据区分了纯合成事件、真实 PTY/curses 中的合成 SGR 输入和真实物理设备；只有前两类已完成。

用户可在常用终端、当前 worktree 前台运行以下**合成演示**，不读真实项目配置，不操作真实队列：

```sh
/opt/anaconda3/bin/python3 tests/board-demo.py --scene body
/opt/anaconda3/bin/python3 tests/board-demo.py --scene body --multi
/opt/anaconda3/bin/python3 tests/board-demo.py --scene long --multi
```

待验：鼠标无需点击即送达、触控板上下方向和连续滚动、正文外不切项目或移动其它区域、滚到末尾、PgUp/PgDn 后命中区域正确、缩放后的新坐标，以及实际字形/配色。当前默认 `python3` 只能验证已说明的降级路径；主控需明确知悉这一环境限制，不能把支持解释器下的结果写成默认启动已具备滚轮能力。

主控审查、独立 Codex 交叉审查、是否接受环境降级、合并、清理、收尾记号和 HANDOFF 由主控接手。本分支不合并、不推送、不收尾，不操作真实 done/go/next/loop。全部验证命令前台等待退出；测试自开的进程均已结束。


## 主控审查（2026-09-22，第1轮，6b914a7）

结论：支持双向滚轮的 curses 路径定向验收通过；默认启动环境未实现用户的主要目标，暂不合并。独立 Codex 交叉审查在本条处理后继续，不先重复全仓库测试。

- 状态/回复已核对：开发 agent `drover/dev-body-scroll-1` idle、attached=0，回复以 DONE 结束，分支仅新增 `6b914a7`，worktree 干净。生产变更限于显示和输入路径，bin/drover、判据、事件、引擎与命令期限未改；没有修改 tests/drover.sh。
- 主控重跑 `python3 -B tests/board-body-scroll.py` 10 项通过；默认解释器 8 组实际 PTY 验证了明确提示和完整翻页退化。`/opt/anaconda3/bin/python3 -B tests/board-body-pty.py --record /tmp/m17-main-body-pty` 8 会话/208 帧通过；该解释器的 T7 Tab/Unicode 最终屏幕 8 组通过。当帧命中、局部滚轮不动外层、不采集/不执行命令、任务身份及缩放夹限均有定向证据。
- `bash tests/drover-board.sh` 与 `bash tests/drover.sh` 均退出0，日志 `/tmp/m17-main-board-regression.log`、`/tmp/m17-main-drover-regression.log`。后者保住 T6 警告/拒绝原因和慢 go 期限。没有重复全仓库四套。
- 支持解释器的合成演示实际 curses/PTY 32 会话/270 帧通过，证据 `/tmp/m17-main-demo`。主控核对 120×32 单项目、80×24 多项目的正文首末页：判据/辅栏坐标不动；警告及拒绝原因画面可见；四组 long 场景正文、标题、判据、历史、消息末尾均可见。`git diff --check` 通过。上述是实际 PTY 中的合成输入，不能写成物理鼠标或桌面目视通过。
- 高度预算、每次至多三行并受可见高度限制、当帧矩形、仅内存状态、正文身份及既有测试调整可接受；真实设备交用户验收符合原任务授权。默认环境退回原布局这一取舍尚未获用户批准。

### R1：默认 Python 不启用正文限高及双向滚轮（必须处理的验收门槛）

`init_mouse` 在没有 `BUTTON5_PRESSED` 时返回 False，`draw` 随之取消正文限高。主控确认本机默认 Python 3.14 使用的 curses 缺该常量；默认 `python3 ./bin/drover board` 又通过 `sys.executable` 启动看板，因此不是只有测试受限：正常启动长正文仍挤走判据、仍依赖 PgUp/PgDn。不可将 Anaconda 支持路径的通过写成默认启动达标。

主控向用户询问是否接受现有 Anaconda Python 启动，用户没有批准，改为指示参考 corral 中 board 的 last reply 实现。此次明确指示只授权窄范围只读参考，不解除“不修改 corral/corral-dispatch、不读内部状态”的边界。主控只读 `corral/tools/board` 的滚轮/回复视口相关代码及对应 `tests/test_board.py` 用例：回复区独立 `reply_top`、`reply_y` 命中、按可用高度夹限；但同样将缺失的 `BUTTON5_PRESSED` 设为0，尚未发现能直接解决默认环境的兼容实现。不得改动/运行真实 corral board 或其 agent 操作。

交原开发 agent 做本条增量调查：先复核用户参考在默认 Python 中的实际 curses 解码（隔离合成 PTY，不运行 corral board）；说明缺常量到底只是 Python 暴露问题还是底层无法双向解码，并给出证据与最小可行方案。能在已批准的标准库/现有 curses 边界内修复且不改快捷键、刷新/超时、采集/业务语义时，先有效 RED 再最小修复与定向 GREEN。若必须自制终端协议解析、改解释器/依赖或改变交互/设计，先仅报告方案与代价，等主控和用户裁定，不擅自实施。不要仅去掉能力检查或猜测按钮数值来制造可用假象。

保留现有的支持/退化测试和所有断言；只增量验证 R1、双向滚轮/点击/区域外无副作用及必要键盘回归，不再重跑两套全量。真实设备仍交用户；不得绕过已拒绝的 Terminal Computer Use。完成记录与回复写清哪些是真实 PTY，哪些是合成事件。
