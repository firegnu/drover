#!/usr/bin/env bash
# drover-board 冒烟测试：造八个合成仓库，断言生成的 HTML 里队列、「等你」横幅、主控状态
# 都在，评审协议的东西一处都不剩，且不接触真实项目。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BOARD=${DROVER_BOARD_BIN:-${ROOT}/bin/drover-board}
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
OUT="${TMP}/board.html"

fail() { echo "FAIL: $*" >&2; exit 1; }
has() { grep -qF -e "$1" "${OUT}" || fail "$2 (missing: $1)"; }
lacks() { grep -qF -e "$1" "${OUT}" && fail "$2 (unexpected: $1)"; return 0; }

mk() {   # <name>：两个提交的仓库 + .drover.conf + 交接目录
  local n="$1" r; r="${TMP}/$1/repo"
  mkdir -p "$r" "${TMP}/$n/review"
  git -C "$r" init -q -b main
  git -C "$r" config user.name t; git -C "$r" config user.email t@example.com
  printf 'a\n' > "$r/a.py"; git -C "$r" add .; git -C "$r" commit -qm base
  printf 'a\nb = 1\n' > "$r/a.py"; git -C "$r" add .; git -C "$r" commit -qm change
  printf 'HANDOFF_DIR=%s\n' "${TMP}/$n/review" > "$r/.drover.conf"
}
mk alpha; mk beta; mk gamma; mk delta; mk epsilon; mk zeta; mk eta; mk theta
now=$(date +%s)

# 假 corral：只实现 send / status / ls 三个命令——drover 用到的就这三个（AGENTS.md 硬规矩）。
# alpha 的主控在 working（带 last_tool / turn_started），zeta 的 blocked，theta 的状态由文件控制。
cat > "${TMP}/corral" <<'MOCK'
#!/usr/bin/env bash
st() {   # <name> <state> [idle_for] [last_input_source]
  printf '{"ok":true,"name":"%s","instance":1,"kind":"claude","state":"%s","title":"","last_tool":"Edit","turn_started":%s,"last_input_source":"%s","idle_for":%s}\n' \
    "$1" "$2" "$(( $(date +%s) - 723 ))" "${4:-send}" "${3:-600}"
}
case "$1 $2" in
  'status alpha/main') st alpha/main working;;
  'status zeta/main')  st zeta/main blocked;;
  # eta 的主控空闲着，但判据没满足 → 它停在某处等人。三个旋钮各自试一遍。
  'status eta/main')   st eta/main "$(cat "${MOCK_DIR}/eta.state" 2>/dev/null || echo idle)" \
                          "$(cat "${MOCK_DIR}/eta.idle_for" 2>/dev/null || echo 600)" \
                          "$(cat "${MOCK_DIR}/eta.src" 2>/dev/null || echo send)";;
  'status theta/main') st theta/main "$(cat "${MOCK_DIR}/theta.status" 2>/dev/null || echo idle)";;
  'status iota/main')  st iota/main "$(cat "${MOCK_DIR}/iota.state" 2>/dev/null || echo idle)";;
  'send iota/main')    printf '%s\n' "$3" >> "${MOCK_DIR}/sent-iota"
                       printf '{"ok":true,"name":"iota/main","instance":1,"confirmed":true}\n';;
  # ls 里有三个：alpha 的主控、eta 的主控、以及 eta 派出去的那个（cwd 在 eta 的 worktree 里）
  'ls ') printf '{"ok":true,"agents":[{"name":"alpha/main","instance":1,"kind":"codex","cwd":"%s"},{"name":"eta/main","instance":1,"kind":"claude","cwd":"%s"},{"name":"eta/m1-backend","instance":2,"kind":"codex","cwd":"%s"}]}\n' \
           "${MOCK_ALPHA}" "${MOCK_ETA}" "${MOCK_ETA_WT}";;
  'status eta/m1-backend') st eta/m1-backend working;;
  'send theta/main') printf '%s\n' "$3" >> "${MOCK_DIR}/prompts.log"
                     printf '{"ok":true,"name":"theta/main","instance":1,"confirmed":true}\n';;
  *) printf '{"ok":false,"error":"not_found"}\n'; exit 2;;
esac
MOCK
chmod +x "${TMP}/corral"
# eta 派出去的那个 agent 跑在一个 worktree 里（corral-dispatch 就是这么干的）：
# corral ls 给的 cwd 是 worktree 路径，不是仓库根，看板要用 git worktree list 映射回来
git -C "${TMP}/eta/repo" worktree add -q -b m1-backend "${TMP}/eta/wt-m1" >/dev/null 2>&1
# 里程碑分支上有提交、还没合回 main —— 判据第 2 条应当不过
printf 'wip\n' >> "${TMP}/eta/wt-m1/a.py"
git -C "${TMP}/eta/wt-m1" add a.py; git -C "${TMP}/eta/wt-m1" commit -qm 'm1 wip'
printf 'BRANCH_GLOB=m[0-9]*\nCHECK_CMD=pytest -q\n' >> "${TMP}/eta/repo/.drover.conf"
export MOCK_ALPHA="${TMP}/alpha/repo" MOCK_ETA="${TMP}/eta/repo" MOCK_ETA_WT="${TMP}/eta/wt-m1" MOCK_DIR="${TMP}"
export DROVER_CORRAL_BIN="${TMP}/corral"
# 谁的 MAIN_AGENT 配了什么：看板按名字问 corral status
printf 'MAIN_AGENT=alpha/main\n' >> "${TMP}/alpha/repo/.drover.conf"
printf 'MAIN_AGENT=zeta/main\n'  >> "${TMP}/zeta/repo/.drover.conf"
printf 'MAIN_AGENT=eta/main\n'   >> "${TMP}/eta/repo/.drover.conf"
printf 'MAIN_AGENT=theta/main\n' >> "${TMP}/theta/repo/.drover.conf"
# zeta：主控卡在审批对话框（假 corral 里 blocked）→「等你」里出现一条 STOP

# 任务区 —— eta：T8 进行中（1 个提交）；队列里一个手写未编号的排在最前；
# 已完成 T5（没有提交）、放弃 T6。theta：T3 做完、放行模式下还没放行，并且暂停中。其余项目没有 queue.md，不出现任务区。
E="${TMP}/eta"; EB=$(git -C "$E/repo" rev-parse HEAD~1); EH=$(git -C "$E/repo" rev-parse HEAD); ES=$(git -C "$E/repo" rev-parse --short HEAD)
printf '## T8 把 CSV 导入改成流式\n约束：内存不超过 200MB\n\n## 修一下登录页的超时\n\n## T9 订单列表分页\n只动分页参数\n### 范围\n- 别碰 <b>旧接口</b> & 文档\n' > "$E/review/queue.md"
{ printf '{"t": %s, "ev": "start", "id": "T5", "title": "给导出加进度条", "body": "", "key": "给导出加进度条", "sha": "%s"}\n' "$((now - 9000))" "$EB"
  printf '{"t": %s, "ev": "done", "id": "T5", "sha": "%s", "gate": false}\n' "$((now - 7800))" "$EB"
  printf '{"t": %s, "ev": "start", "id": "T7", "title": "实验脚本换参数", "body": "", "key": "实验脚本换参数", "sha": "%s"}\n' "$((now - 7790))" "$EB"
  printf '{"t": %s, "ev": "done", "id": "T7", "sha": "%s", "gate": false}\n' "$((now - 7750))" "$EH"
  printf '{"t": %s, "ev": "drop", "id": "T6", "title": "迁移到新日志库", "key": "迁移到新日志库", "reason": "和 T2 冲突"}\n' "$((now - 7700))"
  printf '{"t": %s, "ev": "start", "id": "T8", "title": "把 CSV 导入改成流式", "body": "约束：内存不超过 200MB", "key": "把 CSV 导入改成流式", "sha": "%s", "main": "%s"}\n' "$((now - 3600))" "$EB" "$EH"
} > "$E/review/tasks.state"
TH="${TMP}/theta"; THB=$(git -C "$TH/repo" rev-parse HEAD~1)
printf '## T3 补登录接口的回归测试\n\n## T4 清理旧的 feature flag\n' > "$TH/review/queue.md"
{ printf '{"t": %s, "ev": "start", "id": "T3", "title": "补登录接口的回归测试（带\\"引号\\"）", "body": "", "key": "补登录接口的回归测试（带\\"引号\\"）", "sha": "%s"}\n' "$((now - 2000))" "$THB"
  printf '{"t": %s, "ev": "done", "id": "T3", "sha": "%s", "gate": true}\n' "$((now - 100))" "$THB"
} > "$TH/review/tasks.state"
: > "$TH/review/paused"

printf '%s/alpha/repo\n%s/beta/repo\n%s/gamma/repo\n%s/delta/repo\n%s/epsilon/repo\n%s/zeta/repo\n%s/eta/repo\n%s/theta/repo\n# comment\n%s/nonexistent\n' "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" > "${TMP}/projects"
python3 "${BOARD}" --projects "${TMP}/projects" --out "${OUT}" >/dev/null

# 项目发现与去重命名（三个 checkout 都叫 repo，用上级目录区分）
for n in alpha beta gamma delta epsilon zeta eta theta; do has "data-p=\"$n/repo\"" "project $n listed"; done
has '项目 · 8' 'project count'
has '<div class="mast"><span class="brand">Review board</span>' 'masthead'
has '<b>主控</b> claude' 'masthead names the kind corral status reports'

# 活动条：全部来自 corral status 的结构化字段（state / last_tool / turn_started）。
# 老的做法是跑 herdr agent read、再从输出里正则抠「Working (12m 03s · esc to interrupt)」那句话；
# corral 契约明写 read「只作排查用，不要解析」，所以那段整个删了，换成这两个字段。
has '<span class="dot st-working"></span><b>写手</b><span class="st st-working">working</span><span class="activity">正在调 Edit · 这一轮 12m</span>' 'alpha 主控 chip shows the tool and the turn length'
# 按钮的样式名是 act、默认隐藏；agent 正在做什么的那段文字不能用同一个名字，否则被一起藏掉
lacks '<span class="act">' 'crew activity text is not styled as a hidden button'

# 「等人」的识别：eta 的主控空闲着，但 T8 的判据没满足（main 还停在发任务那一刻）
# —— 它停在某处等人拍板。判据第 1、2 条是纯 git，渲染时照算；第 3 条可能是整套测试，不在这里跑。
has '主控空闲着，但这件活的判据还没满足' 'an idle 主控 with unmet criteria is flagged as waiting on you'
has 'T8' 'the 等人 item names the task'
has '送任务之后没有前进' 'it says which criterion is unmet'

# 横幅：zeta blocked 一条 + eta 等人一条 + theta 做完等放行一条
has '等你 · 3' 'banner count: zeta 1 + eta 1 + theta 1'
seen_plain=0
for c in $(grep -o 'class="proj[^"]*" data-p' "${OUT}" | sed 's/class="proj needs" data-p/needs/;s/class="proj" data-p/plain/'); do
  if [ "$c" = plain ]; then seen_plain=1; elif [ "${seen_plain}" = 1 ]; then fail 'a project that needs you sorted after a quiet one'; fi
done

# 「等人」不许误报。三种情况都不算停下等人，契约和 ROADMAP 各写了一半：
#   a) last_input_source 是 agent —— 这一轮是主控自己开的（后台命令跑完自注入），不是在等人
#   b) idle 的时间还不够 —— 每一轮结束都会短暂 idle，得留一次观察间隔再下结论
#   c) state 是 unknown —— 不认识的 agent 没有钩子，状态无从得知，那就不猜
regen() { python3 "${BOARD}" --projects "${TMP}/projects" --out "${OUT}" >/dev/null; }
for probe in 'eta.src agent' 'eta.idle_for 5' 'eta.state unknown'; do
  set -- ${probe}; printf '%s\n' "$2" > "${TMP}/$1"; regen
  lacks '主控空闲着，但这件活的判据还没满足' "no 等人 item when $1 is $2"
  rm -f "${TMP}/$1"
done
# 主控在干活时当然不算等人
printf 'working\n' > "${TMP}/eta.state"; regen
lacks '主控空闲着，但这件活的判据还没满足' 'no 等人 item while the 主控 is working'
rm -f "${TMP}/eta.state"; regen

# ---- 「当前这件活」块（ROADMAP 第 4 步的新页面结构）----
# 分支进展：从发任务那一刻的 main 算起多了几个提交、最后一次多久前。
# eta 正是卡住的样子：0 个提交落地——这和「等人」那条说的是同一件事，从两个角度看。
has 'class="prog"' 'the current-work card has a branch-progress line'
has 'main</code> 上 <b>0</b> 个提交' 'branch progress counts commits on main since the task went out'
has '还没有提交落地' 'a stuck task shows nothing landed yet'
# 完成判据过了几条：前两条实时算（纯 git），第 3 条只写出命令、标明没在页面上跑
has 'class="crit"' 'the card shows how many criteria are met'
has '判据 0/2' 'eta: neither cheap criterion is met yet'
has '没在页面上跑' 'the check command is named but not run while rendering'
# 派出去的 agent：corral ls 里 cwd 落在这个仓库的 worktree 上的，都算这件活派出去的
has '<b>派出去</b>' 'dispatched agents get their own chips'
has 'eta/m1-backend' 'the dispatched agent is named'

# 评审协议的东西一律不该再出现
lacks 'Round 1' 'no review rounds'
lacks '暂缓清单' 'no backlog section'
lacks '最近归档' 'no archive section'
lacks '等你裁决' 'no pending decisions'
lacks 'request-review' 'no request-review anywhere on the page'   # 老 herdsman 的命令，页面上不该再提

# 「等你」栏：每个项目一栏，横幅只是汇总
has 'id="w-zeta/repo"' 'zeta has its own 等你 section'
has '主控停在审批或提问对话框：去看看：corral attach zeta/main' 'blocked 主控 listed with how to attach'
# 每条「等你」都带接入命令。drover 自己不跑 attach——只用 send / status / ls，这只是给人抄的一句话。
has 'corral attach eta/main' 'the 等人 item also says how to attach'
has 'class="proj needs" data-p="zeta/repo"' 'zeta highlighted in the sidebar'

# 任务区：只有接了队列的项目才有；三栏、阶段条、手写未编号、放弃带原因、做完等放行
[ "$(grep -o 'class="tasks"' "${OUT}" | wc -l | tr -d ' ')" = 2 ] || fail 'task section only on projects with a queue'
has '<span class="next">下一个</span>' 'next marker on the first pending task'
has '修一下登录页的超时' 'hand-written task listed'
has '<span class="hand">手写 · 发出时编号</span>' 'unnumbered task marked'
has '<span class="tid">T9</span>订单列表分页' 'numbered pending task listed with its ID'
has '<span class="tid">T8</span>把 CSV 导入改成流式' 'in-progress card title'
has '<li class="now">实施<span class="x">1 个提交</span></li>' 'implementation step counts commits since start'
has '<span class="tid">T5</span><span class="t">给导出加进度条</span><span class="r">20m</span>' 'finished row with duration'
has 'class="drow dropped"' 'dropped row struck through'
has '和 T2 冲突' 'drop reason shown'
has '<span class="mode gate">放行模式</span>' 'release-mode chip'
has '<span class="mode paused">暂停中</span>' 'paused chip replaces the mode chip'
has 'T3 补登录接口的回归测试（带&quot;引号&quot;） 做完了' 'awaiting release listed as waiting on you, title escaped'
has 'drover go' 'the waiting item says how to release'
has '下一件会自动送进主控' 'the waiting item says what happens after release'
has '<span class="badge me">等你放行</span>' 'awaiting release badge'
has 'class="card s-me"' 'finished card turns crimson while it waits'
has '<li class="now release">收尾<span class="x">核对通过 · 等你放行</span></li>' 'last step waits for release'

# 任务区是独立的框；队列和已完成两栏各自滚动；点任务在右侧抽屉看全文 —— 全文嵌在页面里、已转义，未开始的读 queue.md，开始过的读发出时的快照
has '<section class="tasks">' 'task board is its own section'
[ "$(grep -o 'class="lb"' "${OUT}" | wc -l | tr -d ' ')" = 4 ] || fail 'queue and finished lanes scroll on their own (2 per board)'
[ "$(grep -o '<aside class="drawer"' "${OUT}" | wc -l | tr -d ' ')" = 1 ] || fail 'one shared task drawer'
has 'data-td="eta/repo:T9"' 'pending task opens its description'
has 'data-td="eta/repo:q1"' 'unnumbered pending task opens its description by position'
has 'data-td="eta/repo:T8"' 'in-progress card opens its description'
has 'data-td="eta/repo:T6"' 'dropped task opens its description'
has '<template id="td-eta/repo:T9">' 'pending task description embedded'
has 'queue.md 当前内容' 'pending description says it is the live queue text'
has '<div class="dp">约束：内存不超过 200MB</div>' 'started task description comes from the snapshot'
has '发出时的快照' 'started description says it is the snapshot the writer got'
has '<div class="dh4">范围</div>' 'subheadings rendered in the description'
has '<div class="dli">别碰 &lt;b&gt;旧接口&lt;/b&gt; &amp; 文档</div>' 'list lines rendered and escaped'
lacks '<b>旧接口</b>' 'task text is never injected as markup'
has '和 T2 冲突' 'dropped description carries the reason'
# 自动刷新只恢复滚动位置，不再按地址栏里的锚点跳走
has '!st.auto' 'anchor jump skipped on auto refresh'
lacks 'class="flow' 'no flow chips anywhere'

# 没有队列的项目不画任务区，面板里只剩标题和状态
python3 - "${OUT}" <<'PY2' || fail 'projects without a queue render an empty panel'
import sys
page = open(sys.argv[1], encoding="utf-8").read()
def panel(name):
    i = page.index(f'<div class="panel" data-p="{name}"'); j = page.find('<div class="panel" data-p=', i + 1)
    return page[i:j if j > 0 else None]
for name in ("alpha/repo", "beta/repo"):
    assert '<section class="tasks">' not in panel(name), name
assert '<section class="tasks">' in panel("eta/repo")
PY2
# 静态看板顶栏提示带按钮的版本在哪（本机服务的地址）；服务页不需要
has '<a class="golive" href="http://127.0.0.1:10086/">' 'the static board points to the live board'

# 不接触真实项目
lacks 'jb-finetune' 'real project leaked into fixture board'
lacks '~/Developer' 'default discovery used'

# 默认输出路径：--out 未给时写到 ~/.drover/board.html —— 不在测试里跑，避免碰真实目录

# ---- 项目发现只认 ~/.drover/projects，不扫目录 ----
# 上面所有调用都带 --projects，默认发现路径一次也没走到。这里把 HOME 指到临时目录，
# 在老 glob（~/Developer/personal_projs/*/.drover.conf）会命中的位置埋一个仓库，
# 断言它不会自己冒出来——「放对目录就自动接进看板」正是当初够到真 jb-finetune 的那条路。
DH="${TMP}/dhome"
mkdir -p "${DH}/.drover" "${DH}/Developer/personal_projs/sneaky"
printf 'HANDOFF_DIR=%s\n' "${TMP}/alpha/review" > "${DH}/Developer/personal_projs/sneaky/.drover.conf"
printf '%s/alpha/repo\n' "${TMP}" > "${DH}/.drover/projects"
HOME="${DH}" python3 - "${BOARD}" <<'PY2' || fail 'discovery reads only ~/.drover/projects'
import importlib.machinery, importlib.util, os, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
assert B.PROJ_LIST == os.path.expanduser("~/.drover/projects"), B.PROJ_LIST
found = B.discover(None)                                        # None = 走默认发现
assert len(found) == 1 and found[0].endswith("/alpha/repo"), found
assert not any("sneaky" in r for r in found), found             # 埋在老 glob 位置的那个不该出现
assert not hasattr(B, "PROJ_GLOB"), "PROJ_GLOB 还在：目录扫描没删干净"
PY2
echo 'PASS drover-board renders the queue, the banner and 主控 status; no review protocol left'
echo 'PASS drover-board discovery: only ~/.drover/projects, never a directory scan'

# 并发刷新：launchd 的定时生成和人手动跑的会撞在一起。临时文件共用一个名字时，后到的那个改名会扑空
# （老 herdsman 的 board.err 里 2026-09-11 有 3 次）。先用一个被占住的 board.html.tmp 把「共用固定名字」
# 确定地暴露出来，再真并发跑几次。
mkdir "${OUT}.tmp"
python3 "${BOARD}" --projects "${TMP}/projects" --out "${OUT}" >/dev/null 2>"${TMP}/board.err" \
  || fail "board writes through a shared fixed temp name: $(tail -1 "${TMP}/board.err")"
rmdir "${OUT}.tmp"
pids=""
for i in 1 2 3 4; do
  python3 "${BOARD}" --projects "${TMP}/projects" --out "${OUT}" >/dev/null 2>>"${TMP}/board.err" &
  pids="${pids} $!"
done
for p in ${pids}; do wait "$p" || fail "a concurrent board run failed: $(tail -1 "${TMP}/board.err")"; done
ls "${OUT}".*tmp >/dev/null 2>&1 && fail 'board left a temp file behind'
has 'Review board' 'page still written after concurrent runs'
echo 'PASS concurrent board runs never collide on the temp file'

# 「等你」通知：只有带 --notify（launchd 那次刷新）才发；一个项目新出现的条目合成一条；没变化不重发；
# 条目消失后再出现会重发；AppleScript 字符串要转义；通知发不出去也不能把看板弄崩。用假的通知命令，不真弹。
cat > "${TMP}/notifier" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${TMP}/notify.log"
EOF
chmod +x "${TMP}/notifier"
board() { DROVER_NOTIFY_BIN="$1" python3 "${BOARD}" --projects "${TMP}/projects" --out "${OUT}" "${@:2}" >/dev/null; }
nlines() { if [ -f "${TMP}/notify.log" ]; then wc -l < "${TMP}/notify.log" | tr -d ' '; else echo 0; fi; }
board "${TMP}/notifier"
[ "$(nlines)" = 0 ] || fail 'the board must not notify without --notify'
board "${TMP}/notifier" --notify
[ "$(nlines)" = 3 ] || fail "first --notify run: one per project waiting on you (zeta blocked, eta 等人, theta awaiting release), got $(nlines)"
grep -q 'zeta/repo' "${TMP}/notify.log" || fail 'the blocked 主控 is notified'
grep -q '做完了' "${TMP}/notify.log" || fail 'waiting for release is notified'
board "${TMP}/notifier" --notify
[ "$(nlines)" = 3 ] || fail 'an unchanged board must not notify again'
mv "${TMP}/theta/review/tasks.state" "${TMP}/theta/state.bak"
board "${TMP}/notifier" --notify
[ "$(nlines)" = 3 ] || fail 'an item going away sends nothing'
mv "${TMP}/theta/state.bak" "${TMP}/theta/review/tasks.state"
board "${TMP}/notifier" --notify
[ "$(nlines)" = 4 ] || fail 'an item that comes back is notified again'
tail -1 "${TMP}/notify.log" | grep -q '做完了' || fail 'the renewed notification carries the item text'
tail -1 "${TMP}/notify.log" | grep -qF '\"引号\"' || fail 'double quotes are escaped for AppleScript'
rm -f "${TMP}/board-notified.json"
board "${TMP}/no-such-notifier" --notify || fail 'a missing notifier must not break the board'
has 'Review board' 'page still written when notifications cannot be sent'
echo 'PASS 等你 notifications: only with --notify, once per project, again when an item returns, escaped, never fatal'

# ---- 本机服务：drover-board serve。页面带令牌和按钮；放行、放弃转给 drover；只认本机 Host / Origin 和令牌 ----
lacks '<meta name="rb-token"' 'the static board carries no token'
lacks 'data-act=' 'the static board carries no action buttons'
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
python3 "${BOARD}" serve --projects "${TMP}/projects" --port "${PORT}" > /dev/null 2> "${TMP}/serve.err" &
SERVE=$!
trap 'kill "${SERVE}" 2>/dev/null; rm -rf "${TMP}"' EXIT
U="http://127.0.0.1:${PORT}"
for _ in $(seq 50); do curl -s -o /dev/null "${U}/v" && break; sleep 0.1; done
curl -s "${U}/" > "${TMP}/live.html" || { cat "${TMP}/serve.err"; fail 'serve answers GET /'; }
TOKEN=$(sed -n 's/.*<meta name="rb-token" content="\([^"]*\)".*/\1/p' "${TMP}/live.html")
[ -n "${TOKEN}" ] || fail 'served page embeds the token'
grep -qF 'data-act="go" data-p="theta/repo" data-id="T3"' "${TMP}/live.html" || fail 'release button on the card waiting for release'
grep -qF 'data-act="drop" data-p="eta/repo" data-id="T9"' "${TMP}/live.html" || fail 'drop button on a numbered pending task'
grep -qF 'data-act="drop" data-p="eta/repo" data-id="T8"' "${TMP}/live.html" && fail 'no drop button on the task in progress'
grep -q '"v"' <(curl -s "${U}/v") || fail 'GET /v returns a version'
# 页面脚本嵌在 Python 字符串里，转义写错会让整页脚本失效（刷新、抽屉、按钮全停）；有 node 就查一遍语法
if command -v node >/dev/null; then
  python3 -c 'import re,sys; print(re.search(r"<script>(.*)</script>", open(sys.argv[1], encoding="utf-8").read(), re.S).group(1))' "${TMP}/live.html" > "${TMP}/page.js"
  node --check "${TMP}/page.js" 2> "${TMP}/js.err" || { cat "${TMP}/js.err"; fail 'the page script parses'; }
fi
post() {   # <path> <json> [extra curl args…] → HTTP 状态码；响应体在 ${TMP}/resp
  curl -s -o "${TMP}/resp" -w '%{http_code}' -X POST -H 'Content-Type: application/json' "${@:3}" --data "$2" "${U}$1"
}
[ "$(post /api/go '{"project":"theta/repo"}')" = 403 ] || fail 'POST without the token is refused'
[ "$(post /api/go '{"project":"theta/repo"}' -H "X-RB-Token: wrong")" = 403 ] || fail 'POST with a wrong token is refused'
[ "$(post /api/go '{"project":"theta/repo"}' -H "X-RB-Token: ${TOKEN}" -H "Origin: http://evil.example")" = 403 ] || fail 'POST from another origin is refused'
[ "$(post /api/go '{"project":"theta/repo"}' -H "X-RB-Token: ${TOKEN}" -H "Host: evil.example:${PORT}")" = 403 ] || fail 'a foreign Host header is refused'
[ "$(post /api/go '{"project":"nope/repo"}' -H "X-RB-Token: ${TOKEN}")" = 404 ] || fail 'unknown project'
V1=$(curl -s "${U}/v")
ES=$(wc -l < "${TMP}/eta/review/tasks.state")
[ "$(post /api/drop '{"project":"eta/repo","id":"T8","reason":"x"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'the task in progress cannot be dropped from the page'
[ "$(wc -l < "${TMP}/eta/review/tasks.state")" = "${ES}" ] || fail 'a refused drop writes nothing'
[ "$(post /api/drop '{"project":"eta/repo","id":"T9","reason":"不需要了"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'drop a pending task'; }
grep -q '"ok": true' "${TMP}/resp" || fail 'drop reports ok'
tail -1 "${TMP}/eta/review/tasks.state" | grep -q '"ev": "drop", "id": "T9".*不需要了' || fail 'drop goes through drover with the reason'
[ "$(post /api/go '{"project":"eta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'go refused when nothing waits for release'
[ "$(post /api/go '{"project":"theta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'release the finished task'; }
tail -1 "${TMP}/theta/review/tasks.state" | grep -q '"ev": "go", "id": "T3"' || fail 'go goes through drover'
grep -q 'drover next' "${TMP}/resp" || fail 'go passes on how the next one gets sent'
[ "$(curl -s "${U}/v")" != "${V1}" ] || fail 'the version changes after the queue state changes'
echo 'PASS drover-board serve: token, local Host/Origin only, release and drop via drover, in-progress task not droppable'

# ---- 页面上加任务：标题 + 流程 + 正文，经 drover add 追加到队列末尾；顶格 ## 会被当成新任务，拒绝
grep -qF 'data-act="add" data-p="eta/repo"' "${TMP}/live.html" || fail 'add-task button on a board with a queue'
lacks 'data-act="add"' 'the static board has no add button'
EQ=$(cat "${TMP}/eta/review/queue.md")
[ "$(post /api/add '{"project":"eta/repo","title":"","body":"x"}' -H "X-RB-Token: ${TOKEN}")" = 400 ] || fail 'an empty title is refused'
[ "$(post /api/add '{"project":"eta/repo","title":"两行\n标题","body":""}' -H "X-RB-Token: ${TOKEN}")" = 400 ] || fail 'a multi-line title is refused'
[ "$(post /api/add '{"project":"eta/repo","title":"坏正文","body":"第一行\n## 这会变成新任务"}' -H "X-RB-Token: ${TOKEN}")" = 400 ] || fail 'a body line starting with ## is refused'
grep -q '###' "${TMP}/resp" || fail 'the refusal says to use ### instead'
# 「验收：」那行会被当成 shell 命令跑（判据第 3 条）：网页表单里不收，不让一个输入框变成任意命令执行
[ "$(post /api/add '{"project":"eta/repo","title":"想塞命令","body":"验收：touch /tmp/pwned"}' -H "X-RB-Token: ${TOKEN}")" = 400 ] || fail 'a 验收 line is refused from the web form'
grep -q 'queue.md' "${TMP}/resp" || fail 'the refusal says to edit queue.md instead'
[ "$(post /api/edit '{"project":"eta/repo","pos":1,"title":"想塞命令","body":"验收: rm -rf /"}' -H "X-RB-Token: ${TOKEN}")" = 400 ] || fail 'a 验收 line is refused from edit too'
[ "$(cat "${TMP}/eta/review/queue.md")" = "${EQ}" ] || fail 'refused adds leave queue.md untouched'
[ "$(post /api/add '{"project":"eta/repo","title":"导出支持按月分文件","body":"### 范围\n- 只动导出\n\n怎么算做完：测试通过"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'add a task from the page'; }
grep -q '"ok": true' "${TMP}/resp" && grep -q 'T10' "${TMP}/resp" || fail 'add reports the new ID'
python3 - "${TMP}/eta/review/queue.md" <<'PY2' || fail 'the new block is appended with its body'
import sys; q = open(sys.argv[1], encoding="utf-8").read()
tail = q[q.index("## T10 导出支持按月分文件"):]
assert tail == "## T10 导出支持按月分文件\n### 范围\n- 只动导出\n\n怎么算做完：测试通过\n", repr(tail)
PY2
case "$(cat "${TMP}/eta/review/queue.md")" in "${EQ}"*) ;; *) fail 'existing queue text is kept as is';; esac
[ "$(post /api/add '{"project":"eta/repo","title":"普通任务","body":""}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || fail 'a task with no body'
tail -1 "${TMP}/eta/review/queue.md" | grep -qx '## T11 普通任务' || fail 'a task with no body is a single line'
echo 'PASS drover-board serve: add a task from the page via drover add; bad titles and ## body lines refused'

# ---- 页面上调整顺序、修改还没开始的任务：带着页面生成时 queue.md 的指纹，对不上（队列被别人改过）就拒绝
curl -s "${U}/" > "${TMP}/live.html"
QV=$({ grep -o 'data-p="eta/repo" data-qv="[0-9a-f]*"' "${TMP}/live.html" || true; } | sed 's/.*data-qv="\([0-9a-f]*\)"/\1/')
[ -n "${QV}" ] || fail 'the live task board carries the queue fingerprint'
grep -qF 'data-act="edit" data-p="eta/repo" data-pos="1"' "${TMP}/live.html" || fail 'edit button on pending tasks, unnumbered ones too'
grep -qF 'data-act="down" data-p="eta/repo" data-pos="1"' "${TMP}/live.html" || fail 'move-down button on the first pending task'
grep -qF 'data-act="up" data-p="eta/repo" data-pos="1"' "${TMP}/live.html" && fail 'no move-up button on the first pending task'
grep -qF 'draggable="true" data-pos="3"' "${TMP}/live.html" || fail 'pending tasks can be dragged'
epending() { python3 - "${BOARD}" "${TMP}/eta/review" <<'PY2'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1]); B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
d = sys.argv[2]
print("|".join(b["title"] for b in B.task_pending(B.task_blocks(B.read(d + "/queue.md")), B.task_fold(B.task_events(B.read(d + "/tasks.state")))[0])))
PY2
}
[ "$(epending)" = "修一下登录页的超时|导出支持按月分文件|普通任务" ] || fail "eta pending before moving: $(epending)"
[ "$(post /api/move '{"project":"eta/repo","from":3,"to":1,"expect":"000000000000"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'a stale fingerprint refuses the move'
grep -q '刷新' "${TMP}/resp" || fail 'the conflict says to refresh'
[ "$(post /api/move '{"project":"eta/repo","from":3,"to":1,"expect":"'"${QV}"'"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'move a pending task from the page'; }
[ "$(epending)" = "普通任务|修一下登录页的超时|导出支持按月分文件" ] || fail "moved to the front: $(epending)"
[ "$(post /api/move '{"project":"eta/repo","from":1,"to":2,"expect":"'"${QV}"'"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'the old fingerprint no longer matches after a change'
QV=$(python3 -c 'import hashlib,sys; print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest()[:12])' "${TMP}/eta/review/queue.md")
[ "$(post /api/edit '{"project":"eta/repo","pos":2,"title":"修一下登录页的超时（改）","body":"## 坏","expect":"'"${QV}"'"}' -H "X-RB-Token: ${TOKEN}")" = 400 ] || fail 'edit refuses a ## body line'
[ "$(post /api/edit '{"project":"eta/repo","pos":2,"title":"修一下登录页的超时（改）","body":"### 范围\n- 只改超时","expect":"'"${QV}"'"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'edit a pending task from the page'; }
grep -qx '## 修一下登录页的超时（改）' "${TMP}/eta/review/queue.md" || fail 'edited title written, still unnumbered'
python3 - "${TMP}/eta/review/queue.md" <<'PY2' || fail 'edited block carries its new body'
import sys; q = open(sys.argv[1], encoding="utf-8").read()
i = q.index("## 修一下登录页的超时（改）"); j = q.find("\n## ", i + 1)
assert q[i:j].strip() == "## 修一下登录页的超时（改）\n### 范围\n- 只改超时", repr(q[i:j])
PY2
echo 'PASS drover-board serve: reorder and edit pending tasks via drover move / edit, guarded by the queue fingerprint'

# ---- 页面上暂停 / 恢复发新任务：标题栏按当前状态给「暂停发任务」或「恢复发任务」，经 drover pause / resume
grep -qF 'data-act="pause" data-p="eta/repo"' "${TMP}/live.html" || fail 'pause button on a board that is not paused'
grep -qF 'data-act="resume" data-p="theta/repo"' "${TMP}/live.html" || fail 'resume button on a paused board'
grep -qF 'data-act="resume" data-p="eta/repo"' "${TMP}/live.html" && fail 'no resume button on a board that is not paused'
[ "$(post /api/pause '{"project":"eta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'pause from the page'; }
[ -f "${TMP}/eta/review/paused" ] || fail 'pause goes through drover pause'
[ "$(post /api/pause '{"project":"eta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'pause refused when already paused (the page was stale)'
[ "$(post /api/resume '{"project":"theta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'resume from the page'; }
[ ! -f "${TMP}/theta/review/paused" ] || fail 'resume goes through drover resume'
[ "$(post /api/resume '{"project":"theta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'resume refused when not paused'
rm -f "${TMP}/eta/review/paused"
echo 'PASS drover-board serve: pause / resume from the page via drover, refused when the page was stale'

# ---- 页面上放弃没编号的任务：放弃按钮带队列位置，和调整顺序一样带着指纹
curl -s "${U}/" > "${TMP}/live.html"
[ "$(epending)" = "普通任务|修一下登录页的超时（改）|导出支持按月分文件" ] || fail "eta pending before dropping by position: $(epending)"
grep -qF 'data-act="drop" data-p="eta/repo" data-id="" data-pos="2"' "${TMP}/live.html" || fail 'drop button on an unnumbered pending task'
QV=$(python3 -c 'import hashlib,sys; print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest()[:12])' "${TMP}/eta/review/queue.md")
[ "$(post /api/drop '{"project":"eta/repo","pos":2,"reason":"不做了","expect":"000000000000"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'a stale fingerprint refuses the drop'
[ "$(post /api/drop '{"project":"eta/repo","pos":2,"reason":"不做了","expect":"'"${QV}"'"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'drop an unnumbered task from the page'; }
[ "$(epending)" = "普通任务|导出支持按月分文件" ] || fail "dropped by position: $(epending)"
tail -1 "${TMP}/eta/review/tasks.state" | grep -q '"key": "修一下登录页的超时（改）".*不做了' || fail 'the page drop goes through drover drop --pos'
echo 'PASS drover-board serve: drop unnumbered pending tasks from the page by position, guarded by the queue fingerprint'

# ---- 已完成列表「查看全部」：栏底入口（只在本机服务），点开时 GET /history 取全部做完 / 放弃的任务，最新的在前
curl -s "${U}/" > "${TMP}/live.html"
grep -qF 'data-act="history" data-p="eta/repo"' "${TMP}/live.html" || fail 'view-all entry under the finished lane'
[ "$(curl -s -o /dev/null -w '%{http_code}' "${U}/history?project=nope/repo")" = 404 ] || fail 'history of an unknown project'
[ "$(curl -s -o /dev/null -w '%{http_code}' -H "Host: evil.example:${PORT}" "${U}/history?project=eta/repo")" = 403 ] || fail 'history refuses a foreign Host'
curl -s "${U}/history?project=eta%2Frepo" > "${TMP}/history.json"
python3 - "${TMP}/history.json" <<'PY2' || { cat "${TMP}/history.json"; fail 'history lists every finished and dropped task, newest first, with a summary'; }
import json, sys
h = json.load(open(sys.argv[1], encoding="utf-8"))
items = h["items"]; ids = [i["id"] for i in items]
assert "T8" not in ids, ids                                     # 进行中的不算
assert {"T5", "T6", "T7", "T9"} <= set(ids), ids
assert [i["t1"] for i in items] == sorted((i["t1"] for i in items), reverse=True)
by = {i["id"]: i for i in items}
assert by["T5"]["status"] == "done" and by["T5"]["span"] == "20m", by["T5"]
assert by["T6"]["status"] == "dropped" and by["T6"]["reason"] == "和 T2 冲突"
assert by["T7"]["status"] == "done" and by["T7"]["range"], by["T7"]
assert by["T9"]["status"] == "dropped" and "只动分页参数" in by["T9"]["body"], by["T9"]   # 没发出过：正文取 queue.md 里的原文
assert by["T9"]["source"].startswith("queue.md")
sm = h["summary"]
assert sm["done"] == 2 and sm["dropped"] == len(items) - 2 and sm["avg"], sm
PY2
echo 'PASS drover-board serve: view all finished tasks via GET /history (newest first, summary, queue text for never-started drops)'

# ---- 做完停：只在循环开着（或自动模式）时出现；按钮经 drover hold 记进 tasks.state；任务上标「做完停」；关了循环就不显示
curl -s "${U}/" > "${TMP}/live.html"
grep -qF 'data-act="hold" data-p="eta/repo"' "${TMP}/live.html" && fail 'no hold toggle while every task already waits for release'
[ "$(post /api/loop '{"project":"eta/repo","on":true}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'loop on for eta'; }
curl -s "${U}/" > "${TMP}/live.html"
grep -qF 'data-act="hold" data-p="eta/repo" data-pos="1" data-on="0"' "${TMP}/live.html" || fail 'hold toggle on pending tasks while looping'
QV=$(python3 -c 'import hashlib,sys; print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest()[:12])' "${TMP}/eta/review/queue.md")
[ "$(post /api/hold '{"project":"eta/repo","pos":1,"on":true,"expect":"000000000000"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'a stale fingerprint refuses the hold'
[ "$(post /api/hold '{"project":"eta/repo","pos":1,"on":true,"expect":"'"${QV}"'"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'hold from the page'; }
tail -1 "${TMP}/eta/review/tasks.state" | grep -q '"ev": "hold".*"on": true' || fail 'the page hold goes through drover hold'
curl -s "${U}/" > "${TMP}/live.html"
grep -qF '<span class="hold-tag">做完停</span>' "${TMP}/live.html" || fail 'a held task is marked on the board'
grep -qF 'data-act="hold" data-p="eta/repo" data-pos="1" data-on="1"' "${TMP}/live.html" || fail 'the toggle shows it is on'
[ "$(post /api/hold '{"project":"eta/repo","pos":1,"on":false,"expect":"'"${QV}"'"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || fail 'unhold from the page'
[ "$(post /api/loop '{"project":"eta/repo","on":false}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || fail 'loop off for eta'
echo 'PASS drover-board serve: hold toggle only while looping, via drover hold, marked on the board, guarded by the fingerprint'

# ---- 服务健康：/health 汇报本机服务（代码是否比服务新）、launchd 托管、看板定时生成、出错记录、corral；页面顶栏有状态圆点
grep -qF 'class="hp"' "${TMP}/live.html" || fail 'the live masthead has the health pill'
lacks 'class="hp"' 'the static board has no health pill'
grep -qF 'class="golive"' "${TMP}/live.html" && fail 'the live board does not link to itself'
# 常驻服务要每次都用当前时间算「几分钟前」：模块里的 NOW 若停在启动那刻，页面上的时长会越来越偏
python3 - "${BOARD}" "${TMP}/projects" <<'PY2' || fail 'collect refreshes NOW for every page'
import importlib.machinery, importlib.util, os, sys, time
sys.dont_write_bytecode = True
os.environ["DROVER_CORRAL_BIN"] = "/nonexistent"
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1]); B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
B.NOW = 0
B.collect(sys.argv[2])
assert abs(B.NOW - time.time()) < 60, B.NOW
PY2
# 同理，corral 的 agent 列表每页重查：常驻服务里缓存一次，主控的状态就永远停在服务启动那刻
python3 - "${BOARD}" "${TMP}/projects" <<'PY2' || fail 'collect re-reads corral agents for every page'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1]); B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
B._AGENTS = []                                                  # 假装上一页时 corral 什么都没有
alpha = next(p for p in B.collect(sys.argv[2]) if p["name"] == "alpha/repo")
assert (alpha["agents"].get("writer") or {}).get("status") == "working", alpha["agents"]
PY2
mkdir -p "${TMP}/home/.drover" "${TMP}/hbin" "${TMP}/code"
cp "${BOARD}" "${TMP}/code/drover-board"; cp "$(dirname "${BOARD}")/drover" "${TMP}/code/drover"
cat > "${TMP}/hbin/launchctl" <<EOF
#!/usr/bin/env bash
case "\$2" in
  */dev.drover.board-serve) [ -f "${TMP}/serve.unloaded" ] && exit 113
    pid=\$PPID; [ -f "${TMP}/serve.other" ] && pid=1
    printf '\tstate = running\n\tpid = %s\n\tlast exit code = 0\n' "\$pid";;
  */dev.drover.board) code=0; [ -f "${TMP}/board.never" ] && code='(never exited)'
    printf '\tstate = not running\n\tlast exit code = %s\n' "\$code";;
  *) exit 113;;
esac
EOF
cat > "${TMP}/hbin/corral" <<EOF
#!/usr/bin/env bash
[ -f "${TMP}/corral.down" ] && exit 1
exec "${TMP}/corral" "\$@"
EOF
chmod +x "${TMP}/hbin/launchctl" "${TMP}/hbin/corral"
printf '[]\n' > "${TMP}/home/.drover/board-notified.json"
HP=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
HOME="${TMP}/home" DROVER_LAUNCHCTL="${TMP}/hbin/launchctl" DROVER_LOOP_TICK=1 \
  DROVER_CORRAL_BIN="${TMP}/hbin/corral" \
  python3 "${TMP}/code/drover-board" serve --projects "${TMP}/projects" --port "${HP}" > /dev/null 2> "${TMP}/serve2.err" &
SERVE2=$!
trap 'kill "${SERVE}" "${SERVE2}" 2>/dev/null; rm -rf "${TMP}"' EXIT
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:${HP}/v" && break; sleep 0.1; done
health() {   # <期望的 level> <检查项名> <true|false> [detail 里应有的字]
  curl -s "http://127.0.0.1:${HP}/health" > "${TMP}/health.json" || { cat "${TMP}/serve2.err"; fail 'GET /health'; }
  python3 - "${TMP}/health.json" "$@" <<'PY2' || { cat "${TMP}/health.json"; fail "health: $*"; }
import json, sys
h = json.load(open(sys.argv[1], encoding="utf-8")); level, name, ok = sys.argv[2:5]; want = sys.argv[5] if len(sys.argv) > 5 else ""
names = [i["name"] for i in h["items"]]
assert names == ["本机服务", "服务守护（launchd）", "看板定时生成", "生成出错记录", "corral"], names
it = next(i for i in h["items"] if i["name"] == name)
assert h["level"] == level and it["ok"] == (ok == "true") and want in it["detail"], (h["level"], it)
PY2
}
health ok 本机服务 true '端口'
health ok 看板定时生成 true '通知正常'
: > "${TMP}/board.never"; health ok 看板定时生成 true '通知正常'; rm "${TMP}/board.never"
printf 'Traceback: boom\n' > "${TMP}/home/.drover/board.err"
health warn 生成出错记录 false 'boom'
python3 -c 'import os,sys,time; t=time.time()-3600; os.utime(sys.argv[1], (t, t))' "${TMP}/home/.drover/board.err"
health ok 生成出错记录 true '上次出错'
python3 -c 'import os,sys,time; t=time.time()-900; os.utime(sys.argv[1], (t, t))' "${TMP}/home/.drover/board-notified.json"
health warn 看板定时生成 false '通知可能停了'
printf '[]\n' > "${TMP}/home/.drover/board-notified.json"
: > "${TMP}/corral.down"; health warn corral false '连不上'; rm "${TMP}/corral.down"
: > "${TMP}/serve.unloaded"; health warn '服务守护（launchd）' false '不会自动拉起'; rm "${TMP}/serve.unloaded"
: > "${TMP}/serve.other"; health warn '服务守护（launchd）' false '另一个进程'; rm "${TMP}/serve.other"
health ok '服务守护（launchd）' true '已由 launchd 托管'
grep -qF "document.body.classList.contains('offline')" "${TMP}/live.html" || fail 'no full-page refresh while the service is unreachable'
python3 -c 'import os,sys,time; t=time.time()+5; os.utime(sys.argv[1], (t, t))' "${TMP}/code/drover"
health warn 本机服务 false '旧代码'
# ---- agent 状态随轮询更新：GET /crew 返回各项目的 agent 状态块，页面每 8 秒换上，不用等整页刷新
grep -qF 'data-crew="alpha/repo"' "${TMP}/live.html" || fail 'the live page has a crew slot per project'
curl -s "http://127.0.0.1:${HP}/crew" > "${TMP}/crew.json"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); assert "st-working" in c["alpha/repo"] and "正在调 Edit" in c["alpha/repo"], c' "${TMP}/crew.json" || { cat "${TMP}/crew.json"; fail 'crew shows the working 主控'; }
: > "${TMP}/corral.down"; sleep 3
curl -s "http://127.0.0.1:${HP}/crew" > "${TMP}/crew.json"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); assert "st-working" not in c["alpha/repo"], c' "${TMP}/crew.json" || { cat "${TMP}/crew.json"; fail 'crew follows corral without a page reload'; }
rm "${TMP}/corral.down"
echo 'PASS drover-board serve: /health reports stale code, launchd, board refresh, recent errors and corral; NOW and agents refreshed; crew polled'

# ---- 外层循环：页面开关；服务看到 .loop-wait 且条件满足（有待办、没暂停、不等放行）就跑一次
# drover next，由它把**任务正文**送进主控。老 herdsman 是往写手 pane 里注入固定那句
# 「运行 drover next」——内依赖外，已经删掉；pane 身份核对那一整套也跟着没了。
curl -s "http://127.0.0.1:${HP}/" > "${TMP}/live2.html"
TOKEN2=$(sed -n 's/.*<meta name="rb-token" content="\([^"]*\)".*/\1/p' "${TMP}/live2.html")
grep -qF 'data-act="loop" data-p="theta/repo" data-on="0"' "${TMP}/live2.html" || fail 'loop switch (off) on the task board'
lpost() { curl -s -o "${TMP}/resp" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "X-RB-Token: ${TOKEN2}" --data "$2" "http://127.0.0.1:${HP}$1"; }
[ "$(lpost /api/loop '{"project":"theta/repo","on":true}')" = 200 ] || { cat "${TMP}/resp"; fail 'turn the loop on from the page'; }
[ -f "${TMP}/theta/review/loop" ] || fail 'the page switch goes through drover loop on'
[ "$(lpost /api/loop '{"project":"theta/repo","on":true}')" = 409 ] || fail 'loop on refused when already on'
mark() { printf '{"reason": "empty", "t": %s}\n' "$(date +%s)" > "${TMP}/theta/review/.loop-wait"; }
waitfor() { for _ in $(seq 40); do eval "$1" && return 0; sleep 0.25; done; return 1; }
[ "$(lpost /api/go '{"project":"theta/repo"}')" = 200 ] || true     # T3 还等着放行，先放掉
rm -f "${TMP}/prompts.log"; mark
waitfor '[ -s "${TMP}/prompts.log" ]' || { cat "${TMP}/serve2.err"; cat "${TMP}/theta/review/.loop.log" 2>/dev/null; fail 'the loop sends the next task when one is pending'; }
# 送出去的是任务正文本身，不是「运行 drover …」那种指令
grep -q 'T4' "${TMP}/prompts.log" || { cat "${TMP}/prompts.log"; fail 'the sent text is the task itself'; }
grep -q 'drover' "${TMP}/prompts.log" && { cat "${TMP}/prompts.log"; fail 'the sent text must never tell the agent to run drover'; }
waitfor '[ ! -f "${TMP}/theta/review/.loop-wait" ]' || fail 'the marker is cleared once the task went out'
# 暂停中：不发
[ "$(lpost /api/pause '{"project":"theta/repo","on":true}')" = 200 ] || true
rm -f "${TMP}/prompts.log"; mark; sleep 2.5
[ ! -s "${TMP}/prompts.log" ] || fail 'nothing is sent while paused'
[ "$(lpost /api/pause '{"project":"theta/repo","on":false}')" = 200 ] || true
# 循环关：标记作废，不发
[ "$(lpost /api/loop '{"project":"theta/repo","on":false}')" = 200 ] || fail 'turn the loop off from the page'
rm -f "${TMP}/prompts.log"; mark; sleep 2.5
[ ! -s "${TMP}/prompts.log" ] || fail 'nothing is sent with the loop off'
rm -f "${TMP}/theta/review/.loop-wait"
echo 'PASS drover-board serve: loop switch; sends the next task itself, not while paused, not with the loop off'

# ---- 外层循环闭合：主控空闲下来、且 main 上出现收尾记号时，循环引擎核对三条门，过了就记 done 并发下一件。
# 直接调 loop_tick，不等常驻服务，省得看时序。
IO="${TMP}/iota"; mkdir -p "${IO}/repo" "${IO}/review"
git -C "${IO}/repo" init -q -b main
git -C "${IO}/repo" config user.name t; git -C "${IO}/repo" config user.email t@example.com
printf 'a\n' > "${IO}/repo/a.py"; git -C "${IO}/repo" add .; git -C "${IO}/repo" commit -qm base
IOB=$(git -C "${IO}/repo" rev-parse main)
# 验收命令留下痕迹，好断言「主控在忙时一次都没跑过」
printf 'HANDOFF_DIR=%s\nMAIN_AGENT=iota/main\nTASK_GATE=0\nCHECK_CMD=echo ran >> %s/check.log\n' \
  "${IO}/review" "${TMP}" > "${IO}/repo/.drover.conf"
printf '## T1 头一件\n\n## T2 第二件\n' > "${IO}/review/queue.md"
printf '{"t": %s, "ev": "start", "id": "T1", "title": "头一件", "body": "", "key": "头一件", "sha": "%s", "main": "%s"}\n' \
  "$((now - 600))" "$IOB" "$IOB" > "${IO}/review/tasks.state"
: > "${IO}/review/loop"
printf '%s/iota/repo\n' "${TMP}" > "${TMP}/projects-iota"
tick() { python3 - "${BOARD}" "${TMP}/projects-iota" <<'PY2'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
B.loop_tick(sys.argv[2])
PY2
}
done_ev() { grep -c '"ev": "done", "id": "T1"' "${IO}/review/tasks.state" 2>/dev/null | head -1; }

# 主控在忙：一次都不许核对——第 3 条可能是整套测试，不能因为它在干活就反复跑
printf 'working\n' > "${TMP}/iota.state"; rm -f "${TMP}/check.log"; tick
[ ! -f "${TMP}/check.log" ] || { cat "${TMP}/check.log"; fail 'must not run the check command while the 主控 is working'; }
[ "$(done_ev)" = 0 ] || fail 'nothing is marked done while the 主控 is working'
# 主控空闲了，但 main 还没前进（门第 1 条不过，也还没有收尾记号）：核对了，但不标做完
printf 'idle\n' > "${TMP}/iota.state"; tick
[ "$(done_ev)" = 0 ] || fail 'a task whose criteria are unmet must not be marked done'
# main 前进了，三条门都过了，但主控还没打收尾记号 → 依据不成立 → 绝不自动记 done。
# 这条挡的正是最弱的默认配置：没配 BRANCH_GLOB / CHECK_CMD 时，门只剩「main 前进了」，
# 主控提一行注释就能骗过去。见 ROADMAP 完成判据那一节。
printf 'b\n' >> "${IO}/repo/a.py"; git -C "${IO}/repo" add .; git -C "${IO}/repo" commit -qm work
rm -f "${TMP}/iota.checked" "${IO}/review/.criteria-checked"
tick
[ "$(done_ev)" = 0 ] || fail 'the gates alone must never close a task: no wrap-up mark, no done'
# 打上收尾记号 → 依据成立 → 自动记 done，并且（自动模式）把下一件送出去
git -C "${IO}/repo" commit -q --allow-empty -m '收尾: 头一件做完了'
rm -f "${TMP}/iota.checked" "${IO}/review/.criteria-checked"     # 清掉节流记录，立刻再查一次
: > "${TMP}/sent-iota"; tick
[ "$(done_ev)" = 1 ] || { cat "${IO}/review/.loop.log" 2>/dev/null || true; fail 'the loop closes the task itself once the criteria are met'; }
grep -q '"ev": "start", "id": "T2"' "${IO}/review/tasks.state" || fail 'and the next task goes out right after'
# 节流：刚查过就再来一跳，不许再跑一次验收命令
N=$(wc -l < "${TMP}/check.log"); tick
[ "$(wc -l < "${TMP}/check.log")" = "$N" ] || fail 'the check command is throttled, not run on every tick'
echo 'PASS loop engine: checks the criteria only when the 主控 is idle, closes the task itself, throttled'

# ---- 浏览器冒烟：真开一个无头 Chrome 点一遍（抽屉、编辑框预览、放弃确认、查看全部、↓ 调整顺序、断开变红）。
# 放在最后：它最后会停掉 ${SERVE}。没有 node 或 Chrome 就跳过，不算失败。
if command -v node >/dev/null; then
  # 给冒烟测试准备一个「做完等放行」的任务：theta 领 T4、提交一笔（判据第 1 条要 main 前进）、做完
  rm -f "${TMP}/theta/review/loop" "${TMP}/theta/review/.loop-wait" "${TMP}/theta/review/paused"
  ( cd "${TMP}/theta/repo" && python3 "$(dirname "${BOARD}")/drover" next >/dev/null \
    && printf 'flag\n' >> a.py && git add a.py && git commit -qm 'T4 work' \
    && python3 "$(dirname "${BOARD}")/drover" done T4 >/dev/null ) || true
  grep -q '"ev": "done", "id": "T4".*"gate": true' "${TMP}/theta/review/tasks.state" || fail 'smoke setup: theta T4 waits for release'
  set +e; node "${ROOT}/tests/browser-smoke.mjs" "${U}/" "${SERVE}"; SMOKE=$?; set -e
  if [ "${SMOKE}" = 77 ]; then :
  elif [ "${SMOKE}" != 0 ]; then fail 'browser smoke test'
  else
    [ "$(epending)" = "普通任务|导出支持按月分文件" ] || fail "the page's actions reached queue.md: $(epending)"
    tail -1 "${TMP}/theta/review/tasks.state" | grep -q '"ev": "go"' || fail "the page's release reached tasks.state"
  fi
else
  echo 'SKIP browser smoke: no node'
fi
