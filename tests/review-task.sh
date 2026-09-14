#!/usr/bin/env bash
# review-task 测试：队列归人（queue.md），进度归工具（tasks.state），「做完了」由工具只读核对。
# 造一个假仓库和交接目录，把 request-review 会留下的文件手工摆出来；review-task 不许碰 herdr。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RT=${REVIEW_TASK_BIN:-${ROOT}/bin/review-task}
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
REPO="${TMP}/repo"; D="${TMP}/review"
mkdir -p "${REPO}" "${D}" "${TMP}/bin"
git -C "${REPO}" init -q -b main
git -C "${REPO}" config user.name t; git -C "${REPO}" config user.email t@example.com
printf '.review.conf\n' > "${REPO}/.gitignore"
printf 'a\n' > "${REPO}/a.py"
git -C "${REPO}" add .; git -C "${REPO}" commit -qm base
printf 'REVIEW_KIND=claude\nREVIEW_WT=%s\nREVIEW_DIR=%s\n' "${REPO}" "${D}" > "${REPO}/.review.conf"
# 假 herdr：只记录被调用过，好在最后断言 review-task 从没碰过它
printf '#!/usr/bin/env bash\necho "$*" >> "%s/herdr.log"\nexit 1\n' "${TMP}" > "${TMP}/bin/herdr"; chmod +x "${TMP}/bin/herdr"

fail() { echo "FAIL: $*" >&2; echo "--- 最后一次输出 ---" >&2; cat "${TMP}/out" >&2 || true; exit 1; }
rt() { set +e; ( cd "${REPO}" && PATH="${TMP}/bin:${PATH}" python3 "${RT}" "$@" ) > "${TMP}/out" 2>&1; RC=$?; set -e; }
has() { grep -qF -e "$1" "${TMP}/out" || fail "$2 (missing: $1)"; }
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

# ---- next：发第一个没做的；给手写的补编号；记下开始的 sha；任务文本自带交差办法 ----
rt next; code 0 'next issues a task'
has 'TASK T3: 修一下登录页的超时' 'hand-written block goes first and is numbered after the highest ID'
has 'review-task done T3' 'the task text says how to report done'
grep -q "$(hsha)" "${D}/tasks.state" || fail 'start sha recorded in tasks.state'
rt next; code 0 'next again'; has 'TASK T3: 修一下登录页的超时' 'next re-issues the in-progress task so a fresh writer can take over'

# ---- done：编号不对就拒绝；没有提交的任务直接通过；放行模式下停下等人 ----
rt done T1; code 2 'done for a task that is not in progress'
rt done T3; code 8 'done in release mode stops the writer'; has '等人放行' 'release mode says wait for release'
rt next; code 8 'next before release'; has '等人放行' 'next refuses until released'
rt go; code 0 'go'
has '运行 review-task next，按它的输出办' 'go says the sentence a fresh writer needs'
rt go; code 2 'go when nothing waits for release'
rt next; code 0 'next after release'; has 'TASK T1: 给导出加进度条' 'the finished hand-written block is not issued again'

# ---- 以下用自动模式：done 通过就直接发下一个 ----
printf 'TASK_GATE=0\n' >> "${REPO}/.review.conf"
edit a.py 'progress bar'
rt done T1; code 9 'unrouted commits refuse done'; has 'request-review' 'says the commits have not been routed'
printf 'x\n' >> "${REPO}/a.py"; printf 'junk\n' > "${REPO}/scratch.txt"
rt done T1; code 9 'a dirty tracked file refuses done'; has '工作区' 'names the dirty tree'
git -C "${REPO}" checkout -q a.py
printf '%s\nSKIP\n纯文本\ncode\n\nreview\n' "$(hsha)" > "${D}/.triage"
rt done T1; code 0 'triage SKIP at HEAD passes (untracked files do not count)'
has 'TASK T2: 订单列表分页' 'auto mode issues the next task'; has '约束：不改接口签名' 'the task body travels with the task'

# ---- 评审周期还没结束 → 拒绝；闭合在 HEAD → 通过 ----
edit a.py 'pagination'
H=$(hsha); B=$(git -C "${REPO}" rev-parse HEAD~1)
printf 'artifact: a.py\nkind: code\nbase sha: %s\ntarget sha: %s\nround: 1/3\n' "$B" "$H" > "${D}/request.md"
rt done T2; code 9 'request written but not dispatched'
printf '%s\n%s\nrv-pane\n' "$(date +%s)" "$H" > "${D}/.r1.sent"
rt done T2; code 9 'review still running'
printf 'F1 | should\nclaim: x\nevidence: a.py:1\n\nREVIEW-COMPLETE\n' > "${D}/r1-findings.md"
rt done T2; code 9 'findings not answered yet'
printf 'F1 accept — 改\n' > "${D}/r1-responses.md"
rt done T2; code 9 'an accepted finding still needs another round'
printf 'F1 reject — 不同意\n' > "${D}/r1-responses.md"
rt done T2; code 9 'a reject waits for the human'
printf 'F1 | blocking\nclaim: x\nevidence: a.py:1\n\nREVIEW-COMPLETE\n' > "${D}/r1-findings.md"; printf 'F1 defer — 下轮\n' > "${D}/r1-responses.md"
rt done T2; code 9 'a deferred blocking finding waits for the human'
printf 'F1 | should\nclaim: x\nevidence: a.py:1\n\nREVIEW-COMPLETE\n' > "${D}/r1-findings.md"; printf 'F1 defer — 以后\n' > "${D}/r1-responses.md"
rt done T2; code 8 'a cycle closed at HEAD passes'; has '队列空了' 'queue empty after the last pending task'

# ---- 规划者没交付 → 拒绝；开始之后只有评审记录的提交 → 当作过了路由 ----
rt add "清理旧的 feature flag"; rt next; code 0 'next T4'; has 'TASK T4' 'T4 issued'
printf '%s\nfp\npl-pane\n\n\n%s\n' "$(date +%s)" "$(hsha)" > "${D}/.plan.sent"
rt done T4; code 9 'planner has not delivered'
printf 'DIRECT\n边界：只删 flag\nPLAN-COMPLETE\n' > "${D}/plan.md"
edit docs/reviews/timing.md '2026-09-11 | abc1234 | round 1/3 | 60s | code'
rt done T4; code 8 'records-only commits since start count as routed'

# ---- 人用 SKIP_REVIEW 放过的提交不算没审 ----
rt add "补登录接口的回归测试"; rt next; has 'TASK T5' 'T5 issued'
edit a.py 'regression tests'
edit docs/reviews/skipped.md "2026-09-11 | $(short) | 人工免审"
rt done T5; code 8 'commits the human waived count as routed'

# ---- 编了号的任务改标题后仍认得出；正在做的按开始时的原文重发 ----
rt add "订单导出去重"; rt next; has 'TASK T6: 订单导出去重' 'T6 issued'
sed -i '' 's/^## T6 订单导出去重$/## T6 订单导出去重（含历史数据）/' "${D}/queue.md"
rt next; code 0 'next after editing the title'; has 'TASK T6: 订单导出去重' 'in-progress task re-issued from its snapshot'
grep -q '含历史数据' "${TMP}/out" && fail 'an edited in-progress task must not change under the writer'
printf '%s\nSKIP\n-\ncode\n\nreview\n' "$(hsha)" > "${D}/.triage"
rt done T6; code 8 'T6 done'; has '队列空了' 'an ID-matched edited task is not issued again'

# ---- 暂停、放弃、列表 ----
rt add "迁移到新日志库"
rt pause; code 0 'pause'; rt next; code 8 'paused refuses next'; has '暂停' 'says paused'
rt resume; code 0 'resume'; rt next; code 0 'next after resume'; has 'TASK T7' 'T7 issued'
rt drop T7 "和 T2 冲突"; code 0 'drop the current task'
rt next; code 8 'dropped task does not come back'; has '队列空了' 'queue empty after drop'
rt list; code 0 'list'
has '放弃' 'list shows dropped'; has '和 T2 冲突' 'list shows the drop reason'; has 'T5' 'list shows finished tasks'

# ---- 流程：不评审 → 发任务时交代写手不找规划者、不送审；done 把起点以来该审的提交登记进 skipped.md 后通过 ----
rt add "实验脚本换一组参数" "流程：不评审" "只改 exp.py"; rt next; code 0 'next T8'; has 'TASK T8' 'T8 issued'
has '不找规划者' 'a no-review task tells the writer to skip the planner'; has '不运行 request-review' 'and to skip request-review'
edit exp.py 'lr 1e-4'; S1=$(short)
edit docs/reviews/timing.md '2026-09-12 | abc1234 | round 1/3 | 60s | code'
edit exp.py 'lr 3e-4'; S2=$(short)
printf 'x\n' >> "${REPO}/exp.py"
rt done T8; code 9 'a no-review task still needs a clean tree'
grep -qF "| ${S1} |" "${REPO}/docs/reviews/skipped.md" && fail 'nothing is waived before the other checks pass'
git -C "${REPO}" checkout -q exp.py
rt done T8; code 8 'a no-review task passes without routing'; has '登记' 'done says the commits were waived'
grep -qF "| ${S1} | 任务 T8 人指定不评审" "${REPO}/docs/reviews/skipped.md" || fail 'first commit waived with the task as reason'
grep -qF "| ${S2} | 任务 T8 人指定不评审" "${REPO}/docs/reviews/skipped.md" || fail 'second commit waived'
[ "$(grep -c '任务 T8' "${REPO}/docs/reviews/skipped.md")" = 2 ] || fail 'records-only commits are not waived'
# request-review 的 range_files 用这条 awk 读 skipped.md：读得出来，之后的评审范围就不再含这两个提交
awk -F' [|] ' '{print $2}' "${REPO}/docs/reviews/skipped.md" | tr -d ' ' | grep -qx "${S2}" || fail 'waived lines parse the way request-review reads them'
rt add "正常流程的任务"; rt next; has 'TASK T9' 'T9 issued'
grep -qF '不找规划者' "${TMP}/out" && fail 'a normal task carries no no-review instruction'
edit exp.py 'normal change'
rt done T9; code 9 'a normal task still needs routing'
printf '%s\nSKIP\n-\ncode\n\nreview\n' "$(hsha)" > "${D}/.triage"
rt done T9; code 8 'T9 done'

# ---- 流程：修好再审 → 发任务时交代中间提交不送审、修好后送审一次；done 照常要求过路由，不登记豁免 ----
rt add "修复导出偶发崩溃" "流程: 修好再审"; rt next; has 'TASK T10' 'T10 issued'
has '修好之前' 'a review-last task tells the writer not to request review while iterating'; has '修好后运行一次 request-review' 'and to request review once when fixed'
grep -qF '不找规划者' "${TMP}/out" && fail 'a review-last task does not skip the planner'
edit exp.py 'try 1'; edit exp.py 'try 2'; edit exp.py 'fixed'
rt done T10; code 9 'a review-last task still needs its final review'; has 'request-review' 'says to run request-review'
grep -qF '任务 T10' "${REPO}/docs/reviews/skipped.md" && fail 'a review-last task waives nothing'
printf '%s\nSKIP\n-\ncode\n\nreview\n' "$(hsha)" > "${D}/.triage"
rt done T10; code 8 'a review-last task passes once routed at HEAD'

# ---- 第 2 轮起：接受「未修复」的 finding 还要再走一轮；接受的全是评审方判 resolved 的，不用改东西，周期已结束（手册第 ⑨ 步）----
rt add "验证轮之后的任务"; rt next; has 'TASK T11' 'T11 issued'
printf '%s\n%s\nrv-pane\n' "$(date +%s)" "$(hsha)" > "${D}/.r2.sent"
printf 'F1 | not-resolved\nclaim: 还差边界\n\nREVIEW-COMPLETE\n' > "${D}/r2-findings.md"
printf 'F1 accept — 补上边界\n' > "${D}/r2-responses.md"
rt done T11; code 9 'accepting a not-resolved finding still needs another round'
printf 'F1 | resolved\nclaim: 已修\n\nF2 | resolved\nclaim: 已修\n\nREVIEW-COMPLETE\n' > "${D}/r2-findings.md"
printf 'F1 accept — 接受 resolved 结论，无须修改\nF2 accept — 同上\nF3 defer — backlog 里的 nit\n' > "${D}/r2-responses.md"
rt done T11; code 8 'accepts that only acknowledge resolved findings close the cycle'

# ---- 调整顺序、修改还没开始的任务：按队列里的位置认（没编号的也行）；--expect 对不上说明队列刚被改过，拒绝（退出码 10）
rt add "排序甲"; rt add "排序乙" "乙的说明"; rt add "排序丙"
printf '\n## 手写丁\n丁的说明\n' >> "${D}/queue.md"
qv() { python3 -c 'import hashlib,sys; print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest()[:12])' "${D}/queue.md"; }
pending() { python3 - "${RT}" <<'PY2'
import importlib.machinery, importlib.util, os, sys
sys.dont_write_bytecode = True
p = os.path.join(os.path.dirname(os.path.realpath(sys.argv[1])), "review-board")
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
assert b.index(blk) < b.index("## T12 排序甲")
PY2
rt move 2 4; code 0 'move without --expect'
[ "$(pending)" = "手写丁|排序乙|排序丙|排序甲" ] || fail "move down: $(pending)"
rt move 9 1; code 2 'a position past the queue'
rt edit 2 "排序乙（改）" "流程：不评审" "新说明" --expect "$(qv)"; code 0 'edit a pending task'
grep -q '^## T13 排序乙（改）$' "${D}/queue.md" || fail 'edit keeps the ID and changes the title'
python3 - "${D}/queue.md" <<'PY2' || fail 'edit replaces the whole block'
import sys; q = open(sys.argv[1], encoding="utf-8").read()
i = q.index("## T13 排序乙（改）"); j = q.find("\n## ", i + 1)
assert q[i:j if j > 0 else None].strip() == "## T13 排序乙（改）\n流程：不评审\n新说明", repr(q[i:j])
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
tail -1 "${D}/tasks.state" | grep -q '"ev": "drop", "id": "T14"' || fail 'a numbered task is dropped under its own ID'
[ "$(pending)" = "手写丁（改）|排序乙（改）|排序甲" ] || fail "after dropping T14: $(pending)"
rt drop --pos 9 "x"; code 2 'a position past the queue'
rt list; has '手写戊' 'list shows the dropped unnumbered task'
rt next; code 0 'next after reordering'; has '手写丁（改）' 'next issues the task now at the front'

# ---- docs/queue-example.md 本身是合法的队列：四个任务，流程依次是 正常 / 正常 / 修好再审 / 不评审 ----
python3 - "${ROOT}/bin/review-board" "${ROOT}/docs/queue-example.md" <<'PY' || fail 'docs/queue-example.md drifted from the queue format'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", loader)); loader.exec_module(B)
blocks = B.task_blocks(open(sys.argv[2], encoding="utf-8").read())
assert [b["id"] for b in blocks] == ["T21", "T22", "T23", "T24"], [b["id"] for b in blocks]
assert [B.task_flow(b["body"]) for b in blocks] == ["", "", "修好再审", "不评审"]
assert "不走规划" in blocks[1]["body"] and "不走规划" in blocks[2]["body"]
PY

[ ! -s "${TMP}/herdr.log" ] || { cat "${TMP}/herdr.log"; fail 'review-task must never call herdr'; }
echo 'PASS review-task queue, release gate, read-only done check, pause and drop'
