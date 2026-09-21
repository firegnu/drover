#!/usr/bin/env python3
""".check-result 的写入、显示和判断边界；只用合成仓库与假 corral。"""
import importlib.machinery
import importlib.util
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
DROVER = Path(os.environ.get("DROVER_BIN", ROOT / "bin/drover"))
BOARD = Path(os.environ.get("DROVER_BOARD_BIN", ROOT / "bin/drover-board"))


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(mod)
    return mod


class CheckResult(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.d = self.root / "handoff"
        self.d.mkdir()
        self.result = self.d / ".check-result"
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "test")
        self.git("config", "user.email", "test@example.com")
        self.git("commit", "-q", "--allow-empty", "-m", "base")
        self.base = self.git("rev-parse", "main")
        self.git("commit", "-q", "--allow-empty", "-m", "收尾: test")
        self.sha = self.git("rev-parse", "main")
        self.projects = self.root / "projects"
        self.projects.write_text(str(self.repo) + "\n")
        self.corral = self.root / "corral"
        self.corral.write_text('#!/bin/sh\nprintf \'{"ok":true,"agents":[],"state":"idle",'
                               '"idle_for":999,"last_input_source":"send"}\\n\'\n')
        self.corral.chmod(0o755)
        self.env = {**os.environ, "DROVER_CORRAL_BIN": str(self.corral)}
        self.B = load("board_check_result", BOARD)
        self.B.CORRAL = str(self.corral)
        self.configure("true")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], text=True).strip()

    def configure(self, cmd, body=""):
        (self.repo / ".drover.conf").write_text(
            f"HANDOFF_DIR={self.d}\nCHECK_CMD={cmd}\nMAIN_AGENT=test/main\n")
        self.task = {"t": 100, "ev": "start", "id": "T1", "title": "test",
                     "body": body, "main": self.base, "sha": self.base}
        (self.d / "queue.md").write_text("## T1 test\n\n" + body + "\n")
        (self.d / "tasks.state").write_text(json.dumps(self.task) + "\n")

    def done(self):
        return subprocess.run([sys.executable, str(DROVER), "done", "T1"], cwd=self.repo,
                              env=self.env, capture_output=True, text=True)

    def saved(self, **changes):
        return {"task": "T1", "main": self.sha, "cmd": "true", "ok": True,
                "why": "`true` 过了", "t": time.time() - 180, **changes}

    def display(self):
        before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.d.iterdir()}
        vm = self.B.view_model(self.B.collect(str(self.projects)))
        p = vm["projects"][0]
        row = p["queue"]["card"]["criteria"][3]
        text = "\n".join(line[2] for line in self.B.detail_lines(p))
        after = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.d.iterdir()}
        self.assertEqual(before, after, "看板刷新必须只读")
        return row, text

    def test_done_writes_result(self):
        for cmd, body, effective, ok, code in [
                ("false", "验收：true", "true", True, 8),
                ("true", "验收：echo failed; exit 1", "echo failed; exit 1", False, 9),
                ("", "", "", None, 8)]:
            with self.subTest(ok=ok):
                self.configure(cmd, body)
                before = int(time.time())
                r = self.done()
                self.assertEqual(r.returncode, code, r.stdout + r.stderr)
                self.assertTrue(self.result.exists(), "done 未写 .check-result")
                saved = json.loads(self.result.read_text())
                self.assertEqual(set(saved), {"task", "main", "cmd", "ok", "why", "t"})
                self.assertEqual((saved["task"], saved["main"], saved["cmd"]),
                                 ("T1", self.sha, effective))
                self.assertIs(saved["ok"], ok)
                self.assertTrue(saved["why"])
                self.assertLessEqual(before, saved["t"])
                self.assertLessEqual(saved["t"], time.time())

    def test_board_matching_results(self):
        # 若渲染真跑验收，会留下这个文件；只看 ok 不足以守住此边界。
        check_marker = self.root / "unexpected-check"
        cmd = f"touch {check_marker}"
        self.configure("false", "验收：" + cmd)
        for ok in (True, False):
            with self.subTest(ok=ok):
                self.result.write_text(json.dumps(self.saved(cmd=cmd, ok=ok, why="核对结果")))
                row, text = self.display()
                self.assertIs(row["ok"], ok)
                self.assertIn("核对结果", row["why"])
                self.assertIn("3m 前跑的", text)
                self.assertIn(("✓" if ok else "✗") + " 验收命令过了", text)
                self.assertFalse(check_marker.exists(), "看板不得跑验收命令")

    def test_board_stale_results(self):
        for key, value, reason in [("task", "T2", "任务 id 不一致"),
                                   ("main", self.base, "main sha 不一致"),
                                   ("cmd", "false", "验收命令不一致")]:
            with self.subTest(key=key):
                self.result.write_text(json.dumps(self.saved(**{key: value})))
                row, text = self.display()
                self.assertIsNone(row["ok"])
                self.assertIn(reason, row["why"])
                self.assertIn("– 验收命令过了", text)
                self.assertNotIn("前跑的", text)

    def test_board_missing_and_invalid_results(self):
        row, text = self.display()
        self.assertIsNone(row["ok"])
        self.assertIn("没跑过", row["why"])
        invalid = [b"not json", b"", b'{"ok":true}', b'[]', b'null', b'\xff']
        invalid += [json.dumps(self.saved(**{key: value})).encode() for key, value in
                    [("t", "yesterday"), ("t", float("nan")), ("t", float("inf")),
                     ("t", True), ("ok", 1), ("why", []), ("cmd", None)]]
        for raw in invalid:
            with self.subTest(raw=raw):
                self.result.write_bytes(raw)
                row, text = self.display()
                self.assertIsNone(row["ok"])
                self.assertIn("没跑过", row["why"])
                self.assertIn("– 验收命令过了", text)

    def test_board_not_applicable_is_not_missing(self):
        self.configure("")
        missing, _ = self.display()
        self.assertIn("没跑过", missing["why"])
        self.assertEqual(self.done().returncode, 8)
        row, text = self.display()
        self.assertIsNone(row["ok"])
        self.assertIn("不适用", row["why"])
        self.assertNotIn("没跑过", row["why"])
        self.assertIn("前跑的", text)

    def test_done_publishes_once_atomically(self):
        counter = self.root / "checks"
        # 第一次过、第二次不过：保留既有的两次执行，只发布第一次判断的结果。
        self.configure(f"echo run >> {counter}; test $(wc -l < {counter}) -eq 1")
        D = load("drover_check_result", DROVER)
        previous_cwd = os.getcwd()
        try:
            os.chdir(self.repo)
            D.setup()
        finally:
            os.chdir(previous_cwd)
        self.result.write_text("previous complete result")
        real_open, real_replace = open, os.replace
        published = []

        def guarded_open(path, mode="r", *args, **kwargs):
            if os.fspath(path) == str(self.result):
                self.assertFalse(any(m in mode for m in "wax+"), "不得直接写目标文件")
            return real_open(path, mode, *args, **kwargs)

        def replace(src, dst):
            self.assertEqual(Path(dst), self.result)
            self.assertEqual(Path(src).parent, self.d, "tmp 必须在同一文件系统")
            self.assertIn(str(D.os.getpid()), Path(src).name, "tmp 名必须按进程区分")
            self.assertNotEqual(Path(src), self.result)
            self.assertEqual(self.result.read_text(), "previous complete result",
                             "发布前读者必须仍看见完整旧文件")
            saved = json.loads(Path(src).read_text())
            self.assertIs(saved["ok"], True)
            real_replace(src, dst)
            self.assertEqual(json.loads(self.result.read_text()), saved)
            published.append(Path(src).name)

        for pid in (12345, 23456):
            with patch("builtins.open", guarded_open), patch.object(D.os, "replace", replace), \
                    patch.object(D.os, "getpid", return_value=pid), redirect_stdout(io.StringIO()):
                self.assertEqual(D.cmd_done("T1"), 8)
            self.assertEqual(counter.read_text().splitlines(), ["run", "run"])
            self.assertIs(json.loads(self.result.read_text())["ok"], True)
            self.assertFalse(list(self.d.glob(".check-result.*.tmp")))
            counter.write_text("")
            self.configure(D.CHECK_CMD)
            self.result.write_text("previous complete result")
        self.assertEqual(len(published), 2, "每次 done 只能发布一次")
        self.assertNotEqual(*published, "不同进程的 tmp 不能撞名")

    def test_main_is_captured_before_check(self):
        self.configure("git commit -q --allow-empty -m during-check")
        self.assertEqual(self.done().returncode, 8)
        saved = json.loads(self.result.read_text())
        self.assertEqual(saved["main"], self.sha)
        self.assertNotEqual(saved["main"], self.git("rev-parse", "main"))
        row, _ = self.display()
        self.assertIn("main sha 不一致", row["why"])

    def test_result_never_enters_decisions(self):
        self.configure("false")
        B = self.B
        before = B.criteria(str(self.repo), self.base, "false")
        unchecked = B.criteria(str(self.repo), self.base, "false", do_check=False)
        baseline = self.done()
        self.assertEqual(baseline.returncode, 9)
        original_state = (self.d / "tasks.state").read_bytes()
        conf = B.parse_conf(str(self.repo / ".drover.conf"))
        (self.d / "loop").touch()
        self.result.unlink()
        B.loop_tick(str(self.projects))
        baseline_log = (self.d / ".loop.log").read_text().split(" done ", 1)[1].strip()
        original_open = open

        def forbid_read(path, mode="r", *args, **kwargs):
            if os.fspath(path) == str(self.result) and ("r" in mode or "+" in mode):
                raise AssertionError("判断路径读了 .check-result")
            return original_open(path, mode, *args, **kwargs)

        for raw in (json.dumps(self.saved(cmd="false")).encode(), b"not json", b"\xff"):
            with self.subTest(raw=raw):
                self.result.write_bytes(raw)
                with patch("builtins.open", forbid_read):
                    self.assertEqual(B.criteria(str(self.repo), self.base, "false"), before)
                    self.assertEqual(B.criteria(str(self.repo), self.base, "false", do_check=False), unchecked)
                    # collect 中的「等你」判断也不能因为这个文件改变。
                    self.assertTrue(B.project_state(str(self.repo), conf)["needs_me"] is False)
                    (self.d / ".criteria-checked").unlink()
                    B.loop_tick(str(self.projects))
                self.assertEqual((self.d / "tasks.state").read_bytes(), original_state)
                log = (self.d / ".loop.log").read_text().splitlines()[-1].split(" done ", 1)[1]
                self.assertEqual(log, baseline_log)
                self.result.write_bytes(raw)
                r = self.done()
                self.assertEqual((r.returncode, r.stdout, r.stderr),
                                 (baseline.returncode, baseline.stdout, baseline.stderr))
        # 成功路径也是真正通过 loop_tick → drover done 写入，非只覆盖手动命令。
        self.configure("true")
        (self.d / ".criteria-checked").unlink()
        B.loop_tick(str(self.projects))
        events = B.task_events((self.d / "tasks.state").read_text())
        self.assertEqual([e["ev"] for e in events], ["start", "done"])
        self.assertIs(json.loads(self.result.read_text())["ok"], True)


if __name__ == "__main__":
    unittest.main()
