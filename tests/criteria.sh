#!/usr/bin/env bash
# 完成判据测试（D1 第 2 步，验证计划第 1 层）：三条判据的只读核对。
# 用合成 git 仓库，不依赖真的 corral、不依赖真的 agent、不花钱。
#
# 三条判据（见 docs/ROADMAP.md「完成判据：纯 git，零解析」）：
#   1. main 前进了（送任务前记下的 sha 变了）
#   2. BRANCH_GLOB 匹配到的里程碑分支全都已经是 main 的祖先
#   3. 验收命令退出码为 0
# 外加「依据」：收尾记号（base_sha..main 里的一条空提交，首行「<前缀>: 一句话」）。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BOARD=${DROVER_BOARD_BIN:-${ROOT}/bin/drover-board}
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# 合成仓库：main 上一个提交，另有里程碑分支若干
R="${TMP}/repo"
mkdir -p "$R"
git -C "$R" init -q -b main
git -C "$R" config user.name t; git -C "$R" config user.email t@example.com
printf 'a\n' > "$R/a.py"; git -C "$R" add .; git -C "$R" commit -qm base
BASE=$(git -C "$R" rev-parse main)

# 判据求值：criteria(repo, base_sha, branch_glob, check_cmd) → 每条一个 {n, name, ok, why}
# ok 为 True / False / None（None = 这条不适用，既不算过也不算不过）
crit() {   # <base_sha> <branch_glob> <check_cmd> ；打印 "1:ok 2:ok 3:skip" 这样一行，再打印各条的 why
  python3 - "${BOARD}" "$R" "$1" "$2" "$3" <<'PY2'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
rows = B.criteria(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
print(" ".join(f'{r["n"]}:{"ok" if r["ok"] else ("skip" if r["ok"] is None else "no")}' for r in rows))
for r in rows:
    print(f'  {r["n"]} {r["name"]}: {r["why"]}')
PY2
}
line1() { crit "$@" | head -1; }
why() { crit "$1" "$2" "$3" | tail -n +2; }

# ---- 1. main 没动 → 第 1 条不过 ----
[ "$(line1 "${BASE}" '' '')" = "1:no 2:skip 3:skip" ] \
  || fail "main untouched: $(line1 "${BASE}" '' '')"
why "${BASE}" '' '' | grep -q '没有前进' || fail 'criterion 1 explains that main has not moved'

# ---- main 前进 → 第 1 条过 ----
printf 'b\n' >> "$R/a.py"; git -C "$R" add .; git -C "$R" commit -qm change
[ "$(line1 "${BASE}" '' '')" = "1:ok 2:skip 3:skip" ] \
  || fail "main moved: $(line1 "${BASE}" '' '')"

# ---- 2. BRANCH_GLOB 为空 → 第 2 条不适用（这个项目不用里程碑分支），不是不过 ----
why "${BASE}" '' '' | grep -q '没配' || fail 'an empty glob says the project does not use milestone branches'

# ---- 2. glob 匹配到 0 个分支 → 不过（空真坑：对空集合「全都合进去了」恒真）----
[ "$(line1 "${BASE}" 'm[0-9]*' '')" = "1:ok 2:no 3:skip" ] \
  || fail "glob matching nothing must not pass: $(line1 "${BASE}" 'm[0-9]*' '')"
why "${BASE}" 'm[0-9]*' '' | grep -q '一个都没匹配到' || fail 'criterion 2 says the glob matched nothing'

# ---- 2. 分支还没合进 main → 不过 ----
git -C "$R" branch m1/implementation
git -C "$R" checkout -q m1/implementation
printf 'c\n' >> "$R/a.py"; git -C "$R" add .; git -C "$R" commit -qm 'm1 work'
git -C "$R" checkout -q main
[ "$(line1 "${BASE}" 'm[0-9]*' '')" = "1:ok 2:no 3:skip" ] \
  || fail "unmerged branch must not pass: $(line1 "${BASE}" 'm[0-9]*' '')"
why "${BASE}" 'm[0-9]*' '' | grep -q 'm1/implementation' || fail 'criterion 2 names the unmerged branch'

# ---- 2. 合进 main 之后 → 过；分支没删也照样过（2026-09-20 改判据的原因）----
git -C "$R" merge -q --no-ff -m 'merge m1' m1/implementation
git -C "$R" branch --list 'm1/implementation' | grep -q m1 || fail 'the branch is still there on purpose'
[ "$(line1 "${BASE}" 'm[0-9]*' '')" = "1:ok 2:ok 3:skip" ] \
  || fail "merged branch passes even though it was not deleted: $(line1 "${BASE}" 'm[0-9]*' '')"

# ---- 2. main 自己绝不算里程碑分支，哪怕 glob 匹配得上（m* 会匹配到 main）----
[ "$(line1 "${BASE}" 'm*' '')" = "1:ok 2:ok 3:skip" ] || fail 'm* must still work'
# 直接断分支清单本身：判据的说明文字里本来就会出现 main 这个词，grep 整段认不出来
python3 - "${BOARD}" "$R" <<'PY2' || fail 'main itself must never be counted as a milestone branch'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
assert B.milestone_branches(sys.argv[2], "m*") == ["m1/implementation"], B.milestone_branches(sys.argv[2], "m*")
assert "main" in B.git(sys.argv[2], "branch", "--list", "m*"), "前提：m* 确实匹配得到 main"
PY2

# ---- 3. 验收命令退出码 0 → 过 ----
[ "$(line1 "${BASE}" 'm[0-9]*' 'true')" = "1:ok 2:ok 3:ok" ] \
  || fail "passing check: $(line1 "${BASE}" 'm[0-9]*' 'true')"

# ---- 3. 验收失败 → 不过，并带上输出尾巴 ----
[ "$(line1 "${BASE}" 'm[0-9]*' 'echo 3 failed; exit 1')" = "1:ok 2:ok 3:no" ] \
  || fail "failing check: $(line1 "${BASE}" 'm[0-9]*' 'echo 3 failed; exit 1')"
why "${BASE}" 'm[0-9]*' 'echo 3 failed; exit 1' | grep -q '3 failed' || fail 'a failing check carries its output'

# ---- 3. 验收命令本身崩了（命令不存在）→ 不过，且说清是命令跑不起来，不是测试没通过 ----
why "${BASE}" 'm[0-9]*' 'no-such-command-xyz' | grep -q '退出码 127' \
  || fail 'a check command that cannot run is reported with its exit code'

# ---- 3. 验收命令在仓库根跑，不在别处 ----
[ "$(line1 "${BASE}" '' 'test -f a.py')" = "1:ok 2:skip 3:ok" ] \
  || fail 'the check command runs in the repo root'

# ---- 3. 走 shell：&& 和管道这些要能用（CHECK_CMD 的例子就是 cd backend && …）----
[ "$(line1 "${BASE}" '' 'true && echo x | grep -q x')" = "1:ok 2:skip 3:ok" ] \
  || fail 'the check command goes through a shell'

# ---- 三条判据全程只读：跑完一轮，仓库的 HEAD 和工作区都没变 ----
H=$(git -C "$R" rev-parse HEAD)
crit "${BASE}" 'm[0-9]*' 'true' > /dev/null
[ "$(git -C "$R" rev-parse HEAD)" = "$H" ] || fail 'evaluating the criteria must not move HEAD'
[ -z "$(git -C "$R" status --porcelain)" ] || fail 'evaluating the criteria must not touch the working tree'

# ================== 收尾记号：判「这件活完了」的唯一依据 ==================
# 三条判据是「门」（现在是不是一个可以去判断的时刻），收尾记号是「依据」（凭什么说它完了）。
# 四道闸：区间 / 父提交恰好一个 / 空提交 / 前缀。见 docs/ROADMAP.md 完成判据那一节。
R2="${TMP}/repo2"; mkdir -p "$R2"
git -C "$R2" init -q -b main
git -C "$R2" config user.name t; git -C "$R2" config user.email t@example.com
printf 'a\n' > "$R2/a.py"; git -C "$R2" add .; git -C "$R2" commit -qm base

mark() {   # <base_sha> <前缀> → "ok|no|skip<TAB>说明"
  python3 - "${BOARD}" "$R2" "$1" "$2" <<'PY2'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
r = B.find_done_mark(sys.argv[2], sys.argv[3], sys.argv[4])
print(("ok" if r["ok"] else ("skip" if r["ok"] is None else "no")) + "\t" + r["why"])
PY2
}
m1() { mark "$1" "$2" | cut -f1; }

B0=$(git -C "$R2" rev-parse main)
git -C "$R2" commit -q --allow-empty -m '收尾: 上一件活'
B1=$(git -C "$R2" rev-parse main)

# ---- 闸 1 区间：上一件活的记号在 base_sha 之前，不能算这一件的 ----
[ "$(m1 "$B1" 收尾)" = "no" ] || fail "a marker before base_sha must not count: $(mark "$B1" 收尾)"
[ "$(m1 "$B0" 收尾)" = "ok" ] || fail 'that same marker is valid — only the interval excluded it'

# ---- 前缀没配 → 不适用（这个项目不打收尾记号），不是不过 ----
[ "$(m1 "$B1" '')" = "skip" ] || fail "an empty DONE_MARK is not applicable: $(mark "$B1" '')"
mark "$B1" '' | grep -q 'DONE_MARK' || fail 'and says which setting is missing'

# ---- 闸 3 空提交：改了文件的普通提交，哪怕首行带前缀也不算 ----
printf 'b\n' >> "$R2/a.py"; git -C "$R2" add .; git -C "$R2" commit -qm '收尾: 这条改了文件'
[ "$(m1 "$B1" 收尾)" = "no" ] || fail 'a normal commit carrying the prefix is not a marker'

# ---- 闸 2 单亲：合并提交在 git diff-tree 眼里输出也是 0 行，光靠「空 + 前缀」会误判 ----
git -C "$R2" checkout -qb feat
printf 'c\n' > "$R2/b.py"; git -C "$R2" add .; git -C "$R2" commit -qm 'feat work'
git -C "$R2" checkout -q main
git -C "$R2" merge -q --no-ff -m '收尾: 摘要碰巧以前缀开头的合并提交' feat
[ -z "$(git -C "$R2" diff-tree --no-commit-id --name-only -r HEAD)" ] \
  || fail '前提：合并提交在 diff-tree 眼里确实是空的（不成立的话这条测试就没意义了）'
[ "$(m1 "$B1" 收尾)" = "no" ] || fail 'a merge commit whose subject starts with the prefix must be rejected'

# ---- 四道闸全过 → 这件活完了 ----
git -C "$R2" commit -q --allow-empty -m '收尾: M8-2 录结果前端、外来卷子'
[ "$(m1 "$B1" 收尾)" = "ok" ] || fail "a real marker passes: $(mark "$B1" 收尾)"
mark "$B1" 收尾 | grep -q 'M8-2' || fail 'the row carries the subject so the board can show what finished'

# ---- 闸 4 前缀：全角冒号也收（人手敲中文容易出全角）----
B2=$(git -C "$R2" rev-parse main)
git -C "$R2" commit -q --allow-empty -m '收尾：全角冒号'
[ "$(m1 "$B2" 收尾)" = "ok" ] || fail 'a full-width colon is accepted too'

# ---- 闸 4 前缀：项目自己挑，不写死中文 ----
B3=$(git -C "$R2" rev-parse main)
git -C "$R2" commit -q --allow-empty -m 'wrap: english prefix'
[ "$(m1 "$B3" wrap)" = "ok" ] || fail 'the project picks its own prefix'
[ "$(m1 "$B3" 收尾)" = "no" ] || fail 'and a different prefix does not match'

# ---- 只读 ----
H2=$(git -C "$R2" rev-parse HEAD)
m1 "$B1" 收尾 > /dev/null
[ "$(git -C "$R2" rev-parse HEAD)" = "$H2" ] || fail 'looking for the marker must not move HEAD'
[ -z "$(git -C "$R2" status --porcelain)" ] || fail 'looking for the marker must not touch the working tree'

echo 'PASS criteria: main moved, milestone branches merged, check command; empty glob skips, matching nothing fails'
echo 'PASS 收尾记号: interval / single parent / empty / prefix; merge commits rejected, prefix is per-project'
