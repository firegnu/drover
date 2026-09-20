#!/usr/bin/env bash
# review-board 冒烟测试：造三个仓库覆盖 待人裁决 / 评审中 / triage 中，再造一份归档，
# 断言生成的 HTML 里状态、横幅、finding 行、Backlog、归档都在，且不接触真实项目。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BOARD=${REVIEW_BOARD_BIN:-${ROOT}/bin/review-board}
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
  printf 'REVIEW_DIR=%s\n' "${TMP}/$n/review" > "$r/.drover.conf"
}
mk alpha; mk beta; mk gamma; mk delta; mk epsilon; mk zeta; mk eta; mk theta
now=$(date +%s)

# 假 herdr：beta 的评审方 blocked，gamma 的在 working，其余 pane 不存在
cat > "${TMP}/herdr" <<'MOCK'
#!/usr/bin/env bash
case "$1 $2 $3" in
  'agent get beta-pane')  printf '{"result":{"agent":{"agent_status":"blocked"}}}\n';;
  'agent get gamma-pane') printf '{"result":{"agent":{"agent_status":"working"}}}\n';;
  'agent get eps-plan')   printf '{"result":{"agent":{"agent_status":"working"}}}\n';;
  'agent list ') printf '{"result":{"agents":[{"agent":"codex","agent_status":"working","cwd":"%s","pane_id":"alpha-writer","terminal_title_stripped":"repo"},{"agent":"claude","agent_status":"working","cwd":"%s","pane_id":"gamma-pane","terminal_title_stripped":"Triage request"},{"agent":"claude","agent_status":"working","cwd":"%s","pane_id":"eps-plan","name":"pl-repo-","terminal_title_stripped":"Plan request"},{"agent":"codex","agent_status":"blocked","cwd":"%s","pane_id":"zeta-writer","terminal_title_stripped":"repo"}]}}\n' "${MOCK_ALPHA}" "${MOCK_GAMMA}" "${MOCK_EPS}" "${MOCK_ZETA}";;
  'agent read eps-plan') printf '✻ Drafting… (2m 01s · esc to interrupt)\n';;
  'agent read alpha-writer') printf 'some output\n• Working (12m 03s • esc to interrupt)\n\n› Ask Codex\n';;
  'agent read gamma-pane') printf '✻ Reviewing diff… (3m 10s · esc to interrupt)\n\n❯\n';;
  'agent get theta-writer') printf '{"result":{"agent":{"pane_id":"theta-writer","terminal_id":"%s","agent_status":"%s","cwd":"%s","agent_session":{"value":"s1"}}}}\n' \
      "$(cat "${MOCK_DIR}/theta.term" 2>/dev/null || echo term_t)" "$(cat "${MOCK_DIR}/theta.status" 2>/dev/null || echo idle)" "${MOCK_THETA}";;
  'agent prompt theta-writer') printf '%s\n' "$4" >> "${MOCK_DIR}/prompts.log";;
  *) printf '{"error":{"code":"agent_not_found"}}\n' >&2; exit 1;;
esac
MOCK
chmod +x "${TMP}/herdr"
export MOCK_ALPHA="${TMP}/alpha/repo" MOCK_GAMMA="${TMP}/gamma/repo" MOCK_EPS="${TMP}/epsilon/repo" MOCK_ZETA="${TMP}/zeta/repo" MOCK_THETA="${TMP}/theta/repo" MOCK_DIR="${TMP}"
# zeta：主控卡在审批对话框（假 herdr 里 blocked）→「等你」里出现一条 STOP

# 任务区 —— eta：T8 进行中（1 个提交）；队列里一个手写未编号的排在最前；
# 已完成 T5（没有提交）、放弃 T6。theta：T3 做完、放行模式下还没放行，并且暂停中。其余项目没有 queue.md，不出现任务区。
E="${TMP}/eta"; EB=$(git -C "$E/repo" rev-parse HEAD~1); EH=$(git -C "$E/repo" rev-parse HEAD); ES=$(git -C "$E/repo" rev-parse --short HEAD)
printf '## T8 把 CSV 导入改成流式\n约束：内存不超过 200MB\n\n## 修一下登录页的超时\n流程：修好再审\n\n## T9 订单列表分页\n流程：不评审\n只动分页参数\n### 范围\n- 别碰 <b>旧接口</b> & 文档\n' > "$E/review/queue.md"
{ printf '{"t": %s, "ev": "start", "id": "T5", "title": "给导出加进度条", "body": "", "key": "给导出加进度条", "sha": "%s"}\n' "$((now - 9000))" "$EB"
  printf '{"t": %s, "ev": "done", "id": "T5", "sha": "%s", "gate": false}\n' "$((now - 7800))" "$EB"
  printf '{"t": %s, "ev": "start", "id": "T7", "title": "实验脚本换参数", "body": "流程: 不评审", "key": "实验脚本换参数", "sha": "%s"}\n' "$((now - 7790))" "$EB"
  printf '{"t": %s, "ev": "done", "id": "T7", "sha": "%s", "gate": false}\n' "$((now - 7750))" "$EH"
  printf '{"t": %s, "ev": "drop", "id": "T6", "title": "迁移到新日志库", "key": "迁移到新日志库", "reason": "和 T2 冲突"}\n' "$((now - 7700))"
  printf '{"t": %s, "ev": "start", "id": "T8", "title": "把 CSV 导入改成流式", "body": "约束：内存不超过 200MB", "key": "把 CSV 导入改成流式", "sha": "%s"}\n' "$((now - 3600))" "$EB"
} > "$E/review/tasks.state"
TH="${TMP}/theta"; THB=$(git -C "$TH/repo" rev-parse HEAD~1)
printf '## T3 补登录接口的回归测试\n\n## T4 清理旧的 feature flag\n' > "$TH/review/queue.md"
{ printf '{"t": %s, "ev": "start", "id": "T3", "title": "补登录接口的回归测试（带\\"引号\\"）", "body": "", "key": "补登录接口的回归测试（带\\"引号\\"）", "sha": "%s"}\n' "$((now - 2000))" "$THB"
  printf '{"t": %s, "ev": "done", "id": "T3", "sha": "%s", "gate": true}\n' "$((now - 100))" "$THB"
} > "$TH/review/tasks.state"
: > "$TH/review/paused"

printf '%s/alpha/repo\n%s/beta/repo\n%s/gamma/repo\n%s/delta/repo\n%s/epsilon/repo\n%s/zeta/repo\n%s/eta/repo\n%s/theta/repo\n# comment\n%s/nonexistent\n' "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" "${TMP}" > "${TMP}/projects"
HERDR_BIN_PATH="${TMP}/herdr" python3 "${BOARD}" --projects "${TMP}/projects" --out "${OUT}" >/dev/null

# 项目发现与去重命名（三个 checkout 都叫 repo，用上级目录区分）
for n in alpha beta gamma delta epsilon zeta eta theta; do has "data-p=\"$n/repo\"" "project $n listed"; done
has '项目 · 8' 'project count'
has '<div class="mast"><span class="brand">Review board</span>' 'masthead'
has '<b>主控</b> codex' 'masthead names the running 主控'

# 活动条：主控在干什么，来自 herdr agent list 的状态与标题，working 时再读 pane 最后那句
has '<span class="dot st-working"></span><b>写手</b><span class="st st-working">working</span><span class="activity">Working (12m 03s)</span>' 'alpha 主控 chip with activity'
# 按钮的样式名是 act、默认隐藏；agent 正在做什么的那段文字不能用同一个名字，否则被一起藏掉
lacks '<span class="act">' 'crew activity text is not styled as a hidden button'

# 横幅：zeta 的主控 blocked 一条 + theta 做完等放行一条
has '等你 · 2' 'banner count: zeta 1 + theta 1'
seen_plain=0
for c in $(grep -o 'class="proj[^"]*" data-p' "${OUT}" | sed 's/class="proj needs" data-p/needs/;s/class="proj" data-p/plain/'); do
  if [ "$c" = plain ]; then seen_plain=1; elif [ "${seen_plain}" = 1 ]; then fail 'a project that needs you sorted after a quiet one'; fi
done

# 评审协议的东西一律不该再出现
lacks 'Round 1' 'no review rounds'
lacks '暂缓清单' 'no backlog section'
lacks '最近归档' 'no archive section'
lacks '等你裁决' 'no pending decisions'
lacks 'request-review' 'no request-review anywhere on the page'

# 「等你」栏：每个项目一栏，横幅只是汇总
has 'id="w-zeta/repo"' 'zeta has its own 等你 section'
has '主控停在审批或提问对话框，去看 pane zeta-writer' 'blocked 主控 listed'
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
has 'review-task go' 'the waiting item says how to release'
has '运行 review-task next，按它的输出办' 'the waiting item says the sentence a fresh writer needs'
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
echo 'PASS review-board renders the queue, the banner and 主控 status; no review protocol left'

# 并发刷新：launchd 每 30 秒一次，request-review 退出时也刷一次，两者会同时跑。临时文件共用一个名字时，
# 后到的那个改名会扑空（2026-09-11 board.err 里有 3 次）。先用一个被占住的 board.html.tmp 把「共用固定名字」
# 确定地暴露出来，再真并发跑几次。
mkdir "${OUT}.tmp"
HERDR_BIN_PATH="${TMP}/herdr" python3 "${BOARD}" --projects "${TMP}/projects" --out "${OUT}" >/dev/null 2>"${TMP}/board.err" \
  || fail "board writes through a shared fixed temp name: $(tail -1 "${TMP}/board.err")"
rmdir "${OUT}.tmp"
pids=""
for i in 1 2 3 4; do
  HERDR_BIN_PATH="${TMP}/herdr" python3 "${BOARD}" --projects "${TMP}/projects" --out "${OUT}" >/dev/null 2>>"${TMP}/board.err" &
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
board() { HERDR_BIN_PATH="${TMP}/herdr" REVIEW_NOTIFY_BIN="$1" python3 "${BOARD}" --projects "${TMP}/projects" --out "${OUT}" "${@:2}" >/dev/null; }
nlines() { if [ -f "${TMP}/notify.log" ]; then wc -l < "${TMP}/notify.log" | tr -d ' '; else echo 0; fi; }
board "${TMP}/notifier"
[ "$(nlines)" = 0 ] || fail 'the board must not notify without --notify'
board "${TMP}/notifier" --notify
[ "$(nlines)" = 2 ] || fail "first --notify run: one per project waiting on you (zeta blocked, theta awaiting release), got $(nlines)"
grep -q 'zeta/repo' "${TMP}/notify.log" || fail 'the blocked 主控 is notified'
grep -q '做完了' "${TMP}/notify.log" || fail 'waiting for release is notified'
board "${TMP}/notifier" --notify
[ "$(nlines)" = 2 ] || fail 'an unchanged board must not notify again'
mv "${TMP}/theta/review/tasks.state" "${TMP}/theta/state.bak"
board "${TMP}/notifier" --notify
[ "$(nlines)" = 2 ] || fail 'an item going away sends nothing'
mv "${TMP}/theta/state.bak" "${TMP}/theta/review/tasks.state"
board "${TMP}/notifier" --notify
[ "$(nlines)" = 3 ] || fail 'an item that comes back is notified again'
tail -1 "${TMP}/notify.log" | grep -q '做完了' || fail 'the renewed notification carries the item text'
tail -1 "${TMP}/notify.log" | grep -qF '\"引号\"' || fail 'double quotes are escaped for AppleScript'
rm -f "${TMP}/board-notified.json"
board "${TMP}/no-such-notifier" --notify || fail 'a missing notifier must not break the board'
has 'Review board' 'page still written when notifications cannot be sent'
echo 'PASS 等你 notifications: only with --notify, once per project, again when an item returns, escaped, never fatal'

# ---- 本机服务：review-board serve。页面带令牌和按钮；放行、放弃转给 review-task；只认本机 Host / Origin 和令牌 ----
lacks '<meta name="rb-token"' 'the static board carries no token'
lacks 'data-act=' 'the static board carries no action buttons'
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
HERDR_BIN_PATH="${TMP}/herdr" python3 "${BOARD}" serve --projects "${TMP}/projects" --port "${PORT}" > /dev/null 2> "${TMP}/serve.err" &
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
tail -1 "${TMP}/eta/review/tasks.state" | grep -q '"ev": "drop", "id": "T9".*不需要了' || fail 'drop goes through review-task with the reason'
[ "$(post /api/go '{"project":"eta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'go refused when nothing waits for release'
[ "$(post /api/go '{"project":"theta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'release the finished task'; }
tail -1 "${TMP}/theta/review/tasks.state" | grep -q '"ev": "go", "id": "T3"' || fail 'go goes through review-task'
grep -q '继续' "${TMP}/resp" || fail 'go passes on what to tell the writer'
[ "$(curl -s "${U}/v")" != "${V1}" ] || fail 'the version changes after the queue state changes'
echo 'PASS review-board serve: token, local Host/Origin only, release and drop via review-task, in-progress task not droppable'

# ---- 页面上加任务：标题 + 流程 + 正文，经 review-task add 追加到队列末尾；顶格 ## 会被当成新任务，拒绝
grep -qF 'data-act="add" data-p="eta/repo"' "${TMP}/live.html" || fail 'add-task button on a board with a queue'
lacks 'data-act="add"' 'the static board has no add button'
EQ=$(cat "${TMP}/eta/review/queue.md")
[ "$(post /api/add '{"project":"eta/repo","title":"","body":"x"}' -H "X-RB-Token: ${TOKEN}")" = 400 ] || fail 'an empty title is refused'
[ "$(post /api/add '{"project":"eta/repo","title":"两行\n标题","body":""}' -H "X-RB-Token: ${TOKEN}")" = 400 ] || fail 'a multi-line title is refused'
[ "$(post /api/add '{"project":"eta/repo","title":"坏正文","body":"第一行\n## 这会变成新任务"}' -H "X-RB-Token: ${TOKEN}")" = 400 ] || fail 'a body line starting with ## is refused'
grep -q '###' "${TMP}/resp" || fail 'the refusal says to use ### instead'
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
echo 'PASS review-board serve: add a task from the page via review-task add; bad titles and ## body lines refused'

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
echo 'PASS review-board serve: reorder and edit pending tasks via review-task move / edit, guarded by the queue fingerprint'

# ---- 页面上暂停 / 恢复发新任务：标题栏按当前状态给「暂停发任务」或「恢复发任务」，经 review-task pause / resume
grep -qF 'data-act="pause" data-p="eta/repo"' "${TMP}/live.html" || fail 'pause button on a board that is not paused'
grep -qF 'data-act="resume" data-p="theta/repo"' "${TMP}/live.html" || fail 'resume button on a paused board'
grep -qF 'data-act="resume" data-p="eta/repo"' "${TMP}/live.html" && fail 'no resume button on a board that is not paused'
[ "$(post /api/pause '{"project":"eta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'pause from the page'; }
[ -f "${TMP}/eta/review/paused" ] || fail 'pause goes through review-task pause'
[ "$(post /api/pause '{"project":"eta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'pause refused when already paused (the page was stale)'
[ "$(post /api/resume '{"project":"theta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'resume from the page'; }
[ ! -f "${TMP}/theta/review/paused" ] || fail 'resume goes through review-task resume'
[ "$(post /api/resume '{"project":"theta/repo"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'resume refused when not paused'
rm -f "${TMP}/eta/review/paused"
echo 'PASS review-board serve: pause / resume from the page via review-task, refused when the page was stale'

# ---- 页面上放弃没编号的任务：放弃按钮带队列位置，和调整顺序一样带着指纹
curl -s "${U}/" > "${TMP}/live.html"
[ "$(epending)" = "普通任务|修一下登录页的超时（改）|导出支持按月分文件" ] || fail "eta pending before dropping by position: $(epending)"
grep -qF 'data-act="drop" data-p="eta/repo" data-id="" data-pos="2"' "${TMP}/live.html" || fail 'drop button on an unnumbered pending task'
QV=$(python3 -c 'import hashlib,sys; print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest()[:12])' "${TMP}/eta/review/queue.md")
[ "$(post /api/drop '{"project":"eta/repo","pos":2,"reason":"不做了","expect":"000000000000"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'a stale fingerprint refuses the drop'
[ "$(post /api/drop '{"project":"eta/repo","pos":2,"reason":"不做了","expect":"'"${QV}"'"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'drop an unnumbered task from the page'; }
[ "$(epending)" = "普通任务|导出支持按月分文件" ] || fail "dropped by position: $(epending)"
tail -1 "${TMP}/eta/review/tasks.state" | grep -q '"key": "修一下登录页的超时（改）".*不做了' || fail 'the page drop goes through review-task drop --pos'
echo 'PASS review-board serve: drop unnumbered pending tasks from the page by position, guarded by the queue fingerprint'

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
echo 'PASS review-board serve: view all finished tasks via GET /history (newest first, summary, queue text for never-started drops)'

# ---- 做完停：只在循环开着（或自动模式）时出现；按钮经 review-task hold 记进 tasks.state；任务上标「做完停」；关了循环就不显示
curl -s "${U}/" > "${TMP}/live.html"
grep -qF 'data-act="hold" data-p="eta/repo"' "${TMP}/live.html" && fail 'no hold toggle while every task already waits for release'
[ "$(post /api/loop '{"project":"eta/repo","on":true}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'loop on for eta'; }
curl -s "${U}/" > "${TMP}/live.html"
grep -qF 'data-act="hold" data-p="eta/repo" data-pos="1" data-on="0"' "${TMP}/live.html" || fail 'hold toggle on pending tasks while looping'
QV=$(python3 -c 'import hashlib,sys; print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest()[:12])' "${TMP}/eta/review/queue.md")
[ "$(post /api/hold '{"project":"eta/repo","pos":1,"on":true,"expect":"000000000000"}' -H "X-RB-Token: ${TOKEN}")" = 409 ] || fail 'a stale fingerprint refuses the hold'
[ "$(post /api/hold '{"project":"eta/repo","pos":1,"on":true,"expect":"'"${QV}"'"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || { cat "${TMP}/resp"; fail 'hold from the page'; }
tail -1 "${TMP}/eta/review/tasks.state" | grep -q '"ev": "hold".*"on": true' || fail 'the page hold goes through review-task hold'
curl -s "${U}/" > "${TMP}/live.html"
grep -qF '<span class="hold-tag">做完停</span>' "${TMP}/live.html" || fail 'a held task is marked on the board'
grep -qF 'data-act="hold" data-p="eta/repo" data-pos="1" data-on="1"' "${TMP}/live.html" || fail 'the toggle shows it is on'
[ "$(post /api/hold '{"project":"eta/repo","pos":1,"on":false,"expect":"'"${QV}"'"}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || fail 'unhold from the page'
[ "$(post /api/loop '{"project":"eta/repo","on":false}' -H "X-RB-Token: ${TOKEN}")" = 200 ] || fail 'loop off for eta'
echo 'PASS review-board serve: hold toggle only while looping, via review-task hold, marked on the board, guarded by the fingerprint'

# ---- 服务健康：/health 汇报本机服务（代码是否比服务新）、launchd 托管、看板定时生成、出错记录、herdr；页面顶栏有状态圆点
grep -qF 'class="hp"' "${TMP}/live.html" || fail 'the live masthead has the health pill'
lacks 'class="hp"' 'the static board has no health pill'
grep -qF 'class="golive"' "${TMP}/live.html" && fail 'the live board does not link to itself'
# 常驻服务要每次都用当前时间算「几分钟前」：模块里的 NOW 若停在启动那刻，页面上的时长会越来越偏
python3 - "${BOARD}" "${TMP}/projects" <<'PY2' || fail 'collect refreshes NOW for every page'
import importlib.machinery, importlib.util, os, sys, time
sys.dont_write_bytecode = True
os.environ["HERDR_BIN_PATH"] = "/nonexistent"
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1]); B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
B.NOW = 0
B.collect(sys.argv[2])
assert abs(B.NOW - time.time()) < 60, B.NOW
PY2
# 同理，herdr 的 agent 列表每页重查：常驻服务里缓存一次，主控的状态就永远停在服务启动那刻
HERDR_BIN_PATH="${TMP}/herdr" python3 - "${BOARD}" "${TMP}/projects" <<'PY2' || fail 'collect re-reads herdr agents for every page'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1]); B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
B._AGENTS = []                                                  # 假装上一页时 herdr 什么都没有
alpha = next(p for p in B.collect(sys.argv[2]) if p["name"] == "alpha/repo")
assert (alpha["agents"].get("writer") or {}).get("status") == "working", alpha["agents"]
PY2
mkdir -p "${TMP}/home/.drover" "${TMP}/hbin" "${TMP}/code"
cp "${BOARD}" "${TMP}/code/review-board"; cp "$(dirname "${BOARD}")/review-task" "${TMP}/code/review-task"
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
cat > "${TMP}/hbin/herdr" <<EOF
#!/usr/bin/env bash
[ -f "${TMP}/herdr.down" ] && exit 1
exec "${TMP}/herdr" "\$@"
EOF
chmod +x "${TMP}/hbin/launchctl" "${TMP}/hbin/herdr"
printf '[]\n' > "${TMP}/home/.drover/board-notified.json"
HP=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
HOME="${TMP}/home" REVIEW_LAUNCHCTL="${TMP}/hbin/launchctl" HERDR_BIN_PATH="${TMP}/hbin/herdr" REVIEW_LOOP_TICK=1 \
  python3 "${TMP}/code/review-board" serve --projects "${TMP}/projects" --port "${HP}" > /dev/null 2> "${TMP}/serve2.err" &
SERVE2=$!
trap 'kill "${SERVE}" "${SERVE2}" 2>/dev/null; rm -rf "${TMP}"' EXIT
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:${HP}/v" && break; sleep 0.1; done
health() {   # <期望的 level> <检查项名> <true|false> [detail 里应有的字]
  curl -s "http://127.0.0.1:${HP}/health" > "${TMP}/health.json" || { cat "${TMP}/serve2.err"; fail 'GET /health'; }
  python3 - "${TMP}/health.json" "$@" <<'PY2' || { cat "${TMP}/health.json"; fail "health: $*"; }
import json, sys
h = json.load(open(sys.argv[1], encoding="utf-8")); level, name, ok = sys.argv[2:5]; want = sys.argv[5] if len(sys.argv) > 5 else ""
names = [i["name"] for i in h["items"]]
assert names == ["本机服务", "服务守护（launchd）", "看板定时生成", "生成出错记录", "herdr"], names
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
: > "${TMP}/herdr.down"; health warn herdr false '连不上'; rm "${TMP}/herdr.down"
: > "${TMP}/serve.unloaded"; health warn '服务守护（launchd）' false '不会自动拉起'; rm "${TMP}/serve.unloaded"
: > "${TMP}/serve.other"; health warn '服务守护（launchd）' false '另一个进程'; rm "${TMP}/serve.other"
health ok '服务守护（launchd）' true '已由 launchd 托管'
grep -qF "document.body.classList.contains('offline')" "${TMP}/live.html" || fail 'no full-page refresh while the service is unreachable'
python3 -c 'import os,sys,time; t=time.time()+5; os.utime(sys.argv[1], (t, t))' "${TMP}/code/review-task"
health warn 本机服务 false '旧代码'
# ---- agent 状态随轮询更新：GET /crew 返回各项目的 agent 状态块，页面每 8 秒换上，不用等整页刷新
grep -qF 'data-crew="alpha/repo"' "${TMP}/live.html" || fail 'the live page has a crew slot per project'
curl -s "http://127.0.0.1:${HP}/crew" > "${TMP}/crew.json"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); assert "st-working" in c["alpha/repo"] and "Working (12m 03s)" in c["alpha/repo"], c' "${TMP}/crew.json" || { cat "${TMP}/crew.json"; fail 'crew shows the working writer'; }
: > "${TMP}/herdr.down"; sleep 3
curl -s "http://127.0.0.1:${HP}/crew" > "${TMP}/crew.json"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); assert "st-working" not in c["alpha/repo"], c' "${TMP}/crew.json" || { cat "${TMP}/crew.json"; fail 'crew follows herdr without a page reload'; }
rm "${TMP}/herdr.down"
echo 'PASS review-board serve: /health reports stale code, launchd, board refresh, recent errors and herdr; NOW and agents refreshed; crew polled'

# ---- 外层循环：页面开关；服务看到 .loop-wait 且条件满足（有待办、没暂停、不等放行）、写手空闲、pane 身份没变时，往写手 pane 输入那句话
curl -s "http://127.0.0.1:${HP}/" > "${TMP}/live2.html"
TOKEN2=$(sed -n 's/.*<meta name="rb-token" content="\([^"]*\)".*/\1/p' "${TMP}/live2.html")
grep -qF 'data-act="loop" data-p="theta/repo" data-on="0"' "${TMP}/live2.html" || fail 'loop switch (off) on the task board'
lpost() { curl -s -o "${TMP}/resp" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "X-RB-Token: ${TOKEN2}" --data "$2" "http://127.0.0.1:${HP}$1"; }
[ "$(lpost /api/loop '{"project":"theta/repo","on":true}')" = 200 ] || { cat "${TMP}/resp"; fail 'turn the loop on from the page'; }
[ -f "${TMP}/theta/review/loop" ] || fail 'the page switch goes through review-task loop on'
[ "$(lpost /api/loop '{"project":"theta/repo","on":true}')" = 409 ] || fail 'loop on refused when already on'
mark() { printf '{"reason": "empty", "pane": "theta-writer", "t": %s}\n' "$(date +%s)" > "${TMP}/theta/review/.loop-wait"; }
waitfor() { for _ in $(seq 40); do eval "$1" && return 0; sleep 0.25; done; return 1; }
rm -f "${TMP}/prompts.log"; mark
waitfor '[ -s "${TMP}/prompts.log" ]' || { cat "${TMP}/serve2.err"; fail 'the service wakes the idle writer when a task is pending'; }
grep -qx '运行 review-task next，按它的输出办' "${TMP}/prompts.log" || fail 'the wake prompt is the kickoff sentence'
waitfor '[ ! -f "${TMP}/theta/review/.loop-wait" ]' || fail 'the marker is cleared after a successful wake'
# 暂停中：不叫
rm -f "${TMP}/prompts.log"; : > "${TMP}/theta/review/paused"; mark; sleep 2.5
[ ! -s "${TMP}/prompts.log" ] || fail 'no wake while paused'
rm "${TMP}/theta/review/paused"
waitfor '[ -s "${TMP}/prompts.log" ]' || fail 'resuming lets the wake through'
waitfor '[ ! -f "${TMP}/theta/review/.loop-wait" ]' || fail 'the marker is cleared after the wake'
# 叫醒期间写手又停下、写了新标记：服务不能把新标记当旧的删掉（否则写手停着再没人叫）
HERDR_BIN_PATH="${TMP}/herdr" python3 - "${BOARD}" "${TMP}/projects" "${TMP}" <<'PY2' || fail 'a marker rewritten during the wake survives'
import importlib.machinery, importlib.util, json, os, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1]); B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
mf = os.path.join(sys.argv[3], "theta", "review", ".loop-wait")
open(os.path.join(sys.argv[3], "theta", "review", "loop"), "w").close()
json.dump({"reason": "empty", "pane": "theta-writer", "t": 1}, open(mf, "w"))
real_run = B.subprocess.run
def run(cmd, *a, **k):
    r = real_run(cmd, *a, **k)
    if cmd[1:3] == ["agent", "prompt"]:               # 注入的同时，写手又停下写了新标记
        json.dump({"reason": "empty", "pane": "theta-writer", "t": 2}, open(mf, "w"))
    return r
B.subprocess.run = run
B.HERDR = os.environ["HERDR_BIN_PATH"]
B.loop_tick(sys.argv[2])
assert os.path.exists(os.path.join(sys.argv[3], "prompts.log")), "the wake did not happen"
assert os.path.exists(mf) and json.load(open(mf))["t"] == 2, "new marker was deleted"
os.remove(mf)
PY2
# 写手在忙时先记下 pane 身份；身份变了（换了 terminal）就不叫，标成失败留给人
rm -f "${TMP}/prompts.log"; echo working > "${TMP}/theta.status"; mark
waitfor 'grep -q terminal "${TMP}/theta/review/.loop-wait"' || fail 'the service records the writer pane identity'
echo term_other > "${TMP}/theta.term"; echo idle > "${TMP}/theta.status"
waitfor 'grep -q "\"failed\": true" "${TMP}/theta/review/.loop-wait"' || { cat "${TMP}/theta/review/.loop-wait"; fail 'a changed pane identity is marked failed'; }
[ ! -s "${TMP}/prompts.log" ] || fail 'no wake into a pane whose identity changed'
curl -s "http://127.0.0.1:${HP}/" | grep -q '自动叫醒失败' || fail 'the task board says the wake failed'
rm -f "${TMP}/theta.term" "${TMP}/theta.status"
# 循环关：标记作废，不叫
[ "$(lpost /api/loop '{"project":"theta/repo","on":false}')" = 200 ] || fail 'turn the loop off from the page'
mark; sleep 2.5
[ ! -s "${TMP}/prompts.log" ] || fail 'no wake with the loop off'
echo 'PASS review-board serve: loop switch; wakes the idle writer when work is pending, not while paused, not into a changed pane, not with the loop off'

# ---- 浏览器冒烟：真开一个无头 Chrome 点一遍（抽屉、编辑框预览、放弃确认、查看全部、↓ 调整顺序、断开变红）。
# 放在最后：它最后会停掉 ${SERVE}。没有 node 或 Chrome 就跳过，不算失败。
if command -v node >/dev/null; then
  # 给冒烟测试准备一个「做完等放行」的任务：theta 领 T4、做完（没有提交，放行模式）
  rm -f "${TMP}/theta/review/loop" "${TMP}/theta/review/.loop-wait" "${TMP}/theta/review/paused"
  ( cd "${TMP}/theta/repo" && env -u HERDR_PANE_ID python3 "$(dirname "${BOARD}")/review-task" next >/dev/null && env -u HERDR_PANE_ID python3 "$(dirname "${BOARD}")/review-task" done T4 >/dev/null ) || true
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
