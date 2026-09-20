#!/bin/sh
# shell 只负责启动；安装逻辑仅用 Python 标准库。
set -eu
exec python3 - "$0" <<'PY'
import os
from pathlib import Path
import plistlib
import shlex
import sys

root = Path(sys.argv[1]).resolve().parent
home = Path(os.environ["HOME"]).absolute()
bindir = home / ".local/bin"
state = home / ".drover"
links = [(bindir / name, root / "bin" / name) for name in ("drover", "drover-board")]
plist = state / "dev.drover.loop.plist"
config = plistlib.loads((root / "launchd" / plist.name).read_bytes())
# launchd 不展开 ~、环境变量，也不读 shell rc；先展开路径再交给 plistlib 转义 XML。
config["ProgramArguments"][0] = str(bindir / "drover")
config["EnvironmentVariables"] = {
    "HOME": str(home),
    "PATH": os.pathsep.join(dict.fromkeys(
        [str(bindir)] + os.environ.get("PATH", os.defpath).split(os.pathsep))),
}
config["StandardOutPath"] = str(state / "loop.stdout.log")
config["StandardErrorPath"] = str(state / "loop.stderr.log")
plist_bytes = plistlib.dumps(config, sort_keys=False)
# 先检查全部目标，再写入；断链也算已占用，不能用 exists() 漏掉它。
for target, source in links:
    if not source.is_file() or not os.access(source, os.X_OK):
        sys.exit(f"ERROR: 源命令不存在或不可执行：{source}")
    if os.path.lexists(target) and not (target.is_symlink() and os.readlink(target) == str(source)):
        sys.exit(f"ERROR: 拒绝覆盖不认识的目标：{target}")
if os.path.lexists(plist) and (
    plist.is_symlink() or not plist.is_file() or plist.read_bytes() != plist_bytes
):
    sys.exit(f"ERROR: 拒绝覆盖不认识的目标：{plist}（内容或安装时的 PATH 已变，请人工核对）")

bindir.mkdir(parents=True, exist_ok=True)
state.mkdir(parents=True, exist_ok=True)
for target, source in links:
    if not os.path.lexists(target):
        target.symlink_to(source)
    print(f"已安装：{target}")
if not os.path.lexists(plist):
    with plist.open("xb") as stream:
        stream.write(plist_bytes)
print(f"已生成（尚未启用）：{plist}")

if str(bindir) not in os.environ.get("PATH", "").split(os.pathsep):
    print(f"提示：{bindir} 不在 PATH 中，请自行加入；安装脚本不修改 shell 配置。")
agent = home / "Library/LaunchAgents" / plist.name
print("可选：以下命令需人工执行；会登记登录时启动的引擎，并立即启动 drover loop，退出后自动重启。")
print("请先确认 PATH 能找到 python3、git、corral；启用后不要再同时手动运行引擎。")
print("若目标 plist 已存在，先人工核对，不要覆盖或重复加载；本脚本不执行下列命令：")
print(f"mkdir -p {shlex.quote(str(agent.parent))}")
print(f"ln -s {shlex.quote(str(plist))} {shlex.quote(str(agent))}")
print(f"launchctl bootstrap gui/{os.getuid()} {shlex.quote(str(agent))}")
print("下一步：在目标仓库运行 drover init <短名>，向交接目录的 queue.md 加任务，")
print("配置主控后运行 drover loop on；未启用 launchd 时运行 drover loop（默认每 5 秒一跳）。")
PY
