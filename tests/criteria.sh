#!/usr/bin/env bash
# 完成判据测试（D1 第 2 步，验证计划第 1 层）：三条判据的只读核对。
# 用合成 git 仓库，不依赖真的 corral、不依赖真的 agent、不花钱。
#
# 三条判据（见 docs/ROADMAP.md「完成判据：纯 git，零解析」）：
#   1. main 前进了（送任务前记下的 sha 变了）
#   2. 包含 base_sha 的本次分支全都已经是 main 的祖先
#   3. 验收命令退出码为 0
# 外加「依据」：收尾记号（base_sha..main 里的一条空提交，首行「<前缀>: 一句话」）。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BOARD=${DROVER_BOARD_BIN:-${ROOT}/bin/drover-board}
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# 合成仓库：main 上一个提交，另有本次分支若干
R="${TMP}/repo"
mkdir -p "$R"
git -C "$R" init -q -b main
git -C "$R" config user.name t; git -C "$R" config user.email t@example.com
printf 'a\n' > "$R/a.py"; git -C "$R" add .; git -C "$R" commit -qm base
BASE=$(git -C "$R" rev-parse main)

# 判据求值：criteria(repo, base_sha, check_cmd) → 每条一个 {n, name, ok, why}
# ok 为 True / False / None（None = 这条不适用，既不算过也不算不过）
crit() {   # <base_sha> <check_cmd> ；打印 "1:ok 2:ok 3:skip" 这样一行，再打印各条的 why
  python3 - "${BOARD}" "$R" "$1" "$2" <<'PY2'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
rows = B.criteria(sys.argv[2], sys.argv[3], sys.argv[4])
print(" ".join(f'{r["n"]}:{"ok" if r["ok"] else ("skip" if r["ok"] is None else "no")}' for r in rows))
for r in rows:
    print(f'  {r["n"]} {r["name"]}: {r["why"]}')
PY2
}
line1() { crit "$@" | head -1; }
why() { crit "$1" "$2" | tail -n +2; }

# ---- 1. main 没动 → 第 1 条不过 ----
[ "$(line1 "${BASE}" '' | cut -d' ' -f1)" = "1:no" ] \
  || fail "main untouched: $(line1 "${BASE}" '')"
why "${BASE}" '' | grep -q '没有前进' || fail 'criterion 1 explains that main has not moved'

# ---- main 前进 → 第 1 条过 ----
printf 'b\n' >> "$R/a.py"; git -C "$R" add .; git -C "$R" commit -qm change
[ "$(line1 "${BASE}" '' | cut -d' ' -f1)" = "1:ok" ] \
  || fail "main moved: $(line1 "${BASE}" '')"

# ---- 2. 没有其它分支 → 过，并说明没有未合并的分支 ----
[ "$(line1 "${BASE}" '')" = "1:ok 2:ok 3:skip" ] \
  || fail "no other branches must pass: $(line1 "${BASE}" '')"
why "${BASE}" '' | grep -q '没有未合并的分支' || fail 'criterion 2 explains the empty branch set'

# ---- 2. 分支还没合进 main → 不过 ----
git -C "$R" branch feature/implementation
git -C "$R" checkout -q feature/implementation
printf 'c\n' >> "$R/a.py"; git -C "$R" add .; git -C "$R" commit -qm 'm1 work'
git -C "$R" checkout -q main
[ "$(line1 "${BASE}" '')" = "1:ok 2:no 3:skip" ] \
  || fail "unmerged branch must not pass: $(line1 "${BASE}" '')"
why "${BASE}" '' | grep -q 'feature/implementation' || fail 'criterion 2 names the unmerged branch'

# ---- 2. 合进 main 之后 → 过；分支没删也照样过（2026-09-20 改判据的原因）----
git -C "$R" merge -q --no-ff -m 'merge m1' feature/implementation
git -C "$R" branch --list 'feature/implementation' | grep -q feature || fail 'the branch is still there on purpose'
[ "$(line1 "${BASE}" '')" = "1:ok 2:ok 3:skip" ] \
  || fail "merged branch passes even though it was not deleted: $(line1 "${BASE}" '')"

# ---- 2. main 自己绝不算本次分支 ----
# 直接断分支清单本身：判据的说明文字里本来就会出现 main 这个词，grep 整段认不出来
python3 - "${BOARD}" "$R" "$BASE" <<'PY2' || fail 'main itself must never be counted as a task branch'
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
branches, excluded, errors = B.task_branches(sys.argv[2], sys.argv[3])
assert branches == ["feature/implementation"], branches
assert excluded == [], excluded
assert errors == [], errors
assert "main" in B.git(sys.argv[2], "branch", "--list"), "前提：本地分支清单里确实有 main"
PY2

# ---- 2. 合法 Unicode 空白是分支名的一部分，不能裁成已合入的同名分支 ----
python3 - "${BOARD}" "${TMP}/unicode-repo" <<'PY2'
import importlib.machinery, importlib.util, pathlib, subprocess, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
repo = sys.argv[2]
pathlib.Path(repo).mkdir()
def git(*args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, check=True).stdout
git("init", "-q", "-b", "main")
git("config", "user.name", "t"); git("config", "user.email", "t@example.com")
git("commit", "-q", "--allow-empty", "-m", "base")
base = git("rev-parse", "refs/heads/main").rstrip("\n")
git("branch", "feature/merged")
branch = "feature/merged\u00a0"
git("checkout", "-qb", branch)
git("commit", "-q", "--allow-empty", "-m", "unfinished")
git("checkout", "-q", "main")
row = B.criteria(repo, base, "")[1]
assert row["ok"] is False, f"NBSP branch must block: {row!r}"
assert row["why"] == "还没合进 main：" + branch, row
assert B.task_branches(repo, base) == (["feature/merged", branch], [], [])
git("merge", "-q", "--ff-only", "refs/heads/" + branch)
row = B.criteria(repo, base, "")[1]
assert row["ok"] is True, row
assert row["why"] == "2 个都已经是 main 的祖先：feature/merged、" + branch, row

# U+2028 是 ref 内的字符；已合入时不能因为拆成两条而误报查询失败。
separated = "feature/line\u2028separator"
git("branch", separated)
row = B.criteria(repo, base, "")[1]
assert row["ok"] is True, f"U+2028 branch must stay intact: {row!r}"
assert row["why"] == "3 个都已经是 main 的祖先：" + "、".join([
    separated, "feature/merged", branch]), row
git("checkout", "-q", separated)
git("commit", "-q", "--allow-empty", "-m", "separator unfinished")
git("checkout", "-q", "main")
row = B.criteria(repo, base, "")[1]
assert row["ok"] is False, row
assert row["why"] == "还没合进 main：" + separated, row
assert B.task_branches(repo, base) == ([separated, "feature/merged", branch], [], [])

# 同名 tag 已合入，分支未合入；关闭短名歧义警告后也必须查真实分支。
git("tag", separated, base)
git("config", "core.warnAmbiguousRefs", "false")
row = B.criteria(repo, base, "")[1]
assert row["ok"] is False, f"same-name tag must not hide the branch: {row!r}"
assert row["why"] == "还没合进 main：" + separated, row
assert B.task_branches(repo, base) == ([separated, "feature/merged", branch], [], [])

# 开启警告时 Git 的 short 格式会带 heads/；显示仍只剥固定 refs/heads/。
git("config", "core.warnAmbiguousRefs", "true")
row = B.criteria(repo, base, "")[1]
assert row["ok"] is False and row["why"] == "还没合进 main：" + separated, row
assert B.task_branches(repo, base) == ([separated, "feature/merged", branch], [], [])
PY2

# ---- 2. 两次祖先查询分别消歧：分支同名 tag 不能改变分类，main 同名 tag 不能冒充合入 ----
python3 - "${BOARD}" "${TMP}" <<'PY2'
import importlib.machinery, importlib.util, pathlib, subprocess, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
for scenario, tag_name in [("branch-tag", "feature/task"), ("main-tag", "main")]:
    repo = str(pathlib.Path(sys.argv[2]) / scenario)
    pathlib.Path(repo).mkdir()
    def git(*args):
        return subprocess.run(["git", "-C", repo, *args], capture_output=True,
                              text=True, check=True).stdout.rstrip("\n")
    git("init", "-q", "-b", "main")
    git("config", "user.name", "t"); git("config", "user.email", "t@example.com")
    git("commit", "-q", "--allow-empty", "-m", "early")
    early = git("rev-parse", "HEAD")
    git("commit", "-q", "--allow-empty", "-m", "base")
    base = git("rev-parse", "HEAD")
    git("checkout", "-qb", "feature/task")
    git("commit", "-q", "--allow-empty", "-m", "pending")
    pending = git("rev-parse", "HEAD")
    git("checkout", "-q", "main")
    # 第一个场景的 tag 不含 base；第二个场景的 tag 冒充已包含 pending 的 main。
    git("tag", tag_name, early if scenario == "branch-tag" else pending)
    assert git("rev-parse", "refs/heads/main") == base, scenario
    branches, excluded, errors = B.task_branches(repo, base)
    assert branches == ["feature/task"], f"{scenario} current branches: {branches!r}"
    assert excluded == [], f"{scenario} excluded branches: {excluded!r}"
    assert errors == [], f"{scenario} query errors: {errors!r}"
    row = B.criteria(repo, base, "")[1]
    assert row["ok"] is False, f"{scenario} must block pending branch: {row!r}"
    assert row["why"] == "还没合进 main：feature/task", f"{scenario} reason: {row!r}"
PY2

# ---- 3. 验收命令退出码 0 → 过 ----
[ "$(line1 "${BASE}" 'true')" = "1:ok 2:ok 3:ok" ] \
  || fail "passing check: $(line1 "${BASE}" 'true')"

# ---- 3. 验收失败 → 不过，并带上输出尾巴 ----
[ "$(line1 "${BASE}" 'echo 3 failed; exit 1')" = "1:ok 2:ok 3:no" ] \
  || fail "failing check: $(line1 "${BASE}" 'echo 3 failed; exit 1')"
why "${BASE}" 'echo 3 failed; exit 1' | grep -q '3 failed' || fail 'a failing check carries its output'

# ---- 3. 验收命令本身崩了（命令不存在）→ 不过，且说清是命令跑不起来，不是测试没通过 ----
why "${BASE}" 'no-such-command-xyz' | grep -q '退出码 127' \
  || fail 'a check command that cannot run is reported with its exit code'

# ---- 3. 验收命令在仓库根跑，不在别处 ----
[ "$(line1 "${BASE}" 'test -f a.py')" = "1:ok 2:ok 3:ok" ] \
  || fail 'the check command runs in the repo root'

# ---- 3. 走 shell：&& 和管道这些要能用（CHECK_CMD 的例子就是 cd backend && …）----
[ "$(line1 "${BASE}" 'true && echo x | grep -q x')" = "1:ok 2:ok 3:ok" ] \
  || fail 'the check command goes through a shell'

# ---- 三条判据全程只读：跑完一轮，仓库的 HEAD 和工作区都没变 ----
H=$(git -C "$R" rev-parse HEAD)
crit "${BASE}" 'true' > /dev/null
[ "$(git -C "$R" rev-parse HEAD)" = "$H" ] || fail 'evaluating the criteria must not move HEAD'
[ -z "$(git -C "$R" status --porcelain)" ] || fail 'evaluating the criteria must not touch the working tree'

# ---- 2. 遗留分支不该卡住这次任务，但这次未合入的分支仍必须挡住 ----
(
R="${TMP}/history-repo"; mkdir -p "$R"
git -C "$R" init -q -b main
git -C "$R" config user.name t; git -C "$R" config user.email t@example.com
git -C "$R" commit -q --allow-empty -m initial
EARLY=$(git -C "$R" rev-parse main)
git -C "$R" commit -q --allow-empty -m 'main before legacy branch'
git -C "$R" checkout -qb m4/planning "$EARLY"
printf 'abandoned\n' > "$R/legacy.py"; git -C "$R" add .; git -C "$R" commit -qm 'legacy work'
git -C "$R" checkout -q main
git -C "$R" commit -q --allow-empty -m 'main before dispatch'
CURRENT_BASE=$(git -C "$R" rev-parse main)
git -C "$R" checkout -qb m6/impl
printf 'current\n' > "$R/current.py"; git -C "$R" add .; git -C "$R" commit -qm 'current work'
git -C "$R" checkout -q main
# main 已前进，确认是第 2 条仍在挡这次未合入的分支。
git -C "$R" commit -q --allow-empty -m 'main after dispatch'
[ "$(line1 "$CURRENT_BASE" '')" = "1:ok 2:no 3:skip" ] \
  || fail "current unmerged branch must still block: $(crit "$CURRENT_BASE" '')"
why "$CURRENT_BASE" '' | grep -q 'm6/impl' \
  || fail 'criterion 2 must name the current unmerged branch'
why "$CURRENT_BASE" '' | grep -q '已排除.*m4/planning' \
  || fail 'a blocking criterion must name the excluded legacy branch'
git -C "$R" merge -q --no-ff -m 'merge current task' m6/impl
[ "$(line1 "$CURRENT_BASE" '')" = "1:ok 2:ok 3:skip" ] \
  || fail "merged current branch must pass despite legacy branch: $(crit "$CURRENT_BASE" '')"
why "$CURRENT_BASE" '' | grep -q '1 个都已经是 main 的祖先：m6/impl' \
  || fail 'only the current branch is reported as merged'
why "$CURRENT_BASE" '' | grep -q '已排除.*m4/planning' \
  || fail 'a passing criterion must name the excluded legacy branch'

# ---- 2. 两个本次分支必须都合入，不能只核对第一个 ----
git -C "$R" checkout -qb m6/second "$CURRENT_BASE"
printf 'second\n' > "$R/second.py"; git -C "$R" add .; git -C "$R" commit -qm 'second work'
git -C "$R" checkout -q main
[ "$(line1 "$CURRENT_BASE" '')" = "1:ok 2:no 3:skip" ] \
  || fail "second current branch must still block: $(crit "$CURRENT_BASE" '')"
why "$CURRENT_BASE" '' | grep -q '还没合进 main：m6/second' \
  || fail 'criterion 2 must name the second unmerged branch'
why "$CURRENT_BASE" '' | grep -q '已排除.*m4/planning' \
  || fail 'mixed current branches must still report the excluded legacy branch'
git -C "$R" merge -q --no-ff -m 'merge second task branch' m6/second
[ "$(line1 "$CURRENT_BASE" '')" = "1:ok 2:ok 3:skip" ] \
  || fail "both current branches merged must pass: $(crit "$CURRENT_BASE" '')"

why "$CURRENT_BASE" '' | grep -q '2 个都已经是 main 的祖先：m6/impl、m6/second' \
  || fail 'criterion 2 must name every merged current branch'

# ---- 2. 没记 base_sha → 不适用，不能退回旧行为或凭空卡住 ----
[ "$(line1 '' '')" = "1:no 2:skip 3:skip" ] \
  || fail "missing base_sha makes criterion 2 inapplicable: $(crit '' '')"
why '' '' | grep -q '2 .*没有 base_sha' \
  || fail 'criterion 2 explains the missing base_sha'

# ---- 2. 一个分支正常且已合入，另一个祖先查询报错 → 不过并报告 Git 错误 ----
git -C "$R" checkout -qb m6/z-broken "$CURRENT_BASE"
git -C "$R" commit -q --allow-empty -m 'broken branch middle'
MIDDLE=$(git -C "$R" rev-parse HEAD)
git -C "$R" commit -q --allow-empty -m 'broken branch tip'
git -C "$R" checkout -q main
python3 - "${BOARD}" "$R" "$CURRENT_BASE" "$MIDDLE" <<'PY2'
import importlib.machinery, importlib.util, pathlib, subprocess, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
repo, base, middle = sys.argv[2:]
obj = pathlib.Path(repo) / ".git" / "objects" / middle[:2] / middle[2:]
saved = pathlib.Path(repo).parent / "saved-middle-object"
assert B.criteria(repo, base, "")[1]["ok"] is False
obj.rename(saved)
try:
    listed = subprocess.run(["git", "-C", repo, "branch", "--list", "--format=%(refname:short)", "m6/*"],
                            capture_output=True, text=True)
    assert listed.returncode == 0 and "m6/z-broken" in listed.stdout, listed
    good = subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", base, "m6/impl"])
    assert good.returncode == 0, "the other branch still contains base_sha"
    bad = subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", base, "m6/z-broken"],
                         capture_output=True, text=True)
    assert bad.returncode == 128 and bad.stderr.strip(), bad
    row = B.criteria(repo, base, "")[1]
    assert row["ok"] is False, f"branch query error must block despite merged siblings: {row}"
    assert "m6/z-broken" in row["why"] and "查询失败" in row["why"], row
    assert bad.stderr.strip() in row["why"], row
finally:
    saved.rename(obj)
PY2
# ---- 2. 全是遗留分支 → 过，理由与没有其它分支不同 ----
git -C "$R" branch m4/other m4/planning
git -C "$R" branch -D m6/z-broken >/dev/null
git -C "$R" branch -d m6/impl m6/second >/dev/null
[ "$(line1 "$CURRENT_BASE" '')" = "1:ok 2:ok 3:skip" ] \
  || fail "all legacy branches must pass: $(crit "$CURRENT_BASE" '')"
LEGACY_WHY=$(why "$CURRENT_BASE" '')
printf '%s\n' "$LEGACY_WHY" | grep -q '2 个.*全部被排除' \
  || fail "all-filtered branches need a distinct explanation: $LEGACY_WHY"
for branch in m4/planning m4/other; do
  printf '%s\n' "$LEGACY_WHY" | grep -q "$branch" || fail "excluded branch missing: $branch"
done
if printf '%s\n' "$LEGACY_WHY" | grep -q '没有未合并的分支'; then
  fail 'all-filtered branches must not use the no-other-branches explanation'
fi
)
[ "$(line1 "$BASE" '')" = "1:ok 2:ok 3:skip" ] \
  || fail 'history scenarios must leave the outer repo and base intact'

# ---- 2. 没有正常候选，只有查询失败分支 → 仍不能空集合通过 ----
python3 - "${BOARD}" "${TMP}/only-error-repo" <<'PY2'
import importlib.machinery, importlib.util, pathlib, subprocess, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
repo = sys.argv[2]
pathlib.Path(repo).mkdir()
def git(*args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, check=True).stdout.strip()
git("init", "-q", "-b", "main")
git("config", "user.name", "t"); git("config", "user.email", "t@example.com")
git("commit", "-q", "--allow-empty", "-m", "base")
base = git("rev-parse", "main")
git("checkout", "-qb", "feature/only-broken")
git("commit", "-q", "--allow-empty", "-m", "middle")
middle = git("rev-parse", "HEAD")
git("commit", "-q", "--allow-empty", "-m", "tip")
git("checkout", "-q", "main")
obj = pathlib.Path(repo) / ".git/objects" / middle[:2] / middle[2:]
saved = obj.read_bytes()
obj.unlink()
try:
    bad = subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", base, "feature/only-broken"],
                         capture_output=True, text=True)
    assert bad.returncode == 128 and bad.stderr.strip(), bad
    branches, excluded, errors = B.task_branches(repo, base)
    assert branches == [] and excluded == [] and len(errors) == 1, (branches, excluded, errors)
    assert "feature/only-broken" in errors[0] and bad.stderr.strip() in errors[0], errors
    row = B.criteria(repo, base, "")[1]
    assert row["ok"] is False, f"query error without candidates must block: {row}"
    assert "feature/only-broken" in row["why"] and bad.stderr.strip() in row["why"], row
finally:
    obj.write_bytes(saved)
PY2

# ---- 2. attached / detached cwd 只枚举真实分支，worktree 占用分支仍需核对 ----
python3 - "${BOARD}" "$R" "$BASE" "${TMP}" <<'PY2'
import importlib.machinery, importlib.util, subprocess, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
repo, base, tmp = sys.argv[2:]
def git(cwd, *args):
    subprocess.run(["git", "-C", cwd, *args], check=True, capture_output=True, text=True)
occupied, detached = tmp + "/occupied", tmp + "/detached"
git(repo, "worktree", "add", "-q", occupied, "feature/implementation")
git(repo, "worktree", "add", "-q", "--detach", detached, "main")
expected = (["feature/implementation"], [], [])
assert B.task_branches(repo, base) == expected
attached_rows = B.criteria(repo, base, "")
assert attached_rows[1]["ok"] is True, attached_rows
# 本仓库 checkout --detach 和新建 detached worktree 的伪条目不同，两种都要验。
git(repo, "checkout", "-q", "--detach", "main")
try:
    for cwd in (repo, detached):
        actual = B.task_branches(cwd, base)
        assert actual == expected, f"detached cwd must list only real branches: {actual}"
        assert B.criteria(cwd, base, "") == attached_rows, cwd
    git(occupied, "commit", "-q", "--allow-empty", "-m", "occupied branch unfinished")
    for cwd in (repo, detached):
        row = B.criteria(cwd, base, "")[1]
        assert row["ok"] is False and "feature/implementation" in row["why"], row
finally:
    git(repo, "checkout", "-q", "main")
PY2

# ---- 2. 枚举丢了坏 ref，即使退出码为 0 也不能空集合通过 ----
python3 - "${BOARD}" "${TMP}/enumeration-repo" <<'PY2'
import importlib.machinery, importlib.util, os, pathlib, subprocess, sys
from unittest.mock import patch
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("rb", l)); l.exec_module(B)
repo = sys.argv[2]
pathlib.Path(repo).mkdir()
def git(*args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, check=True).stdout.strip()
git("init", "-q", "-b", "main")
git("config", "user.name", "t"); git("config", "user.email", "t@example.com")
git("commit", "-q", "--allow-empty", "-m", "base")
base = git("rev-parse", "main")
git("checkout", "-qb", "feature/unfinished")
git("commit", "-q", "--allow-empty", "-m", "unfinished")
git("checkout", "-q", "main")
assert B.criteria(repo, base, "")[1]["ok"] is False, "前提：未合入分支必须挡住"
ref = pathlib.Path(repo) / ".git/refs/heads/feature/unfinished"
saved = ref.read_bytes()
ref.write_text("not-a-sha\n")
try:
    listed = subprocess.run(["git", "-C", repo, "for-each-ref", "--format=%(refname:short)", "refs/heads/"],
                            capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"})
    assert listed.returncode == 0 and "warning: ignoring broken ref" in listed.stderr, listed
    row = B.criteria(repo, base, "")[1]
    assert row["ok"] is False, f"ignored broken ref must block: {row}"
    assert listed.stderr.strip() in row["why"], row

    # 调用者处于非英文环境；先用真实 git 证明警告已翻译，禁止用英文外层掩盖生产缺口。
    for locale_name, translated in [("zh_CN.UTF-8", "忽略损坏的引用"), ("fr_FR.UTF-8", "réf cassé")]:
        with patch.dict(os.environ, {"LC_ALL": locale_name, "LANG": locale_name, "LANGUAGE": ""}):
            caller_env = dict(os.environ)
            localized = subprocess.run(
                ["git", "-C", repo, "for-each-ref", "--format=%(refname:short)", "refs/heads/"],
                capture_output=True, text=True)
            assert localized.returncode == 0 and translated in localized.stderr, (
                "前提：真实 git 必须输出非英文坏 ref 警告（需要对应翻译目录）", locale_name, localized)
            assert "refs/heads/feature/unfinished" in localized.stderr, localized
            print(f"locale fixture {locale_name}: {localized.stderr.strip()}", flush=True)
            branches, excluded, errors = B.task_branches(repo, base)
            row = B.criteria(repo, base, "")[1]
            assert row["ok"] is False, f"non-English locale broken ref must block ({locale_name}): {row}"
            assert branches == [] and excluded == [] and len(errors) == 1, (branches, excluded, errors)
            assert "warning: ignoring broken ref refs/heads/feature/unfinished" in errors[0], errors
            assert errors[0] in row["why"], row
            assert dict(os.environ) == caller_env, "枚举不能修改调用进程的环境"
finally:
    ref.write_bytes(saved)

# subprocess 边界注入：枚举非零、启动异常和超时；其它 git 调用仍用真的合成仓库。
real_run = subprocess.run
for failure, diagnostic in [
    (subprocess.CompletedProcess([], 128, "", "fatal: enumeration failed"), "fatal: enumeration failed"),
    (OSError("enumeration could not start"), "enumeration could not start"),
    (subprocess.TimeoutExpired("git enumerate", 30, stderr=b"enumeration timeout detail"), "enumeration timeout detail"),
]:
    calls = []
    def run(args, *a, **kw):
        if args[:3] == ["git", "-C", repo] and args[3] in ("branch", "for-each-ref"):
            calls.append(args)
            if isinstance(failure, Exception):
                raise failure
            return failure
        return real_run(args, *a, **kw)
    with patch.object(B.subprocess, "run", side_effect=run):
        row = B.criteria(repo, base, "")[1]
    assert calls, "前提：确实注入到枚举命令"
    assert row["ok"] is False, f"enumeration failure must block: {row}"
    assert diagnostic in row["why"], row
    if isinstance(failure, subprocess.CompletedProcess):
        assert "128" in row["why"], row
PY2

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

echo 'PASS criteria: main moved, task branches merged, check command; empty/all-legacy pass with distinct reasons, missing base skips'
echo 'PASS 收尾记号: interval / single parent / empty / prefix; merge commits rejected, prefix is per-project'
