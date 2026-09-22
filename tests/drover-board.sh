#!/usr/bin/env bash
# drover-board 冒烟测试：造八个合成仓库，断言看板算出来的东西对 —— 队列、「等你」、
# 当前这件活、完成判据，评审协议的东西一处不剩，且不接触真实项目。
#
# 内容断言打在 view_model() 返回的纯数据上；详情翻页另验纯视口计算、按键和假屏幕，
# 假屏幕一旦写出界就失败，同时确认实际显示的内容随翻页变化。
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
  'status kappa/main') st kappa/main idle;;
  'send iota/main')    printf '%s\n' "$3" >> "${MOCK_DIR}/sent-iota"
                       printf '{"ok":true,"name":"iota/main","instance":1,"confirmed":true}\n';;
  # ls 里有三个：alpha 的主控、eta 的主控、以及 eta 派出去的那个（cwd 在 eta 的 worktree 里）
  'ls ') printf '{"ok":true,"agents":[{"name":"alpha/main","instance":1,"kind":"codex","cwd":"%s"},{"name":"eta/main","instance":1,"kind":"claude","cwd":"%s"},{"name":"eta/m1-backend","instance":2,"kind":"codex","cwd":"%s"},{"name":"eta/ghost","instance":3,"kind":"codex","cwd":"%s"}]}\n' \
           "${MOCK_ALPHA}" "${MOCK_ETA}" "${MOCK_ETA_WT}" "${MOCK_ETA_WT}";;
  'status eta/m1-backend') st eta/m1-backend working;;
  'send theta/main') printf '%s\n' "$3" >> "${MOCK_DIR}/prompts.log"
                     printf '{"ok":true,"name":"theta/main","instance":1,"confirmed":true}\n';;
  *) printf '{"ok":false,"error":"not_found"}\n'; exit 2;;
esac
MOCK
chmod +x "${TMP}/corral"
# eta 派出去的那个 agent 跑在一个 worktree 里（corral-dispatch 就是这么干的）。
# 看板以前会把 corral ls 报的 cwd 顺着 git worktree list 映射回项目，现在不了；这个 worktree
# 留着是给判据第 2 条用的（本次分支有提交、还没合回 main）
git -C "${TMP}/eta/repo" worktree add -q -b m1-backend "${TMP}/eta/wt-m1" >/dev/null 2>&1
# 本次分支上有提交、还没合回 main —— 判据第 2 条应当不过
printf 'wip\n' >> "${TMP}/eta/wt-m1/a.py"
git -C "${TMP}/eta/wt-m1" add a.py; git -C "${TMP}/eta/wt-m1" commit -qm 'm1 wip'
printf 'CHECK_CMD=pytest -q\n' >> "${TMP}/eta/repo/.drover.conf"
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
# 已完成 T5（没有提交，放行模式：做完 5 秒后才放行）、T7（1 个提交，自动模式没有 go）、放弃 T6。theta：T3 做完、放行模式下还没放行，并且暂停中。其余项目没有 queue.md，不出现任务区。
E="${TMP}/eta"; EB=$(git -C "$E/repo" rev-parse HEAD~1); EH=$(git -C "$E/repo" rev-parse HEAD); ES=$(git -C "$E/repo" rev-parse --short HEAD)
printf '## T8 把 CSV 导入改成流式\n约束：内存不超过 200MB\n\n## 修一下登录页的超时\n\n## T9 订单列表分页\n只动分页参数\n### 范围\n- 别碰 <b>旧接口</b> & 文档\n' > "$E/review/queue.md"
{ printf '{"t": %s, "ev": "start", "id": "T5", "title": "给导出加进度条", "body": "", "key": "给导出加进度条", "sha": "%s"}\n' "$((now - 9000))" "$EB"
  printf '{"t": %s, "ev": "done", "id": "T5", "sha": "%s", "gate": true}\n' "$((now - 7800))" "$EB"
  printf '{"t": %s, "ev": "go", "id": "T5"}\n' "$((now - 7795))"
  printf '{"t": %s, "ev": "start", "id": "T7", "title": "实验脚本换参数", "body": "", "key": "实验脚本换参数", "sha": "%s"}\n' "$((now - 7790))" "$EB"
  printf '{"t": %s, "ev": "done", "id": "T7", "sha": "%s", "gate": false}\n' "$((now - 7750))" "$EH"
  printf '{"t": %s, "ev": "drop", "id": "T6", "title": "迁移到新日志库", "key": "迁移到新日志库", "reason": "和 T2 冲突"}\n' "$((now - 7700))"
  printf '{"t": %s, "ev": "start", "id": "T8", "title": "把 CSV 导入改成流式", "body": "约束：内存不超过 200MB", "key": "把 CSV 导入改成流式", "sha": "%s", "main": "%s"}\n' "$((now - 3600))" "$EB" "$EH"
} > "$E/review/tasks.state"
# eta 的任务文件：T5 那件同前缀有两份，「交叉审查」那份排序在前、**没有「路由：」行**
# （真实 docs/任务/ 里就是这个形状），挑的应该是真带那一行的第二份。T7 那件没有任务文件。
mkdir -p "$E/repo/docs/任务"
printf 'TASK_FILE_DIR=docs/任务\n' >> "$E/repo/.drover.conf"
printf '# 交叉审查：给导出加进度条\n\n2026-09-21，eta/main 交给 eta/review-bar。\n你是被委派的审查者：只读审查，不写功能代码。\n' \
  > "$E/repo/docs/任务/给导出加进度条 交叉审查.md"
printf '# 任务：给导出加进度条\n\n2026-09-21，eta/main 交给 eta/dev-bar。\n路由：重 / 交叉审查要（路由：档=拿不准，交叉审查=要（0.9）；推翻：档位路由拿不准，主控定为重）。\n' \
  > "$E/repo/docs/任务/给导出加进度条 加个进度条.md"
TH="${TMP}/theta"; THB=$(git -C "$TH/repo" rev-parse HEAD~1)
printf '## T3 补登录接口的回归测试\n\n## T4 清理旧的 feature flag\n' > "$TH/review/queue.md"
{ printf '{"t": %s, "ev": "start", "id": "T3", "title": "补登录接口的回归测试（带\\"引号\\"）", "body": "", "key": "补登录接口的回归测试（带\\"引号\\"）", "sha": "%s"}\n' "$((now - 2000))" "$THB"
  printf '{"t": %s, "ev": "done", "id": "T3", "sha": "%s", "gate": true}\n' "$((now - 100))" "$THB"
} > "$TH/review/tasks.state"
: > "$TH/review/paused"

printf '%s/alpha/repo\n%s/beta/repo\n%s/gamma/repo\n%s/delta/repo\n%s/epsilon/repo\n%s/zeta/repo\n%s/eta/repo\n%s/theta/repo\n# comment\n%s/nonexistent\n' "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" > "${TMP}/projects"

# ============================================================ view_model：看板要显示的一切
vm() {   # [项目清单] 重跑一遍 collect + view_model，结果落成 JSON。「刷新等于重跑」，看板不存自己的状态
  python3 - "${BOARD}" "${1:-${TMP}/projects}" "${VM}" <<'PY2' || fail 'view_model() 跑不起来'
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
# 任务正文（2026-09-22 加）：在看板上要看得见这件活到底要干什么，不用切去 queue.md。
# 正文只进显示——判据、收尾记号、loop_tick 都不碰它，和「路由：」行同一条边界。
is 'p("eta/repo")["queue"]["card"]["body"]' "['约束：内存不超过 200MB']" 'and its body, so you can see what the task actually asks'
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
is '"按 g / drover go 核对并放行" in p("eta/repo")["queue"]["card"]["criteria"][3]["why"]' True 'the check hint leads directly to g/go'

# 派出去的 agent：2026-09-22 用户要求显示状态（m5 删掉的是重量级的那版，见 crew_of 的注释）。
# eta/m1-backend 在假 corral 的 ls 里、cwd 落在 eta 的 worktree 上——正该被认出来。
is 'len(p("eta/repo")["queue"]["crew"])' 2 'agents living in the repo worktree show up'
is 'p("eta/repo")["queue"]["crew"][0]["name"]' eta/ghost 'sorted by name'
is 'p("eta/repo")["queue"]["crew"][1]["name"]' eta/m1-backend 'both of them'
is 'p("eta/repo")["queue"]["crew"][1]["state"]' working 'with its state'
is 'p("eta/repo")["queue"]["crew"][1]["where"]' wt-m1 'and which worktree it lives in'
# 查不到状态的照样列出来、标 unknown：**列表本身就是信息**（有几个 agent 住在这个仓库里）。
# eta/ghost 在假 corral 的 ls 里，但没有 status 分支 —— 落到 not_found。
is 'p("eta/repo")["queue"]["crew"][0]["state"]' unknown 'an agent whose status cannot be read is still listed'
# 主控自己不算进「干活的 agent」——它在顶栏已经有了
is '[a for a in p("eta/repo")["queue"]["crew"] if a["name"] == "eta/main"]' '[]' 'the 主控 is not crew'
# 边界照旧：只给状态，不长成 agent 看板（那是 corral board + --viewer 的活）
# 边界：只给状态，不长成 agent 看板。「在调什么工具」是 corral board 的活。
# （attach 提示不在此列——「等你」那栏本来就带 corral attach，是给人抄的命令。）
lacks '在调' 'no tool-activity chips: still not an agent board'

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

# ---- 「做完的」栏的记账三项：耗时、提交数、等放行时长（ROADMAP 待定 3 的结论） ----
# 三项全部从现有的 tasks.state 事件流和 git 算出来，不加新事件、不改事件格式。
# **「返工轮数」不做**：drover 看不见主控和 dev agent 之间的往返（硬规矩第 4 条），记不出来。
# 提交数就叫提交数，任何文案里都不许把它说成或暗示成返工轮数。
is 'p("eta/repo")["queue"]["finished"][2]["id"]' T5 'the oldest finished row is T5'
is 'p("eta/repo")["queue"]["finished"][2]["commits"]' 0 '记账·提交数：T5 起止 sha 一样，一个提交都没有'
is 'p("eta/repo")["queue"]["finished"][2]["wait"]' 5s '记账·等放行时长 = go 的 t 减 done 的 t'
is 'p("eta/repo")["queue"]["finished"][1]["id"]' T7 'the next finished row is T7'
is 'p("eta/repo")["queue"]["finished"][1]["span"]' 40s '记账·耗时 = done 的 t 减 start 的 t，沿用 ago() 的口径（40 秒就写秒）'
is 'p("eta/repo")["queue"]["finished"][1]["commits"]' 1 '记账·提交数用 task_commits 算，不另写一份'
# 自动模式（done 事件不带 gate，没有 go 事件）：这一项**不显示**，不是 0
is 'p("eta/repo")["queue"]["finished"][1]["wait"]' '' '自动模式没有 go 事件：等放行时长不显示，不是 0'
lacks '返工' '提交数就叫提交数：任何文案里都不许把它说成返工轮数（ROADMAP 待定 3：记不出来）'
# 路由也进「做完的」栏（ROADMAP 待定 3 的记账内容里本来就有「路由判了什么 / 推翻没有」）。
# 同前缀两份时挑**含「路由：」行**的那一份：排序第一的「交叉审查」那份没有那行，要跳过它。
is 'p("eta/repo")["queue"]["finished"][2]["route"]["tier"]' 重 '「做完的」行也带路由：同前缀两份里挑含「路由：」行的那份'
is 'p("eta/repo")["queue"]["finished"][2]["route"]["cross"]' True '交叉审查要'
is 'p("eta/repo")["queue"]["finished"][2]["route"]["overridden"]' True '主控推翻了路由'
is 'p("eta/repo")["queue"]["finished"][1]["route"]' None '没有任务文件的那件：路由那一项不显示，照样记账'
# 放弃的那件不记账：它没做完，耗时和提交数都无从谈起
is 'p("eta/repo")["queue"]["finished"][0]["dropped"]' True 'the dropped row stays a dropped row'
# 时长只有一套口径：ago() 那套（秒 / 分 / 时分 / 天），耗时和等放行时长都走它，不另发明格式。
# 顺带验「做完的」那一行真把三项画出来了——view_model 有数据、画面上没有的话等于没做。
python3 - "${BOARD}" "${TMP}/projects" <<'PY2' || fail '记账：时长口径 + 「做完的」那一行'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)

# 一段时长怎么写：和 ago() 一个字不差（不满一分钟写秒——老的 task_span 在这里写 0m）
for sec, want in ((0, "0s"), (45, "45s"), (1200, "20m"), (3780, "1h03m"), (90000, "1d")):
    assert B.task_span(1e9, 1e9 + sec) == want, (sec, B.task_span(1e9, 1e9 + sec))
    assert B.ago(B.NOW - sec) == want, (sec, B.ago(B.NOW - sec))
assert B.task_span(None, 5) == "" and B.task_span(5, None) == "", "缺一头就不显示"

pv = next(x for x in B.view_model(B.collect(sys.argv[2]))["projects"] if x["name"] == "eta/repo")
# 判据理由压平旧 split() 识别的 ASCII 空白控制字符；Unicode 必须整串相等。
for why, want in (
    ("还没合进 main：feature/name\xa0", "✗ 门2：还没合进 main：feature/name\xa0"),
    ("还没合进 main：feature/name\u2028tail", "✗ 门2：还没合进 main：feature/name\u2028tail"),
    ("还没合进 main：feature/name\u2029tail", "✗ 门2：还没合进 main：feature/name\u2029tail"),
    ("还没合进 main：feature/name\x85tail", "✗ 门2：还没合进 main：feature/name\x85tail"),
    ("\n".join(["git 查询失败：分支甲", "git 查询失败：分支乙"]),
     "✗ 门2：git 查询失败：分支甲 git 查询失败：分支乙"),
    ("错误甲\r\n\n\r错误乙\r错误丙\n\n错误丁", "✗ 门2：错误甲 错误乙 错误丙 错误丁"),
    ("错误甲\t错误乙\x1f错误丙\v\f\x1c\x1d\x1e\n\r错误丁", "✗ 门2：错误甲 错误乙 错误丙 错误丁"),
    ("\r\n  错误甲\t \n  错误乙  \r", "✗ 门2：   错误甲     错误乙   "),
):
    detail_pv = {**pv, "waits": [], "queue": {**pv["queue"], "crew": [],
        "card": {**pv["queue"]["card"], "criteria": [{"name": "门2", "ok": False, "why": why}]}}}
    actual = [t for style, _, t in B.detail_lines(detail_pv) if style == "bad"]
    assert not any("\x00" <= ch <= "\x1f" for ch in actual[0]), f"详情残留 ASCII 控制字符：{ascii(actual[0])}"
    assert actual == [want], f"详情理由被改写：{ascii(actual)} != {ascii([want])}"
    assert "\n" not in actual[0] and "\r" not in actual[0], ascii(actual[0])
rows = [t for _, _, t in B.detail_lines(pv)]
t5 = next(t for t in rows if t.startswith("T5 "))
assert "20m" in t5 and "0 个提交" in t5 and "等放行 5s" in t5, t5
assert "重档（推翻）" in t5, f"「做完的」一行要能看出档位和主控推翻了路由：{t5}"
# 一行一件，挤：路由紧跟标题排在记账前面，80 列窄屏（详情区就剩 52 格）截完之后，
# 编号、标题、路由、耗时都还在——掉的是三项里最不要紧的「等放行时长」
narrow = B.trunc(t5, 52)
assert narrow.startswith("T5 给导出加进度条") and "重档" in narrow and "20m" in narrow, narrow
assert B.width(t5) <= 60, f"「做完的」那一行别再长了（{B.width(t5)} 格）：{t5}"
t7 = next(t for t in rows if t.startswith("T7 "))
assert "40s" in t7 and "1 个提交" in t7, t7
assert "等放行" not in t7, f"自动模式不该有等放行时长：{t7}"
assert "档" not in t7, f"没有任务文件的那件不该冒出路由：{t7}"
assert not any("返工" in t for t in rows), rows
PY2
echo 'PASS 「做完的」栏记账：耗时 / 提交数 / 等放行时长，口径沿用 ago()'

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

# 夹限用固定例子验，不启动 curses：窗口变高/变矮、内容缩短、无可视行。
assert B.detail_viewport(20, 7, 0, 1) == (6, 6)
assert B.detail_viewport(20, 7, 999) == (14, 6)
assert B.detail_viewport(20, 7, -3) == (0, 6)
assert B.detail_viewport(20, 4, 14, 1) == (17, 3)
assert B.detail_viewport(20, 10, 17) == (11, 9)
assert B.detail_viewport(4, 7, 14, 1) == (0, 7)
assert B.detail_viewport(7, 7, 0, 1) == (0, 7)
assert B.detail_viewport(20, 0, 14, 1) == (0, 0)

# 真正的 detail_lines 内容：25 行详情，10 行屏幕里每页 6 行 + 1 行翻页提示。
import copy, curses
from unittest.mock import patch
pv = next(p for p in model["projects"] if p["name"] == "eta/repo")
long_pv = {**pv, "waits": [], "queue": {**pv["queue"], "card": None, "finished": [], "crew": [],
    "counts": {"todo": 20, "done": 0, "dropped": 0},
    "todo": [{"id": "", "title": f"任务{i:02d} 中文宽度", "next": False, "held": False}
             for i in range(1, 21)]}}
# crew 显式清空：这组用例验的是翻页夹限，行数要可预期，不受「干活的 agent」那块影响。
# 那块自己的断言在下面。
short_pv = {**pv, "repo": "另一个仓库", "queue": None, "waits": []}
equal_pv = {**long_pv, "repo": "等长的另一个仓库"}
assert len(B.detail_lines(long_pv)) == len(B.detail_lines(equal_pv)) == 25
overflow_pv = {**long_pv, "queue": {**long_pv["queue"],
    "counts": {"todo": 7, "done": 0, "dropped": 0}, "todo": long_pv["queue"]["todo"][:7]}}
assert len(B.detail_lines(overflow_pv)) == 12
vm = {**model, "projects": [long_pv, short_pv]}
original = copy.deepcopy(vm)
for w, x in ((80, 26), (20, 0)):                         # 同时覆盖有侧栏和 rail = 0
    screen, state = Fake(10, w), {"sel": 0}
    B.draw(screen, vm, state)
    assert state.get("detail_room") == 7, "draw 尚未提供当帧详情视口"
    assert state["detail_total"] == 25
    state["detail_offset"] = B.key_action(curses.KEY_NPAGE, long_pv, state)[1]
    B.draw(screen, vm, state)
    assert state["detail_offset"] == 6
    assert any(y == 2 and col == x + 2 and "任务04" in text for y, col, text in screen.rows)
    assert (8, x, "PgUp↑6 PgDn↓13") in screen.rows

    state["detail_offset"] = 999
    B.draw(screen, vm, state)
    assert state["detail_offset"] == 19
    assert (8, x, "PgUp↑19 PgDn↓0") in screen.rows
    assert any("还没有" in text for _, _, text in screen.rows)
    screen.h = 6                                         # 窗口变矮后继续下翻，夹在新底部
    B.draw(screen, vm, state)
    state["detail_offset"] = B.key_action(curses.KEY_NPAGE, long_pv, state)[1]
    B.draw(screen, vm, state)
    assert state["detail_offset"] == 21
    screen.h = 10                                        # 变高，旧偏移重新夹住
    B.draw(screen, vm, state)
    assert state["detail_offset"] == 19
    state["sel"] = 1                                     # 切项目必须回顶
    B.draw(screen, vm, state)
    assert state["detail_offset"] == 0
    assert B.key_action(curses.KEY_NPAGE, short_pv, state) == ("scroll", 0)
    state["sel"] = 0
    B.draw(screen, vm, state)
    assert state["detail_offset"] == 0
    state["detail_offset"] = 19
    shorter = {**long_pv, "queue": None}                  # 同一项目刷新，内容缩短
    B.draw(screen, {**vm, "projects": [shorter]}, state)
    assert state["detail_offset"] == 0
    B.draw(screen, vm, state)
    state["detail_offset"] = 19
    B.draw(screen, {**vm, "projects": [short_pv, long_pv]}, state)  # 刷新重排项目
    assert state["detail_offset"] == 0

    # 同仓库缩短后仍溢出：旧偏移越界夹到非零末页，仍合法则原样保留。
    for old_offset, expected in ((19, 6), (3, 3)):
        state = {"sel": 0}
        B.draw(screen, vm, state)
        state["detail_offset"] = old_offset
        B.draw(screen, vm, state)
        assert state["detail_offset"] == old_offset
        B.draw(screen, {**vm, "projects": [overflow_pv]}, state)
        assert state["detail_total"] == 12 and state["detail_room"] == 7
        assert state["detail_offset"] == expected, f"内容缩短后偏移应为 {expected}（旧偏移 {old_offset}）"

    # 等长项目让夹限无法顺带归零，单独守住切换和刷新重排时的项目身份判断。
    for change in ("切换", "重排"):
        equal_vm, state = {**model, "projects": [long_pv, equal_pv]}, {"sel": 0}
        B.draw(screen, equal_vm, state)
        state["detail_offset"] = B.key_action(curses.KEY_NPAGE, long_pv, state)[1]
        B.draw(screen, equal_vm, state)
        assert state["detail_offset"] == 6
        if change == "切换":
            state["sel"] = B.key_action(ord("j"), long_pv, {**state, "n": 2})[1]
            assert state["sel"] == 1
        else:
            equal_vm = {**equal_vm, "projects": [equal_pv, long_pv]}
        B.draw(screen, equal_vm, state)
        assert state["detail_offset"] == 0, f"等长项目{change}后偏移必须归零"
assert vm == original, "显示不能改 view_model 的内容"

# 真 tui 分发到 draw：只替换 curses 边界，项目、数据和按键逻辑照常跑。
class Interactive(Fake):
    def __init__(self):
        super().__init__(5, 80)
        self.frames = []
        self.keys = iter((curses.KEY_NPAGE, curses.KEY_PPAGE, ord("q")))
    def timeout(self, ms): assert ms == B.REFRESH_MS
    def getch(self):
        self.frames.append(list(self.rows))
        return next(self.keys)
screen = Interactive()
with patch.object(B.curses, "curs_set"), patch.object(B.curses, "start_color", side_effect=curses.error):
    B.tui(screen, sys.argv[2])
assert screen.frames[0] != screen.frames[1], "tui 必须执行翻页动作"
assert screen.frames[0] == screen.frames[2], "向上翻后回到第一屏"
# 「干活的 agent」那块：有 crew 就多出标题 + 每个 agent 一行，没有就一行都不占。
crew_pv = {**long_pv, "queue": {**long_pv["queue"], "crew": [
    {"name": "eta/dev-1", "kind": "codex", "state": "working", "since": 0, "where": "wt-m1"},
    {"name": "eta/rev-1", "kind": "codex", "state": "idle", "since": 90, "where": "wt-rev"}]}}
crew_lines = B.detail_lines(crew_pv)
assert len(crew_lines) == len(B.detail_lines(long_pv)) + 3, len(crew_lines)
# 正文要真的画出来（card 有 body 时）
body_pv = {**pv, "waits": []}
body_text = "\n".join(t for _, _, t in B.detail_lines(body_pv))
assert "约束：内存不超过 200MB" in body_text, "任务正文没上屏"

crew_text = "\n".join(t for _, _, t in crew_lines)
assert "干活的 agent · 2" in crew_text, crew_text
assert "eta/dev-1  working" in crew_text and "eta/rev-1  idle" in crew_text, crew_text
assert "闲了" in crew_text, "idle 的要显示闲了多久"
assert "wt-m1" in crew_text, "要说清楚住在哪个 worktree"
PY2
echo 'PASS draw(): 翻页、夹限、切项目、缩窗和内容缩短；窄屏不越界，tui 执行翻页'

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

# 翻页只返回新偏移，不重跑数据；7 行正文留 1 行提示，每页 6 行。
scroll = {**st(), "detail_offset": 0, "detail_total": 20, "detail_room": 7}
# 每次调用立即验输入不变，不能让相反方向的副作用抵消。
for key, name, start in ((curses.KEY_NPAGE, "PgDn", 0), (curses.KEY_PPAGE, "PgUp", 12)):
    candidate = {**scroll, "detail_offset": start}
    before = candidate.copy()
    action = act(key, state=candidate)
    assert candidate == before, f"{name} 单次调用不得修改输入 state"
    assert action == ("scroll", 6), (name, action)
assert act(curses.KEY_NPAGE, state=scroll) == ("scroll", 6), "PgDn 尚未滚动详情"
assert act(curses.KEY_PPAGE, state=scroll) == ("scroll", 0)
assert act(curses.KEY_NPAGE, state={**scroll, "detail_offset": 12}) == ("scroll", 14)
assert act(curses.KEY_NPAGE, state={**scroll, "detail_offset": 14}) == ("scroll", 14)
assert act(curses.KEY_PPAGE, state={**scroll, "detail_offset": 14}) == ("scroll", 8)
assert act(curses.KEY_PPAGE, state={**scroll, "detail_offset": 2}) == ("scroll", 0)
assert act(curses.KEY_NPAGE, state={**scroll, "detail_total": 4}) == ("scroll", 0)
assert act(curses.KEY_NPAGE) == ("scroll", 0)              # 首帧还没有尺寸也安全
assert scroll == {**st(), "detail_offset": 0, "detail_total": 20, "detail_room": 7}
for k in (curses.KEY_NPAGE, curses.KEY_PPAGE):
    assert act(k, None) is None

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
# 这条挡的正是最弱的默认配置：没配 CHECK_CMD 且没有其它分支时，只要 main 前进门就全开，
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

# ============================================================ 任务文件开头那行「路由：…」
# ROADMAP 待定 4 的结论：**读，但降级处理**——解析不出来就不显示这一项，绝不参与任何判断。
# 自己一份合成项目，免得和上面那八个的断言搅在一起。
KA="${TMP}/kappa"; KR="${KA}/kappa"; mkdir -p "${KR}/docs/任务" "${KA}/review"
git -C "${KR}" init -q -b main
git -C "${KR}" config user.name t; git -C "${KR}" config user.email t@example.com
printf 'a\n' > "${KR}/a.py"; git -C "${KR}" add .; git -C "${KR}" commit -qm base
KAB=$(git -C "${KR}" rev-parse main)
printf 'HANDOFF_DIR=%s\nMAIN_AGENT=kappa/main\nTASK_GATE=0\n' "${KA}/review" > "${KR}/.drover.conf"
printf '## T1 把 CSV 导入改成流式\n' > "${KA}/review/queue.md"
printf '%s/kappa/kappa\n' "${TMP}" > "${TMP}/projects-kappa"
TF="${KR}/docs/任务/把 CSV 导入改成流式 流式改造.md"      # 文件名以队列条目标题开头

conf_dir() {   # <TASK_FILE_DIR 的值>：只动这一个键
  grep -v '^TASK_FILE_DIR=' "${KR}/.drover.conf" > "${TMP}/kconf"; cp "${TMP}/kconf" "${KR}/.drover.conf"
  printf 'TASK_FILE_DIR=%s\n' "$1" >> "${KR}/.drover.conf"
}
kastate() {   # <正文>：T1 进行中；正文里写不写「任务文件：」那一行，是两条路的分水岭
  printf '{"t": %s, "ev": "start", "id": "T1", "title": "把 CSV 导入改成流式", "body": "%s", "key": "把 CSV 导入改成流式", "sha": "%s", "main": "%s"}\n' \
    "$((now - 3600))" "$1" "${KAB}" "${KAB}" > "${KA}/review/tasks.state"
}
task_file() {   # <路由那一行> <落到哪个文件>：一份像模像样的任务文件
  { printf '# 任务：把 CSV 导入改成流式\n\n'
    printf '2026-09-21，kappa/main 交给 kappa/dev-csv（Claude Code，重档）。\n'
    printf '%s\n' "$1"
    printf '你是被委派的 agent：照本文件做，不要再开别的 agent。\n'; } > "$2"
}
kroute() { vm "${TMP}/projects-kappa"; }
# 路由行在不在、解析成不成功，判据都必须一个字不变：kappa 是「收尾记号没有 + main 没前进」，
# 分支为空通过、验收命令不适用，所以永远是 1/3。每一步都顺手验一遍。
kmet() { is 'p("kappa")["queue"]["card"]["met"]' 1/3 "$1：完成判据一个字都没变"; }

kastate ""
conf_dir 'docs/任务'
# TASK_FILE_DIR 是 drover init 写出来的配置模板里的一个键，parse_conf 照常读得到
python3 - "${BOARD}" "${DROVER}" "${KR}/.drover.conf" <<'PY2' || fail 'TASK_FILE_DIR：模板里有，parse_conf 读得到'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
def mod(name, path):
    l = importlib.machinery.SourceFileLoader(name, path)
    m = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, l)); l.exec_module(m); return m
B = mod("rb", sys.argv[1])
D = mod("drover_cli", sys.argv[2])
assert "\nTASK_FILE_DIR=\n" in D.CONF_TEMPLATE, "配置模板里没有 TASK_FILE_DIR"
assert "TASK_FILE_DIR=" in D.CONF_TEMPLATE.format(dir="/x")           # 新项目默认留空
assert B.parse_conf(sys.argv[3]).get("TASK_FILE_DIR") == "docs/任务", B.parse_conf(sys.argv[3])
PY2

task_file '路由：重 / 交叉审查不要（路由：档=重（0.9），交叉审查=拿不准；推翻：无）。' "${TF}"
kroute
is 'p("kappa")["queue"]["card"]["route"]["tier"]' 重 '路由行：档位解析出来了'
is 'p("kappa")["queue"]["card"]["route"]["cross"]' False '路由行：要不要交叉审查解析出来了'
is 'p("kappa")["queue"]["card"]["route"]["overridden"]' False '「推翻：无」不算推翻'
kmet '正常解析'

# 「推翻：无」后面接着写别的（主控真就这么写过）：还是没推翻，别当成推翻了
task_file '路由：常规 / 交叉审查不要（路由：档=拿不准（常规 0.85），交叉审查=拿不准；推翻：无。档按「按任务文件写功能」定为常规；交叉审查定为不要——这件活只写文件不执行）。' "${TF}"
kroute
is 'p("kappa")["queue"]["card"]["route"]["overridden"]' False '「推翻：无。」后面接着写理由的，还是没推翻'
is 'p("kappa")["queue"]["card"]["route"]["tier"]' 常规 '档位照样认得'

# 主控推翻了路由的那一版
task_file '路由：常规 / 交叉审查要（路由：档=拿不准（倾向重 0.76），交叉审查=要（核心规则 0.91）；推翻：档位路由拿不准，主控定为常规——修法 ROADMAP 已经写死）。' "${TF}"
kroute
is 'p("kappa")["queue"]["card"]["route"]["tier"]' 常规 '换一档也认得'
is 'p("kappa")["queue"]["card"]["route"]["cross"]' True '交叉审查要'
is 'p("kappa")["queue"]["card"]["route"]["overridden"]' True '主控推翻了路由，看得出来'
kmet '推翻那一版'

# 队列条目正文里写了「任务文件：<相对路径>」→ 用它，不走标题前缀匹配（和「验收：」同一套机制）
task_file '路由：轻 / 交叉审查不要（路由：档=轻（0.95），交叉审查=不要（0.93）；推翻：无）。' "${KR}/docs/任务/另外指名的那一份.md"
kastate '任务文件：docs/任务/另外指名的那一份.md'
kroute
is 'p("kappa")["queue"]["card"]["route"]["tier"]' 轻 '正文指名了任务文件就用它，不再按标题前缀找'
kmet '指名任务文件'
kastate ''

# ---- 降级：任何一种都只是不显示这一项，看板照常渲染，不抛异常、判据不受影响 ----
degrade() {   # <说明>
  kroute
  is 'p("kappa")["queue"]["card"]["route"]' None "$1：路由那一项不显示"
  is 'p("kappa")["queue"]["card"]["id"]' T1 "$1：看板照常渲染"
  kmet "$1"
}
conf_dir ''                     ; degrade 'TASK_FILE_DIR 留空'
conf_dir 'docs/没有这个目录'     ; degrade '配的目录不存在'
conf_dir 'docs/任务'
mv "${TF}" "${KR}/docs/任务/对不上标题的名字.md"
degrade '目录在、找不到这件活的文件'
task_file '路由：写成大白话了，没有斜杠也没有交叉审查那半句' "${TF}"
degrade '那一行格式对不上'
printf '\xff\xfe 路由：重 / 交叉审查不要（路由：档=重；推翻：无）\n' > "${TF}"
degrade '文件编码坏了'
task_file '路由：重 / 交叉审查不要（路由：档=重（0.9），交叉审查=拿不准；推翻：无）。' "${TF}"
kroute
is 'p("kappa")["queue"]["card"]["route"]["tier"]' 重 '修好了又显示出来'
echo 'PASS 任务文件的「路由：」行：档位 / 交叉审查 / 推翻；两条找法，六种降级都只是不显示'

# ---- 守住「绝不参与任何判断」：路由行只进显示，判据、wants_human、loop_tick 都不许碰它 ----
git -C "${KR}" add -A; git -C "${KR}" commit -qm 'task files'      # 工作区要干净，drover done 才肯核对
printf 'b\n' >> "${KR}/a.py"; git -C "${KR}" add -A; git -C "${KR}" commit -qm work
git -C "${KR}" commit -q --allow-empty -m '收尾: 头一件做完了'
: > "${KA}/review/loop"
python3 - "${BOARD}" "${TMP}/projects-kappa" "${KR}/.drover.conf" <<'PY2' || fail '路由行绝不参与任何判断'
import importlib.machinery, importlib.util, json, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
projects, conf = sys.argv[2], sys.argv[3]
frozen = B.time.time(); B.time.time = lambda: frozen      # 两次算的 NOW 一样，剩下的差别才说明问题

def strip(x):     # 把 route 这一项摘掉，别的必须一模一样
    if isinstance(x, dict):
        return {k: strip(v) for k, v in x.items() if k != "route"}
    return [strip(v) for v in x] if isinstance(x, list) else x

with_route = B.view_model(B.collect(projects))
assert with_route["projects"][0]["queue"]["card"]["route"], "底子不对：这一版本该解析得出路由"
text = open(conf, encoding="utf-8").read()
open(conf, "w", encoding="utf-8").write("".join(
    l for l in text.splitlines(keepends=True) if not l.startswith("TASK_FILE_DIR=")))
without = B.view_model(B.collect(projects))
open(conf, "w", encoding="utf-8").write(text)
assert without["projects"][0]["queue"]["card"]["route"] is None, "没配 TASK_FILE_DIR 时不该有路由"
assert strip(with_route) == strip(without), "路由行影响到了别的东西：\n" + \
    json.dumps([strip(with_route), strip(without)], ensure_ascii=False, indent=1)

# 判断那一路上碰一下路由就当场炸：判据、收尾记号、「等人」、外层循环的一跳，一个都不许碰
p = B.collect(projects)[0]
rows = [B.find_done_mark(p["repo"], p["tasks"]["card"]["main"], p["done_mark"])] + \
    B.criteria(p["repo"], p["tasks"]["card"]["main"], "", do_check=False)
B.task_route = lambda *a, **k: 1 / 0
assert [B.find_done_mark(p["repo"], p["tasks"]["card"]["main"], p["done_mark"])] + \
    B.criteria(p["repo"], p["tasks"]["card"]["main"], "", do_check=False) == rows
B.wants_human(p)                                           # 「等人」也只看 git 和 corral
B.loop_tick(projects)                                      # 主控空闲 + 有收尾记号 → 该自己记 done
PY2
grep -q '"ev": "done", "id": "T1"' "${KA}/review/tasks.state" \
  || { cat "${KA}/review/.loop.log" 2>/dev/null || true; fail 'the loop must close the task exactly as it would without the 路由 line'; }
echo 'PASS 路由行只进显示：判据、收尾记号、等人、loop_tick 一概碰不到它'

# 第 3 条上次核对的结果只喂显示；原子发布、陈旧检测和判断边界一起验。
DROVER_BIN="${DROVER}" DROVER_BOARD_BIN="${BOARD}" python3 "${ROOT}/tests/check-result.py"

# 完成记录（2026-09-21，交叉审查返工；本轮限定只改本文件，记录也留在这里）：
# 新增同仓库 25→12 行的溢出用例：偏移 19→6、合法偏移 3→3，宽窄屏均验；
# PgDn 从 0、PgUp 从 12 独立调用，各自先复制输入、调用后立即验输入未变。原断言全部保留。
# 变异自证使用临时 drover-board / drover 副本，以 DROVER_BOARD_BIN 指向副本跑 bash tests/drover-board.sh：
# 1. 在 draw 的夹限前植入 if state.get("detail_total") != len(lines): offset = 0，
#    退出 1，命中 AssertionError: 内容缩短后偏移应为 6（旧偏移 19）。
# 2. 在 key_action 返回翻页动作前植入 state["detail_offset"] = offset，
#    退出 1，命中 AssertionError: PgDn 单次调用不得修改输入 state。
# 两个副本均还原并校验字节一致；生产代码全程未改，主仓库审查文件只读。
# 原实现回归：for t in criteria drover install drover-board; do bash tests/$t.sh || exit 1; done
# 四套件全绿、退出 0（安装 9 项、看板 13 块）；bash -n 与 git diff --check 通过。
