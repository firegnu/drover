#!/usr/bin/env python3
"""cmd_list 的严格 UTF-8 输出回归；仅使用临时文件和内存队列。"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DROVER = Path(os.environ.get("DROVER_BIN", ROOT / "bin/drover")).resolve()
NORMAL = "中文🙂甲\u00a0乙\u0085丙\u2028丁\u2029尾"
BAD = "异常\ud800甲\udbff乙\udc00丙\udcff丁\udfff尾"
ESCAPED = "异常\\ud800甲\\udbff乙\\udc00丙\\udcff丁\\udfff尾"

# -I 隔离调用者的 Python 环境，再显式固定严格 UTF-8，裸 print 必须失败。
RUN_LIST = r'''
import copy, json, runpy, sys
from pathlib import Path
sys.stdout.reconfigure(encoding="utf-8", errors="strict")
sys.stderr.reconfigure(encoding="utf-8", errors="strict")
ns = runpy.run_path(sys.argv[1])
d = ns["cmd_list"].__globals__
root = Path(sys.argv[2])
for key, name in (("Q", "queue.md"), ("S", "tasks.state"),
                  ("PAUSED", "paused"), ("LOOP", "loop")):
    d[key] = str(root / name)
vm = d["fold"]()
blocks = d["parse_queue"]()
blocks[0]["title"] = json.load(sys.stdin)
before = copy.deepcopy((vm, blocks))
d["fold"] = lambda: vm
d["parse_queue"] = lambda: blocks
try:
    code = d["cmd_list"]()
finally:
    assert (vm, blocks) == before, "list modified task/queue data"
sys.exit(code)
'''


class ListOutput(unittest.TestCase):
    def test_task_text_is_safe_and_read_only(self):
        for field in ("normal", "current", "pending", "done", "dropped", "reason"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                titles = {name: NORMAL for name in ("current", "done", "dropped")}
                reason = NORMAL
                if field in titles:
                    titles[field] = BAD + NORMAL
                elif field == "reason":
                    reason = BAD + NORMAL
                events = [
                    {"ev": "start", "id": "T1", "title": "后续正常条目", "sha": "aaaaaaa", "t": 60},
                    {"ev": "done", "id": "T1", "sha": "bbbbbbb", "t": 180},
                    {"ev": "start", "id": "T2", "title": titles["done"], "sha": "aaaaaaa", "t": 60},
                    {"ev": "done", "id": "T2", "sha": "bbbbbbb", "t": 180},
                    {"ev": "drop", "id": "T3", "title": titles["dropped"], "reason": reason},
                    {"ev": "start", "id": "T4", "title": titles["current"], "sha": "aaaaaaa"},
                ]
                (root / "tasks.state").write_text(
                    "".join(json.dumps(e) + "\n" for e in events), encoding="utf-8")
                # 完整待办文字只在子进程内存中加入；不改变生产解析规则。
                (root / "queue.md").write_text(
                    "## T5 中文待办\n\n## T6 后续待办条目\n", encoding="utf-8")
                before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in root.iterdir()}
                actual = subprocess.run(
                    [sys.executable, "-I", "-c", RUN_LIST, str(DROVER), tmp],
                    input=json.dumps((BAD if field == "pending" else "") + NORMAL).encode("ascii"),
                    cwd=tmp, capture_output=True)
                after = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in root.iterdir()}
                self.assertEqual(after, before, "list 不得改写原始文件")
                self.assertEqual(actual.returncode, 0, actual.stderr.decode("utf-8"))
                self.assertEqual(actual.stderr, b"")
                shown = {name: NORMAL for name in ("current", "pending", "done", "dropped", "reason")}
                if field != "normal":
                    shown[field] = ESCAPED + NORMAL
                expected = (
                    "模式：放行模式\n\n进行中：\n"
                    f"  T4 {shown['current']}（开始于 aaaaaaa）\n"
                    "\n队列：\n"
                    f"  1. T5 {shown['pending']}  ← 下一个\n"
                    "  2. T6 后续待办条目\n"
                    "\n已完成 / 放弃：\n"
                    f"  T3 {shown['dropped']} · 放弃：{shown['reason']}\n"
                    f"  T2 {shown['done']} · 2m · aaaaaaa..bbbbbbb\n"
                    "  T1 后续正常条目 · 2m · aaaaaaa..bbbbbbb\n"
                )
                self.assertEqual(actual.stdout.decode("utf-8"), expected)


if __name__ == "__main__":
    unittest.main()
