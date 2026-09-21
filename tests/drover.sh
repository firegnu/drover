#!/usr/bin/env bash
# drover 测试：队列归人（queue.md），进度归工具（tasks.state），「做完了」由工具只读核对。
# 造一个假仓库和交接目录 + 一个假 corral；drover 只用 send / status / ls，也不许写目标仓库一个字节。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RT=${DROVER_BIN:-${ROOT}/bin/drover}
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
REPO="${TMP}/repo"; D="${TMP}/review"
mkdir -p "${REPO}" "${D}" "${TMP}/bin"
git -C "${REPO}" init -q -b main
git -C "${REPO}" config user.name t; git -C "${REPO}" config user.email t@example.com
printf '.drover.conf\n' > "${REPO}/.gitignore"
printf 'a\n' > "${REPO}/a.py"
git -C "${REPO}" add .; git -C "${REPO}" commit -qm base
printf 'HANDOFF_DIR=%s\n' "${D}" > "${REPO}/.drover.conf"
# 假 corral：把 send 的收件人和正文记下来，退出码由 ${TMP}/corral.code 控制（默认 0 = 送达）。
# 只实现 send / status / ls 三个命令——drover 用到的就这三个（AGENTS.md 硬规矩）。
cat > "${TMP}/bin/corral" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "${TMP}/cmds"     # 记下用过哪些子命令，最后断言只用了 send / status / ls
case "\$1" in
  send)
    printf '%s\n' "\$2" >> "${TMP}/sent.to"
    printf '%s\n--8<--\n' "\$3" >> "${TMP}/sent.txt"
    c=\$(cat "${TMP}/corral.code" 2>/dev/null || true); [ -n "\$c" ] || c=0
    case "\$c" in
      0) printf '{"ok":true,"name":"%s","instance":1,"confirmed":true,"merged_with_draft":false}\n' "\$2";;
      7) printf '{"ok":false,"error":"not_idle","state":"working"}\n';;
      8) printf '{"ok":false,"error":"human_active"}\n';;
      3) printf '{"ok":false,"error":"not_delivered"}\n';;
      2) printf '{"ok":false,"error":"not_found"}\n';;
    esac
    exit "\$c";;
  status)
    s=\$(cat "${TMP}/corral.state" 2>/dev/null || echo idle)
    [ "\$s" = "gone" ] && { printf '{"ok":false,"error":"not_found"}\n'; exit 2; }
    printf '{"ok":true,"name":"%s","instance":1,"kind":"claude","state":"%s","title":"t","last_tool":"Edit","turn_started":%s,"last_input_source":"send"}\n' "\$2" "\$s" "\$(date +%s)"
    exit 0;;
  ls) printf '{"ok":true,"agents":[]}\n'; exit 0;;
esac
printf '{"ok":false,"error":"usage"}\n'; exit 1
EOF
chmod +x "${TMP}/bin/corral"
sent_to() { tail -1 "${TMP}/sent.to" 2>/dev/null; }
sent_txt() { awk 'BEGIN{RS="--8<--\n"} {b=$0} END{printf "%s", b}' "${TMP}/sent.txt" 2>/dev/null; }
# 大部分用例不配 MAIN_AGENT：next 就只把任务正文打出来（内循环全靠人手工做的项目照样能用）

fail() { echo "FAIL: $*" >&2; echo "--- 最后一次输出 ---" >&2; cat "${TMP}/out" >&2 || true; exit 1; }
rt() { set +e; ( cd "${REPO}" && DROVER_CORRAL_BIN="${TMP}/bin/corral" python3 "${RT}" "$@" ) > "${TMP}/out" 2>&1; RC=$?; set -e; }
has() { grep -qF -e "$1" "${TMP}/out" || fail "$2 (missing: $1)"; }
lacks() { grep -qF -e "$1" "${TMP}/out" && fail "$2 (unexpected: $1)"; return 0; }
code() { [ "${RC}" = "$1" ] || fail "$2: exit ${RC}, expected $1"; }
edit() { mkdir -p "$(dirname "${REPO}/$1")"; printf '%s\n' "$2" >> "${REPO}/$1"; git -C "${REPO}" add "$1"; git -C "${REPO}" commit -qm "$2"; }
hsha() { git -C "${REPO}" rev-parse HEAD; }
short() { git -C "${REPO}" rev-parse --short HEAD; }

# ---- 加任务：编号自增；手写的可以不带编号，写在哪一块前面就排在哪 ----
rt add "给导出加进度条"; code 0 'add'; has 'T1' 'add numbers from T1'
rt add "订单列表分页" "约束：不改接口签名"; code 0 'add with a note'; has 'T2' 'add numbers T2'
grep -qx '## T2 订单列表分页' "${D}/queue.md" || fail 'add writes a ## T<n> block'
grep -qx '约束：不改接口签名' "${D}/queue.md" || fail 'add writes the note under its block'
python3 - "${D}/queue.md" <<'PY'
import sys; p = sys.argv[1]; s = open(p, encoding='utf-8').read(); i = s.index('## T1')
open(p, 'w', encoding='utf-8').write(s[:i] + '## 修一下登录页的超时\n\n' + s[i:])
PY

# ---- next：发第一个没做的；给手写的补编号；记下开始时 main 的 sha ----
rt next; code 0 'next issues a task'
has 'TASK T3: 修一下登录页的超时' 'hand-written block goes first and is numbered after the highest ID'
# 送出去的是任务正文本身。里面绝不能有「运行 drover …」——那是内循环依赖外循环，
# 正是老 herdsman 注入 LOOP_PROMPT 的做法，ROADMAP 明确要求改掉。
grep -q 'drover' "${TMP}/out" && fail 'the task text must never tell the agent to run drover'
grep -q 'drover' "${TMP}/out" && fail 'the task text must not mention drover at all'
grep -q "$(hsha)" "${D}/tasks.state" || fail 'start sha recorded in tasks.state'
python3 -c 'import json,sys
e=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()]
s=[x for x in e if x["ev"]=="start"][-1]
assert s["main"] == sys.argv[2], (s, sys.argv[2])' "${D}/tasks.state" "$(git -C "${REPO}" rev-parse main)" \
  || fail 'the start event records main, not HEAD'
rt next; code 0 'next again'; has 'TASK T3: 修一下登录页的超时' 'next re-issues the in-progress task'
[ "$(grep -c '"ev": "start", "id": "T3"' "${D}/tasks.state")" = 1 ] || fail 're-issuing must not record a second start'

# ---- done：编号不对就拒绝；main 没前进就拒绝（判据第 1 条）；放行模式下停下等人 ----
rt done T1; code 2 'done for a task that is not in progress'
rt done T3; code 9 'main has not moved since the task was issued'; has '判据 1' 'names the criterion that failed'
edit login.py 'timeout fix'
# 老配置残留的键不报错，也不再影响第 2 条（旧逻辑会因匹配不到分支而拦住）。
printf 'BRANCH_GLOB=does-not-match-*\n' >> "${REPO}/.drover.conf"
rt done T3; code 8 'done in release mode stops the writer'; has '等人放行' 'release mode says wait for release'
has '✓ 1 main 前进了' 'the passing criteria are printed'
has '✓ 2 这次建的分支都合进去了：没有未合并的分支' 'no remaining branches pass criterion 2'
has '— 3 验收命令过了' 'a skipped criterion is shown as skipped, not as passed'
# 收尾记号是「依据」，三条判据是「门」。手动 drover done 是人自己的判断，不拦——但要把
# 没看到记号这件事说出来，免得人以为 drover 认出了完成。循环那条路见 tests/drover-board.sh。
has '✗ 依据 收尾记号' 'done reports the wrap-up mark as the basis, missing here'
has '这次算你自己判断的' 'and says plainly that this was the human deciding, not drover detecting'
rt next; code 8 'next before release'; has '等人放行' 'next refuses until released'
rt go; code 0 'go'
has 'drover next' 'go says how to send the next one'
rt go; code 2 'go when nothing waits for release'
rt next; code 0 'next after release'; has 'TASK T1: 给导出加进度条' 'the finished hand-written block is not issued again'

# ---- 以下用自动模式：done 通过就直接发下一个 ----
printf 'TASK_GATE=0\n' >> "${REPO}/.drover.conf"
edit a.py 'progress bar'
printf 'x\n' >> "${REPO}/a.py"; printf 'junk\n' > "${REPO}/scratch.txt"
rt done T1; code 9 'a dirty tracked file refuses done'; has '工作区' 'names the dirty tree'
git -C "${REPO}" checkout -q a.py
rt done T1; code 0 'a clean tree passes (untracked files do not count)'
has 'TASK T2: 订单列表分页' 'auto mode issues the next task'; has '约束：不改接口签名' 'the task body travels with the task'

# ---- 核对只看 git，不看任何评审痕迹 ----
edit a.py 'pagination'
rt done T2; code 8 'a committed change passes'; has '队列空了' 'queue empty after the last pending task'
rt add "清理旧的 feature flag"; rt next; code 0 'next T4'; has 'TASK T4' 'T4 issued'
edit flags.py 'drop old flag'
rt done T4; code 8 'T4 done'
rt add "补登录接口的回归测试"; rt next; has 'TASK T5' 'T5 issued'
edit a.py 'regression tests'
rt done T5; code 8 'T5 done'

# ---- 编了号的任务改标题后仍认得出；正在做的按开始时的原文重发 ----
rt add "订单导出去重"; rt next; has 'TASK T6: 订单导出去重' 'T6 issued'
sed -i '' 's/^## T6 订单导出去重$/## T6 订单导出去重（含历史数据）/' "${D}/queue.md"
rt next; code 0 'next after editing the title'; has 'TASK T6: 订单导出去重' 'in-progress task re-issued from its snapshot'
grep -q '含历史数据' "${TMP}/out" && fail 'an edited in-progress task must not change under the writer'
edit export.py 'dedupe'
rt done T6; code 8 'T6 done'; has '队列空了' 'an ID-matched edited task is not issued again'

# ---- 暂停、放弃、列表 ----
rt add "迁移到新日志库"
rt pause; code 0 'pause'; rt next; code 8 'paused refuses next'; has '暂停' 'says paused'
rt resume; code 0 'resume'; rt next; code 0 'next after resume'; has 'TASK T7' 'T7 issued'
rt drop T7 "和 T2 冲突"; code 0 'drop the current task'
rt next; code 8 'dropped task does not come back'; has '队列空了' 'queue empty after drop'
rt list; code 0 'list'
has '放弃' 'list shows dropped'; has '和 T2 冲突' 'list shows the drop reason'; has 'T5' 'list shows finished tasks'

# ---- drover 对目标仓库完全只读：跑完一整轮 add / next / done，仓库里一个字节都没变 ----
rt add "实验脚本换一组参数" "只改 exp.py"; rt next; code 0 'next T8'; has 'TASK T8' 'T8 issued'
edit exp.py 'lr 1e-4'
BEFORE=$(git -C "${REPO}" rev-parse HEAD)
rt done T8; code 8 'T8 done'
[ "$(git -C "${REPO}" rev-parse HEAD)" = "${BEFORE}" ] || fail 'done must not commit anything to the target repo'
[ -z "$(git -C "${REPO}" status --porcelain --untracked-files=no)" ] || fail 'done must not touch tracked files in the target repo'

# ---- 调整顺序、修改还没开始的任务：按队列里的位置认（没编号的也行）；--expect 对不上说明队列刚被改过，拒绝（退出码 10）
rt add "排序甲"; rt add "排序乙" "乙的说明"; rt add "排序丙"
printf '\n## 手写丁\n丁的说明\n' >> "${D}/queue.md"
qv() { python3 -c 'import hashlib,sys; print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest()[:12])' "${D}/queue.md"; }
pending() { python3 - "${RT}" <<'PY2'
import importlib.machinery, importlib.util, os, sys
sys.dont_write_bytecode = True
p = os.path.join(os.path.dirname(os.path.realpath(sys.argv[1])), "drover-board")
l = importlib.machinery.SourceFileLoader("rb", p); B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
q = open(os.environ["Q"], encoding="utf-8").read(); st = open(os.environ["S"], encoding="utf-8").read()
print("|".join(b["title"] for b in B.task_pending(B.task_blocks(q), B.task_fold(B.task_events(st))[0])))
PY2
}
export Q="${D}/queue.md" S="${D}/tasks.state"
[ "$(pending)" = "排序甲|排序乙|排序丙|手写丁" ] || fail "pending order before moving: $(pending)"
cp "${D}/queue.md" "${TMP}/q.before"
rt move 4 1 --expect 000000000000; code 10 'a stale --expect refuses the move'; has 'CONFLICT' 'says the queue changed'
cmp -s "${D}/queue.md" "${TMP}/q.before" || fail 'a refused move writes nothing'
rt move 4 1 --expect "$(qv)"; code 0 'move with a matching --expect'
[ "$(pending)" = "手写丁|排序甲|排序乙|排序丙" ] || fail "unnumbered task moved to the front: $(pending)"
grep -qx '## T1 给导出加进度条' "${D}/queue.md" || fail 'finished blocks stay in the file'
python3 - "${TMP}/q.before" "${D}/queue.md" <<'PY2' || fail 'moving changes only where the moved block sits'
import re, sys
a, b = (open(x, encoding="utf-8").read() for x in sys.argv[1:])
blk = "## 手写丁\n丁的说明\n"
assert blk in a and blk in b
norm = lambda x: re.sub(r"\n{2,}", "\n\n", x.replace(blk, "")).strip()   # 块之间的空行多少不算改动
assert norm(a) == norm(b), (norm(a), norm(b))
assert b.index(blk) < b.index("## T9 排序甲")
PY2
rt move 2 4; code 0 'move without --expect'
[ "$(pending)" = "手写丁|排序乙|排序丙|排序甲" ] || fail "move down: $(pending)"
rt move 9 1; code 2 'a position past the queue'
rt edit 2 "排序乙（改）" "新说明" --expect "$(qv)"; code 0 'edit a pending task'
grep -q '^## T10 排序乙（改）$' "${D}/queue.md" || fail 'edit keeps the ID and changes the title'
python3 - "${D}/queue.md" <<'PY2' || fail 'edit replaces the whole block'
import sys; q = open(sys.argv[1], encoding="utf-8").read()
i = q.index("## T10 排序乙（改）"); j = q.find("\n## ", i + 1)
assert q[i:j if j > 0 else None].strip() == "## T10 排序乙（改）\n新说明", repr(q[i:j])
assert "乙的说明" not in q
PY2
QB=$(cat "${D}/queue.md")
rt edit 1 "手写丁" "## 坏行"; code 2 'edit refuses a body line starting with ##'
rt edit 1 "" "x"; code 2 'edit refuses an empty title'
rt edit 1 "丁" --expect 000000000000; code 10 'a stale --expect refuses the edit'
[ "$(cat "${D}/queue.md")" = "${QB}" ] || fail 'refused edits write nothing'
rt edit 1 "手写丁（改）" "丁的新说明"; code 0 'edit an unnumbered task by position'
grep -qx '## 手写丁（改）' "${D}/queue.md" || fail 'an unnumbered task stays unnumbered'
# ---- 按位置放弃还没开始的任务：没编号的也行（编号记进 tasks.state、按标题认），有编号的照原来的放弃；--expect 同样防冲突
printf '\n## 手写戊\n戊的说明\n' >> "${D}/queue.md"
[ "$(pending)" = "手写丁（改）|排序乙（改）|排序丙|排序甲|手写戊" ] || fail "pending before dropping by position: $(pending)"
rt drop --pos 5 "不要了" --expect 000000000000; code 10 'a stale --expect refuses the drop'
[ "$(pending)" = "手写丁（改）|排序乙（改）|排序丙|排序甲|手写戊" ] || fail 'a refused drop changes nothing'
rt drop --pos 5 "不要了" --expect "$(qv)"; code 0 'drop an unnumbered task by position'; has '手写戊' 'says which task was dropped'
[ "$(pending)" = "手写丁（改）|排序乙（改）|排序丙|排序甲" ] || fail "the unnumbered task is no longer pending: $(pending)"
tail -1 "${D}/tasks.state" | grep -q '"ev": "drop".*"key": "手写戊".*"reason": "不要了"' || fail 'the drop is recorded with its title as key'
grep -qx '## 手写戊' "${D}/queue.md" || fail 'the queue text is left as it was'
rt drop --pos 3 "丙也不要"; code 0 'drop a numbered task by position'
tail -1 "${D}/tasks.state" | grep -q '"ev": "drop", "id": "T11"' || fail 'a numbered task is dropped under its own ID'
[ "$(pending)" = "手写丁（改）|排序乙（改）|排序甲" ] || fail "after dropping T11: $(pending)"
rt drop --pos 9 "x"; code 2 'a position past the queue'
rt list; has '手写戊' 'list shows the dropped unnumbered task'
rt next; code 0 'next after reordering'; has '手写丁（改）' 'next issues the task now at the front'

# ---- 外层循环：loop 文件在交接目录，默认没有 = 关。三档：关 / 开着但放行模式（自动核对、下一件等人）/
# 开着且自动模式（做完直接发下一件）。停在队列那一步（队列空 / 暂停 / 主控在忙）时留下 .loop-wait，
# 条件满足后由看板服务再跑一次 next
[ ! -f "${D}/loop" ] || fail 'the loop is off by default'
TID=$(sed -n 's/^TASK \(T[0-9]*\):.*/\1/p' "${TMP}/out")
grep -v '^TASK_GATE=' "${REPO}/.drover.conf" > "${TMP}/conf" && cp "${TMP}/conf" "${REPO}/.drover.conf"   # 回到放行模式
rt loop on; code 0 'loop on'; [ -f "${D}/loop" ] || fail 'loop on creates the loop file'
rt list; has '循环' 'list shows the loop is on'

# 中间档：循环开着 + 放行模式。自动核对判据、自动记 done，但下一件等人放行——TASK_GATE 不再被循环旁路
edit loop.py 'work for the looping task'
rt done "${TID}"; code 8 'loop on + release mode: done stops for release'; has '放行模式' 'says it is waiting for release, not that a mark was set'
grep -q '"ev": "done".*"gate": true' "${D}/tasks.state" || fail 'the done event is gated in release mode even while looping'
python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); assert m["reason"]=="release", m' "${D}/.loop-wait" || fail 'the wake marker says release'
rt next; code 8 'the loop does not issue while awaiting release'
rt go; code 0 'go releases'
rt next; code 0 'next issues after release'; has 'TASK ' 'the next task goes out'
TID=$(sed -n 's/^TASK \(T[0-9]*\):.*/\1/p' "${TMP}/out")

# 自动档：TASK_GATE=0，做完直接发下一件
printf 'TASK_GATE=0\n' >> "${REPO}/.drover.conf"
edit loop.py 'work for the auto task'
rt done "${TID}"; code 0 'loop on + auto mode: done issues the next task'; has 'TASK ' 'the next task follows right away'
grep -q '"ev": "done".*"gate": false' "${D}/tasks.state" || fail 'the done event is not gated in auto mode'
n=0
while grep -q '^TASK ' "${TMP}/out"; do
  n=$((n + 1)); edit loop.py "work ${n}"          # 每个任务都要让 main 前进，否则判据第 1 条不过
  TID=$(sed -n 's/^TASK \(T[0-9]*\):.*/\1/p' "${TMP}/out"); rt done "${TID}"
done
code 8 'the loop runs until the queue is empty'; has '队列空了' 'says the queue is empty'
# 标记里只有原因和时间：送给谁看配置的 MAIN_AGENT，不再记 pane，也不再核对 pane 身份
python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); assert m["reason"]=="empty" and m["t"] and "pane" not in m, m' "${D}/.loop-wait" || fail 'the wake marker records the reason only'
rt_pane() { rt "$@"; }        # 老的「在不在写手窗格里」没有意义了：drover 只在 drover 这边跑
rt_pane next; code 8 'empty queue stops'
has '自动接着往下发' 'says the loop will pick it up again'
rt add "循环里新加的任务"; rt pause
rt_pane next; code 8 'paused stops'
python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); assert m["reason"]=="paused", m' "${D}/.loop-wait" || fail 'the marker says paused'
rt resume; rt_pane next; code 0 'next after resume'; has '循环里新加的任务' 'the new task is issued'
TID=$(sed -n 's/^TASK \(T[0-9]*\):.*/\1/p' "${TMP}/out")
[ ! -f "${D}/.loop-wait" ] || fail 'issuing a task clears the wake marker'
grep -v '^TASK_GATE=' "${REPO}/.drover.conf" > "${TMP}/conf" && cp "${TMP}/conf" "${REPO}/.drover.conf"   # 回到放行模式
rt loop off; code 0 'loop off'; [ ! -f "${D}/loop" ] || fail 'loop off removes the loop file'
edit loop.py 'work for the last task'
rt done "${TID}"; code 8 'with the loop off, release mode stops again'; has '等人放行' 'back to waiting for release'
rt_pane next; code 8 'waiting for release'
[ ! -f "${D}/.loop-wait" ] || fail 'no wake marker when the loop is off'
rt go

# ---- 做完停：给队列里还没开始的任务打标记（记进 tasks.state，不改 queue.md），循环里做完它就停下等放行，放行后接着转；
# 正文里手写一行「做完：等我放行」效果一样（给 agent 建任务用）
# 这一段用自动模式（TASK_GATE=0）：放行模式下本来每件都停，看不出标记起没起作用
rt loop on
printf 'TASK_GATE=0\n' >> "${REPO}/.drover.conf"
rt add "做完要看一眼的甲"; rt add "甲之后的乙"
QB=$(cat "${D}/queue.md")
rt hold 1 on --expect 000000000000; code 10 'a stale --expect refuses the hold'
rt hold 1 on --expect "$(qv)"; code 0 'hold the first pending task'
[ "$(cat "${D}/queue.md")" = "${QB}" ] || fail 'hold does not touch queue.md'
tail -1 "${D}/tasks.state" | grep -q '"ev": "hold".*"on": true' || fail 'the hold is recorded in tasks.state'
rt hold 9 on; code 2 'hold a position past the queue'
rt_pane next; code 0 'next issues the held task'; has '做完要看一眼的甲' 'the held task'
# 「做完停」是 drover 自己的事，不写进送出去的正文：主控不需要知道有 drover 这个东西
grep -q '做完后会停下' "${TMP}/out" && fail 'the hold must not leak into the task text'
TID=$(sed -n 's/^TASK \(T[0-9]*\):.*/\1/p' "${TMP}/out")
edit hold.py 'work for the held task'
rt_pane done "${TID}"; code 8 'a held task stops after done even while looping'; has '等人放行' 'waits for release'
python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); assert m["reason"]=="release", m' "${D}/.loop-wait" || fail 'the wake marker says release'
rt go; rt_pane next; code 0 'released: the loop goes on'; has '甲之后的乙' 'the next task'
TID=$(sed -n 's/^TASK \(T[0-9]*\):.*/\1/p' "${TMP}/out")
edit hold.py 'work for the unheld task'
rt_pane done "${TID}"; code 8 'an unheld task continues'; has '队列空了' 'straight to the next (empty) step'
rt add "正文里写了的丙" "做完：等我放行"; rt_pane next; TID=$(sed -n 's/^TASK \(T[0-9]*\):.*/\1/p' "${TMP}/out")
edit hold.py 'work for the written-line task'
rt_pane done "${TID}"; code 8 'a task with the written line stops'; has '等人放行' 'waits for release'
rt go
rt add "打了又撤的丁"; rt hold 1 on; rt hold 1 off; code 0 'unhold'
rt_pane next; TID=$(sed -n 's/^TASK \(T[0-9]*\):.*/\1/p' "${TMP}/out"); grep -q '做完后会停下' "${TMP}/out" && fail 'an unheld task has no stop note'
edit hold.py 'work for the unheld-again task'
rt_pane done "${TID}"; code 8 'unheld task continues to the empty queue'; has '队列空了' 'continues'
rt loop off

# ---- 验收命令只有一个来源：.drover.conf 的 CHECK_CMD。
#      队列正文里写什么都不当命令跑——「验收：<命令>」那条语法 2026-09-21 删了，
#      理由：queue.md 的帮助说「下面随意写约束和验收」，而那行会被当 shell 跑，两句话不能同时成立。
printf 'CHECK_CMD=true\n' >> "${REPO}/.drover.conf"
rt add "正文里写了验收字样的任务" "验收：test -f no-such-file"; rt next
TID=$(sed -n 's/^TASK \(T[0-9]*\):.*/\1/p' "${TMP}/out")
edit acc.py 'work'
rt done "${TID}"; code 8 'a 验收 line in the body is prose, not a command'
has '✓ 3 验收命令过了' 'CHECK_CMD ran, not the text from the body'
lacks 'no-such-file' 'the body text never reached the shell'
rt add "用默认验收命令的任务"; rt next
TID=$(sed -n 's/^TASK \(T[0-9]*\):.*/\1/p' "${TMP}/out")
edit acc.py 'more work'
rt done "${TID}"; code 8 'without the line it falls back to CHECK_CMD'
has '✓ 3 验收命令过了' 'the default check ran and passed'
grep -v '^CHECK_CMD=' "${REPO}/.drover.conf" > "${TMP}/conf" && cp "${TMP}/conf" "${REPO}/.drover.conf"

# ---- 配上 MAIN_AGENT：next 真的把任务正文送进主控（corral send）----
printf 'MAIN_AGENT=owlet/main\n' >> "${REPO}/.drover.conf"
: > "${TMP}/sent.to"; : > "${TMP}/sent.txt"; printf '0\n' > "${TMP}/corral.code"
rt go || true                      # 上一块结束时可能还有一件在等放行
rt add "送出去的任务" "范围：只动 a.py"; rt next; code 0 'next sends the task'
[ "$(sent_to)" = "owlet/main" ] || fail "sent to the wrong agent: $(sent_to)"
sent_txt | grep -q '范围：只动 a.py' || fail 'the body travels with the task'
sent_txt | grep -q 'drover' && fail 'the sent text must never mention drover'
has '已送给 owlet/main' 'next reports where it went'
TID=$(sed -n 's/^TASK \(T[0-9]*\):.*/\1/p' "${D}/../out" 2>/dev/null || true)
TID=$(python3 -c 'import json,sys
e=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()]
print([x for x in e if x["ev"]=="start"][-1]["id"])' "${D}/tasks.state")
edit sendtest.py 'work'; rt done "${TID}"; rt go

# 送不出去时一个字都不能写：主控在忙 / 有人在打字 / 主控不在，队列必须原样不动
rt add "送不出去的任务"
for c in 7 8 2; do
  printf '%s\n' "$c" > "${TMP}/corral.code"
  rt next; code 8 "corral send exit ${c} stops instead of pretending it was issued"
  python3 -c 'import json,sys
e=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()]
assert not [x for x in e if x["ev"]=="start" and x.get("title")=="送不出去的任务"], "recorded a start for a task that was never delivered"' \
    "${D}/tasks.state" || fail "exit ${c}: a refused send must not record a start"
done
printf '7\n' > "${TMP}/corral.code"; rt next; has '不是 idle' 'exit 7 explains the 主控 is busy'
printf '8\n' > "${TMP}/corral.code"; rt next; has '有人在' 'exit 8 explains a human is typing'
printf '2\n' > "${TMP}/corral.code"; rt next; has '不会替你开它' 'exit 2 says drover will not start the 主控'
# 送了但没确认（退出码 3）：契约说不要重送，所以照样记开始，但要显眼地报出来
printf '3\n' > "${TMP}/corral.code"
rt next; code 8 'exit 3 is reported, not silently retried'; has '没确认送达' 'says the delivery was not confirmed'
python3 -c 'import json,sys
e=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()]
assert [x for x in e if x["ev"]=="start" and x.get("title")=="送不出去的任务"], "exit 3 must still record the start so it is not re-sent"' \
  "${D}/tasks.state" || fail 'exit 3 records the start'
printf '0\n' > "${TMP}/corral.code"
grep -v '^MAIN_AGENT=' "${REPO}/.drover.conf" > "${TMP}/conf" && cp "${TMP}/conf" "${REPO}/.drover.conf"

# ---- docs/queue-example.md 本身是合法的队列：四个任务 ----
python3 - "${ROOT}/bin/drover-board" "${ROOT}/docs/queue-example.md" <<'PY' || fail 'docs/queue-example.md drifted from the queue format'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", loader)); loader.exec_module(B)
blocks = B.task_blocks(open(sys.argv[2], encoding="utf-8").read())
assert [b["id"] for b in blocks] == ["T21", "T22", "T23", "T24"], [b["id"] for b in blocks]
assert "不走规划" in blocks[1]["body"] and "不走规划" in blocks[2]["body"]
PY

# 只许用 send / status / ls 三个 corral 命令（AGENTS.md 硬规矩），别的一个都不许出现
grep -vE '^(send|status|ls)$' "${TMP}/cmds" 2>/dev/null | grep -q . && { cat "${TMP}/cmds"; fail 'drover used a corral command outside send / status / ls'; }
echo 'PASS drover queue, release gate, read-only done check, pause and drop'

# ---- drover init：把一个新仓库接上。幂等；只写 .drover.conf + .gitignore + ~/.drover 下两处 ----
NEW="${TMP}/fresh"; mkdir -p "${NEW}"
git -C "${NEW}" init -q -b main
git -C "${NEW}" config user.name t; git -C "${NEW}" config user.email t@example.com
git -C "${NEW}" commit -q --allow-empty -m base
H2="${TMP}/home2"; mkdir -p "${H2}"
ini() { set +e; ( cd "${NEW}" && HOME="${H2}" python3 "${RT}" "$@" ) > "${TMP}/out" 2>&1; RC=$?; set -e; }
ini init 'Bad Name'; code 2 'init refuses a short name with spaces and capitals'
ini init inksample; code 0 'init'
[ -f "${NEW}/.drover.conf" ] || fail 'init writes .drover.conf'
if grep -q 'BRANCH_GLOB' "${NEW}/.drover.conf"; then fail 'init must not emit the removed branch setting'; fi
grep -qx '.drover.conf' "${NEW}/.gitignore" || fail 'init keeps the conf out of git'
# 登记的是 git 给的仓库根（macOS 上 /var 是 /private/var 的软链，两边写法不同）
python3 -c 'import os,sys
want = os.path.realpath(sys.argv[1])
got = [os.path.realpath(l.strip()) for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
assert want in got, (want, got)' "${NEW}" "${H2}/.drover/projects" || fail 'init registers the repo in the project list'
[ -d "${H2}/.drover/inksample" ] || fail 'init creates the handoff dir'
grep -q '^MAIN_AGENT=$' "${NEW}/.drover.conf" || fail 'MAIN_AGENT starts empty for the human to fill in'
grep -q '^DONE_MARK=收尾$' "${NEW}/.drover.conf" || fail 'DONE_MARK gets a default the project can change'
# 收尾记号要在项目自己的 AGENTS.md 里也写一遍（给主控看的那一份）。init 是唯一知道该提醒的时机，
# 所以它把那一行原样打出来让人贴——模板只管新项目，已有的项目全靠这一步。
has 'AGENTS.md' 'init tells you to add the wrap-up line to the project AGENTS.md'
has '收尾记号：' 'and prints the line itself, ready to paste'
has 'git commit --allow-empty' 'the printed line carries the command'
# 目标仓库里除了那两个文件，一个字节都没动
[ "$(git -C "${NEW}" status --porcelain | wc -l | tr -d ' ')" = 1 ] || { git -C "${NEW}" status --porcelain; fail 'init touched more than .gitignore'; }
# 幂等：再跑一次什么都不覆盖
cp "${NEW}/.drover.conf" "${TMP}/conf.before"
ini init inksample; code 0 'init again'
cmp -s "${NEW}/.drover.conf" "${TMP}/conf.before" || fail 'a second init must not overwrite the conf'
[ "$(grep -c . "${H2}/.drover/projects")" = 1 ] || fail 'a second init must not register the repo twice'
# 没接过的仓库上跑别的子命令 → 说清楚要先 init
rm -f "${NEW}/.drover.conf"; ini list; code 2 'a repo without .drover.conf is refused'
has '还没接入 drover' 'and says so'
echo 'PASS drover init: idempotent, registers the repo, leaves the target repo alone'
