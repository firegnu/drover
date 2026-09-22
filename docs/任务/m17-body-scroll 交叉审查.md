# T8 任务正文限高与鼠标滚动：独立 Codex 交叉审查

2026-09-22，drover/main 委派新的 drover/dev-review-body（Codex，重档 gpt-6-astra/xhigh）。用户明确要求独立交叉审查，不再调用路由。你是独立只读审查 agent，不再委派。

## 最新范围（优先于分支历史记录）

用户已确认：直接采用 corral 同类原生 curses 滚轮方案，使用已有 `/opt/anaconda3/bin/python3` 支持运行时；不继续旧 ABI 的自制鼠标协议兼容。主仓库 `b4d4c23` 已记录，取代 `00a2f6a` 和旧 R1“默认Homebrew Python必须支持”的门槛。不要重开已裁定的运行时选择，不提出自写协议、安装或换PATH。旧环境可明确提示并退化为原有整页翻页；不要将其写成局部滚动达标。

## 先读与代码

- 自己 worktree 的 AGENTS.md、README.md；主仓库 `/Users/firegnu/Developer/personal_projs/drover/docs/任务/m17-body-scroll 任务正文限高与鼠标滚动.md` 末尾最终裁定及首版完成/主控审查记录。
- 主仓库 docs/ROADMAP.md 的 T8 两节及 docs/QUICKSTART.md 的运行说明。分支文档保留调查时点，不得据此误判最新授权。
- 审查 worktree `/Users/firegnu/Developer/personal_projs/drover-worktrees/review-m17-body-scroll`，detached `885d49f`。审查生产改动 `git diff 342b6a0..885d49f` 或 `git diff main...HEAD`；实际生产实现与 `6b914a7` 相同，885d49f仅调查。代码/测试只读，不修改、不提交、不切分支。
- 原开发worktree中的自写协议实验已完整另存stash，不属于被审代码，不读取/恢复它。不要操作任何stash、真实队列、agent或项目服务。

## 已完成验证及审查方式

主控已自行重跑看板/drover两套、10项局部视口测试、支持路径8个实际PTY/208帧、默认退化8PTY、支持路径Tab8组、32个演示/270帧。T6警告/拒绝与慢go通过；当帧命中、局部滚动外部像素不变、不采集/命令、任务切换与缩放已核对。上轮默认解码8个独立样本已证实旧ABI限制，该限制由用户接受运行范围解决。

以代码及测试充分性审查为主，可跑少量有针对性的验证；禁止重复全仓库或两套全量、32演示矩阵。需要验证滚轮支持时显式用 `/opt/anaconda3/bin/python3`；使用默认python验证明确退化只能算退化验证。只用合成VM/假corral，外部临时副本可做必要缺陷自证，不能改被审代码。

## 重点（不得扩大范围）

1. 正文限高/短正文自然展开，120×32和80×24普通标题消息条件下判据可见；长标题/消息未误入正文限高，长外层内容仍可达。
2. 鼠标矩形是当帧真实可见交集，局部/完全裁切、双栏/窄屏/多项目及resize竞态不误中其它区块。
3. wheel仅改变正文内存偏移，外层/选择/VM不变，tui直接重绘不collect/view_model/业务命令；点击/拖动/移动/横向/区域外不触发操作，普通键及PgUp/PgDn不回退。
4. `(repo, card.id)`身份、同任务刷新保持、任务/项目切换归零、正文变化和缩放夹限、极小可见区不跳过内容，正文两端可达。
5. T7 Tab显示副本、中文列宽、合法Unicode、完整命令及T6消息可见性，既有断言未削弱。
6. 原生mousemask/init/退出路径足够简单，能力退化有提示且内容可达；不要求旧curses局部滚动或新增通用框架。区分合成事件、真实PTY/curses、物理设备；后者按用户任务留给用户。
7. diff范围、RED/GREEN与缺陷植入记录可信，生产/业务边界未越界。未改tests/drover.sh的首版即被审内容，不把stash中未提交试验误算进来。

分级按“正常用会不会撞上”：必须改/建议改/可以不改。只有特意构造畸形输入才触发的通常建议改或可以不改，避免把无关防御开发重新引入。

## 唯一允许写入的文件

只追加本文件 `/Users/firegnu/Developer/personal_projs/drover/docs/任务/m17-body-scroll 交叉审查.md`（在主仓库，不在审查worktree）“## 审查意见”。先结论“可以合并/改完再合并”；逐项写级别、位置、问题、证据、最小改法；对高度预算、步长、部分裁切、原生运行时/退化、真实设备交用户等取舍明确表态。说明实际跑的定向检查；不要复述整段开发日志。

不改任何其它仓库文件、不提交、不切分支、不合并、不删worktree/分支、不启动或关闭agent、不推送、不操作真实done/go/next/loop。不改corral/corral-dispatch，不读源码或内部状态；用户指定的参考已由主控完成，本审查无需再读取corral代码。禁止碰AGENTS列出的真实项目和服务；不绕过Terminal安全拒绝，T4暂缓。

完成后只回复结论、必须改/建议改条数。命令都在前台跑完，全部做完后，回复最后一行写 DONE。
