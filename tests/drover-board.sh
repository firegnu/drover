#!/usr/bin/env bash
# drover-board 冒烟测试：造八个合成仓库，断言看板算出来的东西对 —— 队列、「等你」、
# 当前这件活、完成判据，评审协议的东西一处不剩，且不接触真实项目。
#
# **断言全打在 view_model() 返回的纯数据上，不 grep 画面。** 换个排版、换个配色不会挂；
# 画那一层（draw）薄到只补一条「画进很窄的假屏幕不崩、不越界」的冒烟就够。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BOARD=${DROVER_BOARD_BIN:-${ROOT}/bin/drover-board}
DROVER="$(dirname "${BOARD}")/drover"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
VM="${TMP}/vm.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
has() { grep -qF -e "$1" "${VM}" || fail "$2 (missing: $1)"; }
lacks() { grep -qF -e "$1" "${VM}" && fail "$2 (unexpected: $1)"; return 0; }

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
# eta 派出去的那个 agent 跑在一个 worktree 里（corral-dispatch 就是这么干的）。
# 看板以前会把 corral ls 报的 cwd 顺着 git worktree list 映射回项目，现在不了；这个 worktree
# 留着是给判据第 2 条用的（里程碑分支有提交、还没合回 main）
git -C "${TMP}/eta/repo" worktree add -q -b m1-backend "${TMP}/eta/wt-m1" >/dev/null 2>&1
# 里程碑分支上有提交、还没合回 main —— 判据第 2 条应当不过
printf 'wip\n' >> "${TMP}/eta/wt-m1/a.py"
git -C "${TMP}/eta/wt-m1" add a.py; git -C "${TMP}/eta/wt-m1" commit -qm 'm1 wip'
printf 'BRANCH_GLOB=m[0-9]*\nCHECK_CMD=pytest -q\n' >> "${TMP}/eta/repo/.drover.conf"
export MOCK_ALPHA="${TMP}/alpha/repo" MOCK_ETA="${TMP}/eta/repo" MOCK_ETA_WT="${TMP}/eta/wt-m1" MOCK_DIR="${TMP}"
export DROVER_CORRAL_BIN="${TMP}/corral"
# 引擎每跳都会发「等你」通知：记录写 ~/.drover/board-notified.json、命令默认是 osascript。
# 两样都得关进临时目录，不然测试会写到真的家目录、真的弹通知。所有 drover loop 的调用都带上。
NH="${TMP}/nhome"; mkdir -p "${NH}/.drover"
cat > "${TMP}/notifier" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${TMP}/notify.log"
EOF
chmod +x "${TMP}/notifier"
loop() { HOME="${NH}" DROVER_NOTIFY_BIN="${1:-${TMP}/notifier}" python3 "${DROVER}" loop "${@:2}"; }
# 谁的 MAIN_AGENT 配了什么：看板按名字问 corral status
printf 'MAIN_AGENT=alpha/main\n' >> "${TMP}/alpha/repo/.drover.conf"
printf 'MAIN_AGENT=zeta/main\n'  >> "${TMP}/zeta/repo/.drover.conf"
printf 'MAIN_AGENT=eta/main\n'   >> "${TMP}/eta/repo/.drover.conf"
printf 'MAIN_AGENT=theta/main\n' >> "${TMP}/theta/repo/.drover.conf"
# zeta 的主控在假 corral 里是 blocked。以前这会在「等你」里挂一条 STOP，现在不会了——
# 「主控卡在对话框」这条删了，corral 的 board 本来就把 blocked 显在最显眼处。zeta 留着当对照：
# 主控 blocked 但队列没事的项目，drover 这边一条「等你」都不该有。

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

# ============================================================ view_model：看板要显示的一切
vm() {   # 重跑一遍 collect + view_model，结果落成 JSON。「刷新等于重跑」，看板不存自己的状态
  python3 - "${BOARD}" "${TMP}/projects" "${VM}" <<'PY2' || fail 'view_model() 跑不起来'
import importlib.machinery, importlib.util, json, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
json.dump(B.view_model(B.collect(sys.argv[2])), open(sys.argv[3], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
PY2
}
q() {   # <python 表达式> → 求值打印。vm 是整份字典，p("名字") 取一个项目
  # eval 的表达式全是本文件里写死的断言，不是外来输入
  python3 - "${VM}" "$1" <<'PY2'
import json, sys
vm = json.load(open(sys.argv[1], encoding="utf-8"))
p = lambda n: next(x for x in vm["projects"] if x["name"] == n)
print(eval(sys.argv[2]))
PY2
}
is() {   # <表达式> <期望> <说明>
  local got
  got=$(q "$1") || fail "$3 (表达式报错：$1)"
  [ "${got}" = "$2" ] || fail "$3 (want: $2 · got: ${got})"
}

vm

# 项目发现与去重命名（八个 checkout 都叫 repo，用上级目录区分）
is 'len(vm["projects"])' 8 'eight projects'
for n in alpha beta gamma delta epsilon zeta eta theta; do
  is "any(x['name'] == '$n/repo' for x in vm['projects'])" True "project $n listed"
done

# 顶栏的健康提示：数据源只剩 corral（launchd / 静态页 / 本机服务那几项随 HTML 层一起删了）
is 'vm["health"]["ok"]' True 'health is green while corral answers'
is '"corral" in vm["health"]["text"]' True 'the health line names corral'

# 「等人」的识别：eta 的主控空闲着，但 T8 的判据没满足（main 还停在发任务那一刻）
# —— 它停在某处等人拍板。判据第 1、2 条是纯 git，刷新时照算；第 3 条可能是整套测试，不在这里跑。
is 'len(p("eta/repo")["waits"])' 1 'an idle 主控 with unmet criteria is flagged as waiting on you'
has '主控空闲着，但这件活的判据还没满足' 'the 等人 item says why'
is '"T8" in p("eta/repo")["waits"][0]' True 'the 等人 item names the task'
is '"送任务之后没有前进" in p("eta/repo")["waits"][0]' True 'it says which criterion is unmet'
# 每条「等你」都带接入命令。drover 自己不跑 attach——只用 send / status / ls，这只是给人抄的一句话。
is '"corral attach eta/main" in p("eta/repo")["waits"][0]' True 'the 等人 item also says how to attach'

# 跨项目汇总：eta 等人一条 + theta 做完等放行一条（zeta 的主控 blocked 不再算一条）
is 'len(vm["waits"])' 2 'summary count: eta 1 + theta 1'
is 'any(w["project"] == "zeta/repo" for w in vm["waits"])' False 'a blocked 主控 alone must not raise 等你: that is corral board的活'
is '[x["needs_me"] for x in vm["projects"]] == sorted([x["needs_me"] for x in vm["projects"]], reverse=True)' True \
   'projects that need you sort first'

# 「等人」不许误报。三种情况都不算停下等人，契约和 ROADMAP 各写了一半：
#   a) last_input_source 是 agent —— 这一轮是主控自己开的（后台命令跑完自注入），不是在等人
#   b) idle 的时间还不够 —— 每一轮结束都会短暂 idle，得留一次观察间隔再下结论
#   c) state 是 unknown —— 不认识的 agent 没有钩子，状态无从得知，那就不猜
for probe in 'eta.src agent' 'eta.idle_for 5' 'eta.state unknown'; do
  set -- ${probe}; printf '%s\n' "$2" > "${TMP}/$1"; vm
  is 'p("eta/repo")["waits"]' '[]' "no 等人 item when $1 is $2"
  rm -f "${TMP}/$1"
done
# 主控在干活时当然不算等人
printf 'working\n' > "${TMP}/eta.state"; vm
is 'p("eta/repo")["waits"]' '[]' 'no 等人 item while the 主控 is working'
rm -f "${TMP}/eta.state"; vm

# ---- 「当前这件活」块 ----
# 分支进展：从发任务那一刻的 main 算起多了几个提交、最后一次多久前。
# eta 正是卡住的样子：0 个提交落地——这和「等人」那条说的是同一件事，从两个角度看。
is 'p("eta/repo")["queue"]["card"]["id"]' T8 'the current-work card is the task in progress'
is 'p("eta/repo")["queue"]["card"]["title"]' '把 CSV 导入改成流式' 'and carries its title'
is 'p("eta/repo")["queue"]["card"]["on_main"]' 0 'branch progress counts commits on main since the task went out'
is '"还没有提交落地" in p("eta/repo")["queue"]["card"]["progress"]' True 'a stuck task shows nothing landed yet'
is 'p("eta/repo")["queue"]["card"]["commits"]' 1 'the card counts commits since the task started'
# 完成判据：收尾记号排最前（它是依据，三条是门），前两条实时算（纯 git），第 3 条只写出命令、不跑
is 'p("eta/repo")["queue"]["card"]["criteria"][0]["name"]' 收尾记号 'the wrap-up mark comes first: it is the 依据'
is 'p("eta/repo")["queue"]["card"]["criteria"][0]["ok"]' False 'eta has no wrap-up mark yet'
is 'p("eta/repo")["queue"]["card"]["met"]' 0/3 'eta: nothing met yet (wrap-up mark + the two cheap gates)'
is 'p("eta/repo")["queue"]["card"]["criteria"][3]["ok"]' None 'the check command is never run while refreshing'
is '"pytest -q" in p("eta/repo")["queue"]["card"]["criteria"][3]["why"]' True 'but the board still says what it is'
# 说法是「没在刷新时跑」，不是「没在页面上跑」——页面没有了，看板每刷新一次就要算一遍判据
is '"没在刷新时跑" in p("eta/repo")["queue"]["card"]["criteria"][3]["why"]' True 'and why it was skipped'

# 派出去的 agent 一个字都不该出现：那是 corral board + --viewer 的活。
# eta/m1-backend 在假 corral 的 ls 里、cwd 就落在 eta 的 worktree 上——正是以前会被认出来的那种。
lacks 'eta/m1-backend' 'dispatched agents are not drover的事: no chips, no names'

# 评审协议的东西一律不该再出现
lacks 'Round 1' 'no review rounds'
lacks '暂缓清单' 'no backlog section'
lacks '最近归档' 'no archive section'
lacks '等你裁决' 'no pending decisions'
lacks 'request-review' 'no request-review anywhere'   # 老 herdsman 的命令，看板上不该再提

# ---- 任务区：只有接了队列的项目才有；队列 / 当前这件活 / 做完的 ----
is 'p("alpha/repo")["queue"]' None 'a project without queue.md has no task section'
is 'len([x for x in vm["projects"] if x["queue"]])' 2 'task section only on projects with a queue'
is 'p("eta/repo")["queue"]["todo"][0]["title"]' '修一下登录页的超时' 'hand-written task listed in file order'
is 'p("eta/repo")["queue"]["todo"][0]["id"]' '' 'an unnumbered task has no id yet (it gets one when it goes out)'
is 'p("eta/repo")["queue"]["todo"][0]["next"]' True 'next marker on the first pending task'
is 'p("eta/repo")["queue"]["todo"][1]["id"]' T9 'numbered pending task listed with its ID'
is 'p("eta/repo")["queue"]["todo"][1]["title"]' '订单列表分页' 'and its title'
is 'p("eta/repo")["queue"]["counts"]["todo"]' 2 'two pending'
is 'p("eta/repo")["queue"]["counts"]["done"]' 2 'two finished'
is 'p("eta/repo")["queue"]["counts"]["dropped"]' 1 'one dropped'
is '[f["id"] for f in p("eta/repo")["queue"]["finished"]]' "['T6', 'T7', 'T5']" 'finished list, newest first'
is 'p("eta/repo")["queue"]["finished"][0]["dropped"]' True 'dropped row marked'
is 'p("eta/repo")["queue"]["finished"][0]["reason"]' '和 T2 冲突' 'drop reason shown'
is 'p("eta/repo")["queue"]["finished"][2]["span"]' 20m 'finished row with duration'
is 'p("eta/repo")["queue"]["mode"]' 放行模式 'release-mode chip'
is 'p("theta/repo")["queue"]["mode"]' 暂停中 'paused chip replaces the mode chip'

# theta：做完了、放行模式下还等着人放行
is 'p("theta/repo")["queue"]["card"]["waiting"]' True 'the finished task waits for release'
is 'p("theta/repo")["state"]' 等你放行 'and the project says so'
is 'p("theta/repo")["badge"]' me 'awaiting release is on you'
is '"补登录接口的回归测试（带" in p("theta/repo")["waits"][0] and "引号" in p("theta/repo")["waits"][0]' True \
   'awaiting release listed as waiting on you, title carried verbatim'
is '"做完了，核对已通过" in p("theta/repo")["waits"][0]' True 'and it says the check already passed'
is '"drover go" in p("theta/repo")["waits"][0]' True 'the waiting item says how to release'
is '"下一件会自动送进主控" in p("theta/repo")["waits"][0]' True 'and what happens after release'

# 不接触真实项目
lacks 'jb-finetune' 'real project leaked into the fixture board'
lacks 'Developer/personal_projs' 'default discovery used'

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
echo 'PASS view_model: queue, 等你, the current work and its criteria; no review protocol left'
echo 'PASS drover-board discovery: only ~/.drover/projects, never a directory scan'

# ---- HTML / CSS / JS / HTTP 服务那一整层删干净了 ----
# 看板现在是 TUI：没有静态页、没有本机服务、没有令牌、没有 Host / Origin 校验，也不再管通知。
for s in 'http.server' 'BaseHTTPRequestHandler' '<!doctype' 'rb-token' 'X-RB-Token' '/api/' \
         'def render' 'def serve' 'def live_action' 'def health(started' 'launchctl' 'notify'; do
  grep -qF -e "$s" "${BOARD}" && fail "the HTML / HTTP layer must be gone from drover-board (found: $s)"
done
[ ! -e "${ROOT}/tests/browser-smoke.mjs" ] || fail 'browser-smoke.mjs goes away with the HTML layer'
grep -qE '^import curses' "${BOARD}" || fail 'the board is a curses TUI now'
echo 'PASS the HTML / CSS / JS / HTTP layer is gone; the board is a TUI'

# ---- 中文宽度：curses 按字符数排版会错位，所有排版都过 width() / trunc() ----
python3 - "${BOARD}" <<'PY2' || fail 'width() / trunc() count display cells, not characters'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
s = "把 CSS 导入改成流式"
assert len(s) == 12, len(s)                       # 12 个字符……
assert B.width(s) == 19, B.width(s)               # ……但要占 19 格：东亚宽字符一个顶两个
assert B.width("") == 0 and B.width("abc") == 3
for n in range(0, 24):                            # 截到任何格数，显示宽度都不许超
    t = B.trunc(s, n)
    assert B.width(t) <= n, (n, t, B.width(t))
assert B.trunc(s, 100) == s, "够宽就别动它"
assert B.trunc(s, 8).endswith("…"), B.trunc(s, 8)  # 截了要看得出来
assert B.trunc(s, 0) == ""
PY2
echo 'PASS width() / trunc(): 东亚宽字符算两格，截断不超格'

# ---- draw()：薄薄一层，画进很窄的假屏幕不崩、不越界 ----
python3 - "${BOARD}" "${TMP}/projects" <<'PY2' || fail 'draw() into a narrow screen: no crash, no overflow'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)

class Fake:
    """假屏幕：只实现 draw() 用得着的几个方法，写出界就当场炸。
    curses 真屏幕上越界是 error，而且右下角那一格写不得——两条都在这里守着。"""
    def __init__(self, h, w): self.h, self.w, self.rows = h, w, []
    def getmaxyx(self): return (self.h, self.w)
    def erase(self): self.rows = []
    def addstr(self, y, x, text, attr=0):
        assert 0 <= y < self.h and 0 <= x < self.w, f"越界：({y},{x}) 屏幕 {self.h}x{self.w}"
        limit = self.w - (1 if y == self.h - 1 else 0)          # 右下角那一格不能写
        assert x + B.width(text) <= limit, f"写出右边：({y},{x}) + {B.width(text)} > {limit}：{text!r}"
        self.rows.append((y, x, text))
    def noutrefresh(self): pass
    def refresh(self): pass
    def clear(self): pass

model = B.view_model(B.collect(sys.argv[2]))
for h, w in ((10, 40), (24, 80), (6, 20), (60, 200), (3, 12)):
    for sel in range(len(model["projects"])):
        s = Fake(h, w)
        B.draw(s, model, {"sel": sel, "msg": "很长的提示" * 40})
        assert s.rows, f"{h}x{w} 什么都没画"
s = Fake(10, 40)                                                 # 一个项目都没有时也不能崩
B.draw(s, {"health": {"ok": True, "text": "corral 正常"}, "waits": [], "projects": []}, {"sel": 0, "msg": ""})
PY2
echo 'PASS draw(): 40x10 到 12x3 都不崩、不越界'

# ---- 按键：「按了什么键 → 要做什么」也是一层纯函数 ----
# 推进靠按键，这是新的主操作面（ROADMAP），所以不能只埋在 tui() 里跟 getch 缠着。
# key_action(键码, 选中的项目, state) → 动作，喂键码就能验；tui() 只管 getch 和执行。
# p 和 l 是有状态的：按当前 paused / loop 决定发 pause 还是 resume、loop on 还是 off，切反了就是真 bug。
python3 - "${BOARD}" "${TMP}/projects" <<'PY2' || fail 'key_action(): 键码 → 动作'
import curses, importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)

# 拿真的 view_model 当底子，字段名跟着一起验（手搓的 pv 会和真结构悄悄走散）
model = B.view_model(B.collect(sys.argv[2]))
eta = next(p for p in model["projects"] if p["name"] == "eta/repo")          # 没暂停、循环没开
theta = next(p for p in model["projects"] if p["name"] == "theta/repo")      # 暂停中
none_q = next(p for p in model["projects"] if p["queue"] is None)            # 没接队列的项目
assert eta["queue"]["paused"] is False and eta["queue"]["loop"] is False, eta["queue"]
assert theta["queue"]["paused"] is True, theta["queue"]
looping = {**eta, "queue": {**eta["queue"], "loop": True}}                   # 循环开着的样子
st = lambda sel=0, n=3: {"sel": sel, "n": n}


def act(k, pv=eta, state=None):
    return B.key_action(k, pv, state or st())


# 放行、发下一件：原样转给 drover
assert act(ord("g")) == ("run", ["go"]), act(ord("g"))
assert act(ord("n")) == ("run", ["next"]), act(ord("n"))
# 暂停 / 恢复、循环开 / 关：按当前状态选，切反了就是真 bug
assert act(ord("p")) == ("run", ["pause"]), act(ord("p"))
assert act(ord("p"), theta) == ("run", ["resume"]), act(ord("p"), theta)
assert act(ord("l")) == ("run", ["loop", "on"]), act(ord("l"))
assert act(ord("l"), looping) == ("run", ["loop", "off"]), act(ord("l"), looping)
# 没接队列的项目：当成没暂停、循环没开
assert act(ord("p"), none_q) == ("run", ["pause"]), act(ord("p"), none_q)
assert act(ord("l"), none_q) == ("run", ["loop", "on"]), act(ord("l"), none_q)
# 加任务、退出
assert act(ord("a")) == ("edit",), act(ord("a"))
assert act(ord("q")) == ("quit",), act(ord("q"))

# 选项目：上下都不许越界
for k in (curses.KEY_UP, ord("k")):
    assert act(k, state=st(sel=1)) == ("sel", 0), k
    assert act(k, state=st(sel=0)) == ("sel", 0), k                          # 已经在第一个
for k in (curses.KEY_DOWN, ord("j")):
    assert act(k, state=st(sel=1)) == ("sel", 2), k
    assert act(k, state=st(sel=2)) == ("sel", 2), k                          # 已经在最后一个
for k in (curses.KEY_UP, curses.KEY_DOWN, ord("j"), ord("k")):               # 一个项目都没有
    assert act(k, None, st(sel=0, n=0)) == ("sel", 0), k

# 刷新：手按 r、30 秒没人按（getch 超时给 -1）、窗口改大小，都是重跑一遍
for k in (ord("r"), -1, curses.KEY_RESIZE):
    assert act(k) == ("refresh",), k

# 不认识的键：什么都不做，也不重跑（重跑要跑一圈 git 和 corral，不能乱按就触发）
for k in (ord("x"), ord("Z"), ord("1"), ord("G"), curses.KEY_F1):
    assert act(k) is None, k
# 一个项目都没选中时，对项目的操作一概不做
for k in (ord("g"), ord("n"), ord("p"), ord("l"), ord("a")):
    assert B.key_action(k, None, st(sel=0, n=0)) is None, k
# 纯函数：不许改 state
s = st(sel=1)
for k in (ord("g"), curses.KEY_DOWN, ord("q"), -1):
    B.key_action(k, eta, s)
assert s == {"sel": 1, "n": 3}, s
PY2
echo 'PASS key_action(): 键码 → 动作；p / l 认当前状态，上下不越界，生键不重跑'

# ---- 「等你」通知：跟着守护进程走，和界面无关 ----
# 通知现在由循环引擎（drover loop）每跳发一次，看板一点不管——开不开看板都照发。
# 一个项目新出现的条目合成一条；没变化不重发；条目消失后再出现会重发；AppleScript 字符串要转义；
# 通知发不出去也不能把循环带走。用假的通知命令，不真弹。
tick() { loop "$1" --once --projects "${TMP}/projects"; }
nlines() { if [ -f "${TMP}/notify.log" ]; then wc -l < "${TMP}/notify.log" | tr -d ' '; else echo 0; fi; }
tick "${TMP}/notifier"
[ "$(nlines)" = 2 ] || fail "first tick: one per project waiting on you (eta 等人, theta awaiting release), got $(nlines)"
grep -q 'zeta/repo' "${TMP}/notify.log" && fail 'a blocked 主控 is not drover的事'
grep -q '做完了' "${TMP}/notify.log" || fail 'waiting for release is notified'
tick "${TMP}/notifier"
[ "$(nlines)" = 2 ] || fail 'an unchanged tick must not notify again'
mv "${TMP}/theta/review/tasks.state" "${TMP}/theta/state.bak"
tick "${TMP}/notifier"
[ "$(nlines)" = 2 ] || fail 'an item going away sends nothing'
mv "${TMP}/theta/state.bak" "${TMP}/theta/review/tasks.state"
tick "${TMP}/notifier"
[ "$(nlines)" = 3 ] || fail 'an item that comes back is notified again'
tail -1 "${TMP}/notify.log" | grep -q '做完了' || fail 'the renewed notification carries the item text'
tail -1 "${TMP}/notify.log" | grep -qF '\"引号\"' || fail 'double quotes are escaped for AppleScript'
[ -s "${NH}/.drover/board-notified.json" ] || fail 'the notified state lives in ~/.drover'
tick "${TMP}/no-such-notifier" || fail 'a missing notifier must not break the loop'
echo 'PASS 等你 notifications ride the loop engine: once per project, again when an item returns, escaped, never fatal'

# ---- 通知节流：看一次「有没有新的等你」要跑一遍 collect()，不能每跳都跑 ----
# collect() 每个项目十来个 git 子进程外加一次 corral status；引擎默认 5 秒一跳、常驻一天就是
# 一万七千多跳。节流的是「多久看一次」，**不是**「哪些通知过了」——去重仍旧全靠
# board-notified.json（上一块验的就是它）。循环推进（B.loop_tick）照旧每跳都跑，不跟着节流。
TH2="${TMP}/thome"; mkdir -p "${TH2}/.drover"
HOME="${TH2}" python3 - "${DROVER}" <<'PY2' || fail 'tick(): 通知节流'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("drover_cli", sys.argv[1])
D = importlib.util.module_from_spec(importlib.util.spec_from_loader("drover_cli", l)); l.exec_module(D)

collects, ticks = [], []
D.B.collect = lambda lp: collects.append(lp) or []      # 数一数看了几次
D.B.loop_tick = lambda lp: ticks.append(lp)

D.tick("清单")
D.tick("清单")                                          # 紧接着再来一跳
assert len(collects) == 1, f"连着两跳看了 {len(collects)} 次，应该只看一次"
assert len(ticks) == 2, f"循环推进被一起节流了：只跑了 {len(ticks)} 跳"

D._looked_at -= D.NOTIFY_EVERY + 1                    # 装作隔了足够久
D.tick("清单")
assert len(collects) == 2, f"隔够了还是不看：{len(collects)}"
assert len(ticks) == 3, len(ticks)
assert D.NOTIFY_EVERY >= 60, D.NOTIFY_EVERY             # 别退回成「每跳都看」
PY2
echo 'PASS tick(): 通知节流——循环每跳都推，「有没有新的等你」隔一阵才看一次'

# ---- 外层循环：开关只管开关，推动循环的是引擎进程 `drover loop` ----
# 引擎看到 .loop-wait 且条件满足（有待办、没暂停、不等放行）就跑一次 drover next，由它把
# **任务正文**送进主控。老 herdsman 是往写手 pane 里注入固定那句「运行 drover next」——
# 内依赖外，已经删掉；pane 身份核对那一整套也跟着没了。
dv() { (cd "${TMP}/theta/repo" && python3 "${DROVER}" "$@" >/dev/null); }
mark() { printf '{"reason": "empty", "t": %s}\n' "$(date +%s)" > "${TMP}/theta/review/.loop-wait"; }
engine() { loop "" --once --projects "${TMP}/projects"; }
dv loop on
[ -f "${TMP}/theta/review/loop" ] || fail 'drover loop on turns this project on'
dv resume                                          # fixture 里 theta 是暂停的
dv go                                              # T3 还等着放行，先放掉
rm -f "${TMP}/prompts.log"; mark; engine
[ -s "${TMP}/prompts.log" ] || { cat "${TMP}/theta/review/.loop.log" 2>/dev/null; fail 'the engine sends the next task when one is pending'; }
# 送出去的是任务正文本身，不是「运行 drover …」那种指令
grep -q 'T4' "${TMP}/prompts.log" || { cat "${TMP}/prompts.log"; fail 'the sent text is the task itself'; }
grep -q 'drover' "${TMP}/prompts.log" && { cat "${TMP}/prompts.log"; fail 'the sent text must never tell the agent to run drover'; }
[ ! -f "${TMP}/theta/review/.loop-wait" ] || fail 'the marker is cleared once the task went out'
# 暂停中：不发
dv pause
rm -f "${TMP}/prompts.log"; mark; engine
[ ! -s "${TMP}/prompts.log" ] || fail 'nothing is sent while paused'
dv resume
# 循环关：标记作废，不发
dv loop off
[ ! -f "${TMP}/theta/review/loop" ] || fail 'drover loop off turns it off'
rm -f "${TMP}/prompts.log"; mark; engine
[ ! -s "${TMP}/prompts.log" ] || fail 'nothing is sent with the loop off'
rm -f "${TMP}/theta/review/.loop-wait"
echo 'PASS the loop switch is a switch; driving the loop is drover loop'

# ---- 外层循环闭合：主控空闲下来、且 main 上出现收尾记号时，循环引擎核对三条门，过了就记 done 并发下一件。
# 直接调 loop_tick，不等常驻进程，省得看时序。
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
# 走真入口：drover loop --once。引擎不需要待在某个仓库里，所以不走 setup()。
tick2() { loop "" --once --projects "${TMP}/projects-iota"; }
done_ev() { grep -c '"ev": "done", "id": "T1"' "${IO}/review/tasks.state" 2>/dev/null | head -1; }

# 主控在忙：一次都不许核对——第 3 条可能是整套测试，不能因为它在干活就反复跑
printf 'working\n' > "${TMP}/iota.state"; rm -f "${TMP}/check.log"; tick2
[ ! -f "${TMP}/check.log" ] || { cat "${TMP}/check.log"; fail 'must not run the check command while the 主控 is working'; }
[ "$(done_ev)" = 0 ] || fail 'nothing is marked done while the 主控 is working'
# 主控空闲了，但 main 还没前进（门第 1 条不过，也还没有收尾记号）：核对了，但不标做完
printf 'idle\n' > "${TMP}/iota.state"; tick2
[ "$(done_ev)" = 0 ] || fail 'a task whose criteria are unmet must not be marked done'
# main 前进了，三条门都过了，但主控还没打收尾记号 → 依据不成立 → 绝不自动记 done。
# 这条挡的正是最弱的默认配置：没配 BRANCH_GLOB / CHECK_CMD 时，门只剩「main 前进了」，
# 主控提一行注释就能骗过去。见 ROADMAP 完成判据那一节。
printf 'b\n' >> "${IO}/repo/a.py"; git -C "${IO}/repo" add .; git -C "${IO}/repo" commit -qm work
rm -f "${TMP}/iota.checked" "${IO}/review/.criteria-checked"
tick2
[ "$(done_ev)" = 0 ] || fail 'the gates alone must never close a task: no wrap-up mark, no done'
# 打上收尾记号 → 依据成立 → 自动记 done，并且（自动模式）把下一件送出去
git -C "${IO}/repo" commit -q --allow-empty -m '收尾: 头一件做完了'
rm -f "${TMP}/iota.checked" "${IO}/review/.criteria-checked"     # 清掉节流记录，立刻再查一次
: > "${TMP}/sent-iota"; tick2
[ "$(done_ev)" = 1 ] || { cat "${IO}/review/.loop.log" 2>/dev/null || true; fail 'the loop closes the task itself once the criteria are met'; }
grep -q '"ev": "start", "id": "T2"' "${IO}/review/tasks.state" || fail 'and the next task goes out right after'
# 节流：刚查过就再来一跳，不许再跑一次验收命令
N=$(wc -l < "${TMP}/check.log"); tick2
[ "$(wc -l < "${TMP}/check.log")" = "$N" ] || fail 'the check command is throttled, not run on every tick'

# ---- 常驻进程：同一个进程里连跑两跳，NOW 和 corral 的 agent 列表都必须每跳重取 ----
# 以前 loop_tick 是 `drover board serve` 里的一个线程，NOW / _AGENTS 只在 collect()（渲染页面）
# 里刷新——没人开页面就永远停在启动那一刻。拆成独立进程之后没有渲染这回事了，这条得自己成立。
printf 'working\n' > "${TMP}/iota.state"
printf 'c\n' >> "${IO}/repo/a.py"; git -C "${IO}/repo" add .; git -C "${IO}/repo" commit -qm 'work 2'
git -C "${IO}/repo" commit -q --allow-empty -m '收尾: 第二件做完了'
rm -f "${IO}/review/.criteria-checked"
python3 - "${BOARD}" "${TMP}/projects-iota" "${TMP}/iota.state" <<'PY2'
import importlib.machinery, importlib.util, sys, time
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
B.loop_tick(sys.argv[2])                     # 第一跳：主控在忙
t1 = B.NOW
open(sys.argv[3], "w", encoding="utf-8").write("idle\n")
time.sleep(1.1)
STALE = ["假的：上一跳留下的 agent 清单"]
B._AGENTS = STALE
B.loop_tick(sys.argv[2])                     # 第二跳：必须看见新状态

# 两个不变量，只有独立进程才会碰上：
# NOW 每跳重取 —— 停在启动那刻的话，close_if_done 的节流 `NOW - mtime(stamp) < CHECK_EVERY`
# 会一路算出负数，也就是「永远在节流窗口里」：查一次之后再也不查了。
assert B.NOW > t1, f"NOW 没有重取：{B.NOW} <= {t1}"
# corral 的 agent 清单同理：缓存住的话，主控重开换了 instance、新开的 agent，都认不出来。
assert B._AGENTS is not STALE, "corral 的 agent 清单被跨跳缓存了"
PY2
grep -q '"ev": "done", "id": "T2"' "${IO}/review/tasks.state" \
  || { cat "${IO}/review/.loop.log" 2>/dev/null || true; fail 'a long-running loop must re-read corral every tick, not cache the agent list'; }

echo 'PASS loop engine: checks the criteria only when the 主控 is idle, closes the task itself, throttled'
