#!/usr/bin/env bash
# 全局安装（只需一次，所有项目共用）
set -euo pipefail

# ============================================================================
# 锁死：这个脚本是从 herdsman 原样继承来的，现在跑它会拆掉本机正在用的老 herdsman
# ============================================================================
# 它会：
#   1. 覆盖 ~/.local/bin/ 里的 herdsman-init、review-board、review-map、review-task
#      —— 那几个是老 herdsman 装出去的副本，正在推进一个真实项目；
#   2. 覆盖 ~/.config/review/ 下的配置；
#   3. launchctl bootout 再 bootstrap 掉 dev.herdsman.review-board 和
#      dev.herdsman.review-board-serve —— 这两个 launchd 任务此刻正在运行。
#
# drover 装到哪、叫什么名字、用不用 launchd，是 ROADMAP D1 第 1 步和第 5 步要定的事。
# 定完并把这个脚本重写之后，删掉下面这段守卫。在那之前不要绕过它。
if [ "${DROVER_INSTALL_REWRITTEN:-}" != "1" ]; then
  cat >&2 <<'GUARD'
install.sh 还没有按 drover 重写，拒绝运行。

它现在是 herdsman 时代的脚本，会覆盖 ~/.local/bin 里正在用的命令、覆盖
~/.config/review/，并重启 dev.herdsman.* 两个 launchd 任务 —— 那是本机
正在跑的老 herdsman，动了就会打断一个真实项目。

要装 drover：先按 docs/ROADMAP.md D1 第 1 步定好装到哪、叫什么，第 5 步
重写这个脚本，然后删掉本文件里这段守卫。
GUARD
  exit 2
fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${HOME}/.local/bin"
CFG="${HOME}/.config/review"

echo "从 ${SRC} 安装"

mkdir -p "${BIN}" "${CFG}"

install -m 0755 "${SRC}/bin/request-review" "${BIN}/request-review"
install -m 0755 "${SRC}/bin/review-archive" "${BIN}/review-archive"
install -m 0755 "${SRC}/bin/herdsman-init" "${BIN}/herdsman-init"
install -m 0755 "${SRC}/bin/review-board" "${BIN}/review-board"
install -m 0755 "${SRC}/bin/review-map" "${BIN}/review-map"
install -m 0755 "${SRC}/bin/review-task" "${BIN}/review-task"
echo "  ✓ ${BIN}/request-review"
echo "  ✓ ${BIN}/review-archive"
echo "  ✓ ${BIN}/herdsman-init"
echo "  ✓ ${BIN}/review-board"
echo "  ✓ ${BIN}/review-map"
echo "  ✓ ${BIN}/review-task"

if [ -f "${CFG}/rubric.md" ]; then
  if cmp -s "${SRC}/config/rubric.md" "${CFG}/rubric.md"; then
    echo "  = ${CFG}/rubric.md（无变化）"
  else
    cp "${CFG}/rubric.md" "${CFG}/rubric.md.bak.$(date +%Y%m%d%H%M%S)"
    install -m 0644 "${SRC}/config/rubric.md" "${CFG}/rubric.md"
    echo "  ✓ ${CFG}/rubric.md（旧版已备份为 .bak.*）"
  fi
else
  install -m 0644 "${SRC}/config/rubric.md" "${CFG}/rubric.md"
  echo "  ✓ ${CFG}/rubric.md"
fi

install -m 0644 "${SRC}/templates/agents-section.md" "${CFG}/agents-section.md"
echo "  ✓ ${CFG}/agents-section.md"
install -m 0644 "${SRC}/templates/brief-prompt.md" "${CFG}/brief-prompt.md"
echo "  ✓ ${CFG}/brief-prompt.md"
install -m 0644 "${SRC}/templates/planner-prompt.md" "${CFG}/planner-prompt.md"
echo "  ✓ ${CFG}/planner-prompt.md"

# 看板定时生成（macOS launchd，每 30 秒）；非 macOS 跳过
if [ "$(uname)" = Darwin ]; then
  AGENTS="${HOME}/Library/LaunchAgents"; PLIST="${AGENTS}/dev.herdsman.review-board.plist"
  mkdir -p "${AGENTS}" "${HOME}/.review"
  sed "s|__HOME__|${HOME}|g" "${SRC}/templates/review-board.plist" > "${PLIST}"
  launchctl bootout "gui/$(id -u)/dev.herdsman.review-board" >/dev/null 2>&1 || true
  if launchctl bootstrap "gui/$(id -u)" "${PLIST}" 2>/dev/null; then
    echo "  ✓ ${PLIST}（每 30 秒生成 ~/.review/board.html）"
  else
    echo "  ✗ launchctl bootstrap 失败：${PLIST}"
  fi
  # 看板的本机服务（放行 / 放弃按钮）：常驻，挂了自动拉起；重装时先卸再装，用上新版本
  SPLIST="${AGENTS}/dev.herdsman.review-board-serve.plist"
  sed "s|__HOME__|${HOME}|g" "${SRC}/templates/review-board-serve.plist" > "${SPLIST}"
  launchctl bootout "gui/$(id -u)/dev.herdsman.review-board-serve" >/dev/null 2>&1 || true
  if launchctl bootstrap "gui/$(id -u)" "${SPLIST}" 2>/dev/null; then
    echo "  ✓ ${SPLIST}（看板带按钮的版本：http://127.0.0.1:10086/）"
  else
    echo "  ✗ launchctl bootstrap 失败：${SPLIST}"
  fi
fi

echo
missing=0
for c in jq herdr git python3; do
  command -v "$c" >/dev/null || { echo "  ✗ 缺少 ${c}"; missing=1; }
done
case ":${PATH}:" in
  *":${BIN}:"*) ;;
  *) echo "  ✗ ${BIN} 不在 PATH 中，请加进 ~/.zshrc"; missing=1;;
esac
[ "${missing}" -eq 0 ] && echo "  ✓ 依赖检查通过"

echo
echo "下一步：在项目目录里运行  herdsman-init <短名>"
