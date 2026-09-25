#!/usr/bin/env python3
"""从 CLI 核对 list JSON、原文本和只读边界；仅使用临时仓库及假 corral。"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


CLI = Path(__file__).resolve().parents[1] / "bin/drover"


def main():
    with tempfile.TemporaryDirectory(prefix="drover-list-json-") as tmp:
        root = Path(tmp)
        repo, data, home = root / "repo", root / "handoff", root / "home"
        for path in (repo, data, home):
            path.mkdir()
        fake = root / "corral"
        fake.write_text('#!/bin/sh\nprintf called >> "$CORRAL_CALL_LOG"\nexit 1\n')
        fake.chmod(0o755)
        env = {**os.environ, "HOME": str(home), "DROVER_CORRAL_BIN": str(fake),
               "CORRAL_CALL_LOG": str(root / "called"), "DROVER_BOARD_ENGLISH": "0"}
        subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], env=env, check=True)

        def configure(directory, gate=1):
            (repo / ".drover.conf").write_text(
                f"HANDOFF_DIR={directory}\nTASK_GATE={gate}\nMAIN_AGENT=fake/main\n",
                encoding="utf-8")

        def snapshot():
            return {str(p.relative_to(root)): (p.read_bytes(), p.stat().st_mtime_ns)
                    if p.is_file() else None for p in root.rglob("*")}

        def run(*args):
            before = snapshot()
            result = subprocess.run([sys.executable, str(CLI), "list", *args],
                                    cwd=repo, env=env, capture_output=True, text=True)
            assert snapshot() == before, "list changed files or contacted corral"
            assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
            assert not result.stderr, result.stderr
            return result.stdout

        configure(data)
        queue = "## T30 排在前面\n说明甲\n\n## 手写待办\n说明乙\n\n## T20 排在后面\n\n"
        queue += "## T12 正在做\n旧正文\n\n## 放弃的手写任务\n\n## T10 已完成\n"
        (data / "queue.md").write_text(queue, encoding="utf-8")
        events = []
        for n in range(1, 11):
            events.extend([
                {"ev": "start", "id": f"T{n}", "title": "已完成", "sha": "aaaaaaa1", "t": 60},
                {"ev": "done", "id": f"T{n}", "sha": "bbbbbbb2", "t": 180, "gate": False},
            ])
        events.extend([
            {"ev": "drop", "id": "T11", "title": "放弃的手写任务", "key": "放弃的手写任务",
             "reason": "不做了", "t": 200},
            {"ev": "start", "id": "T12", "title": "正在做", "body": "已发出的正文",
             "sha": "ccccccc3", "main": "aaaaaaa1", "t": 240},
        ])
        state = data / "tasks.state"
        state.write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in events), encoding="utf-8")
        (data / "loop").touch()
        (data / "paused").touch()
        expected_text = (
            "模式：循环 + 放行模式（自动核对判据，下一件等人放行）（已暂停）\n"
            "\n进行中：\n  T12 正在做（开始于 ccccccc）\n"
            "\n队列：\n  1. T30 排在前面  ← 下一个\n  2. （未编号） 手写待办\n  3. T20 排在后面\n"
            "\n已完成 / 放弃：\n  T11 放弃的手写任务 · 放弃：不做了\n"
        ) + "".join(f"  T{n} 已完成 · 2m · aaaaaaa..bbbbbbb\n" for n in range(10, 1, -1))
        assert run() == expected_text, "plain list output changed"
        result = json.loads(run("--json"))
        assert result["mode"] == {"loop": True, "gate": True}
        assert result["paused"] is True and result["awaiting"] is None
        current = result["current"]
        assert (current["id"], current["status"], current["body"], current["start"]) == (
            "T12", "doing", "已发出的正文", "ccccccc3")
        assert result["pending"] == [
            {"id": "T30", "title": "排在前面", "body": "说明甲"},
            {"id": None, "title": "手写待办", "body": "说明乙"},
            {"id": "T20", "title": "排在后面", "body": ""},
        ]
        history = result["history"]
        assert [t["id"] for t in history] == [f"T{n}" for n in range(11, 0, -1)], "JSON history must include records older than the latest ten"
        assert history[0]["status"] == "dropped" and history[0]["reason"] == "不做了"
        assert all(t["status"] == "done" and t["end"] == "bbbbbbb2" for t in history[1:])

        with state.open("a", encoding="utf-8") as f:
            f.write(json.dumps({"ev": "done", "id": "T12", "sha": "ddddddd4", "t": 300, "gate": True}) + "\n")
        result = json.loads(run("--json"))
        assert result["current"] is None
        assert result["awaiting"]["id"] == "T12" and result["awaiting"]["status"] == "done"
        assert result["history"][0] == result["awaiting"]

        configure(root / "missing-handoff", gate=0)
        assert json.loads(run("--json")) == {
            "mode": {"loop": False, "gate": False}, "paused": False,
            "current": None, "awaiting": None, "pending": [], "history": [],
        }
    print("PASS list JSON: queue order, states, complete history, plain output and read-only access")


if __name__ == "__main__":
    main()
