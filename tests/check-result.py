#!/usr/bin/env python3
""".check-result 的写入、显示和判断边界；只用合成仓库与假 corral。"""
import importlib.machinery
import importlib.util
import fcntl
from contextlib import contextmanager, redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import select
import subprocess
import struct
import sys
import tempfile
import termios
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

    def strict_cli(self, *args):
        code = ("import runpy, sys; "
                "sys.stdout.reconfigure(encoding='utf-8', errors='strict'); "
                "sys.stderr.reconfigure(encoding='utf-8', errors='strict'); "
                "sys.argv = sys.argv[1:]; runpy.run_path(sys.argv[0], run_name='__main__')")
        # -I 忽略调用者的 Python 环境；流编码也显式固定，不设置 PYTHONIOENCODING。
        return subprocess.run([sys.executable, "-I", "-c", code, str(DROVER), *args],
                              cwd=self.repo, env=self.env, capture_output=True)

    def saved(self, **changes):
        return {"task": "T1", "main": self.sha, "cmd": "true", "ok": True,
                "why": "`true` 过了", "t": time.time() - 180, **changes}

    def display(self):
        before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.d.iterdir()}
        vm = self.B.view_model(self.B.collect(str(self.projects)))
        p = vm["projects"][0]
        row = p["queue"]["card"]["criteria"][3]
        text = "\n".join(line[2] for line in self.B.detail_lines(p))
        self.draw(vm)
        after = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.d.iterdir()}
        self.assertEqual(before, after, "看板刷新必须只读")
        return row, text

    def draw(self, vm):
        case = self

        class Screen:
            def getmaxyx(self): return (40, 120)
            def erase(self): self.lines = []
            def addstr(self, y, x, text, attr=0):
                if "\0" in text:
                    raise ValueError("embedded null character")
                text.encode("utf-8")
                case.assertLessEqual(x + case.B.width(text), 120)
                self.lines.append(text)

        screen = Screen()
        self.B.draw(screen, vm, {"sel": 0, "msg": ""})
        self.assertTrue(any("验收命令过了" in line for line in screen.lines),
                        "必须实际绘制第 3 条，不能被视口或截断绕过")

    def test_nul_output_reaches_real_draw(self):
        self.configure(r"printf '\000'; exit 1")
        r = self.done()
        self.assertEqual(r.returncode, 9, r.stderr)
        self.assertIn("\0", json.loads(self.result.read_text())["why"])
        # 用真实 curses 的 addstr 验证，不依赖假屏幕自己声称 NUL 会抛异常。
        master, slave = os.openpty()
        try:
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
            code = """
import curses, runpy, sys
m = runpy.run_path(sys.argv[1])
B = m['load']('draw_check', sys.argv[2])
vm = B.view_model(B.collect(sys.argv[3]))
curses.wrapper(lambda screen: B.draw(screen, vm, {'sel': 0, 'msg': ''}))
"""
            with tempfile.TemporaryFile() as errors:
                proc = subprocess.Popen(
                    [sys.executable, "-B", "-c", code, __file__, str(BOARD), str(self.projects)],
                    stdin=slave, stdout=slave, stderr=errors,
                    env={**self.env, "TERM": "xterm-256color"})
                try:
                    deadline = time.monotonic() + 15
                    while proc.poll() is None and time.monotonic() < deadline:
                        if select.select([master], [], [], 0.1)[0]:
                            os.read(master, 65536)  # 前台排空终端输出，避免 PTY 缓冲堵塞。
                    self.assertIsNotNone(proc.poll(), "PTY 绘制超时")
                finally:
                    if proc.poll() is None:
                        proc.kill()
                    proc.wait()
                errors.seek(0)
                self.assertEqual(proc.returncode, 0, errors.read().decode())
        finally:
            os.close(slave)
            os.close(master)
        row, _ = self.display()
        self.assertIsNone(row["ok"])
        self.assertIn("没跑过", row["why"])

    def test_deep_json_and_parser_recursion(self):
        self.result.write_text("[" * 1200 + "0" + "]" * 1200)
        row, _ = self.display()
        self.assertIsNone(row["ok"])
        # 不依赖具体 Python 的 JSON 解析器是否使用递归，强制覆盖这个错误出口。
        p = self.B.collect(str(self.projects))[0]
        with patch.object(self.B.json, "loads", side_effect=RecursionError("deep JSON")):
            card = self.B.card_vm(p, p["tasks"])
        self.assertIsNone(card["criteria"][3]["ok"])
        self.assertIn("没跑过", card["criteria"][3]["why"])

    def test_done_writes_result(self):
        # 正文里的「验收：…」只是散文：CHECK_CMD 是唯一来源（覆盖语法 2026-09-21 删了）。
        for cmd, body, effective, ok, code in [
                ("true", "验收：echo failed; exit 1", "true", True, 8),
                ("echo failed; exit 1", "验收：true", "echo failed; exit 1", False, 9),
                ("", "验收：true", "", None, 8)]:
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

    def test_publish_failure_preserves_done_and_advance(self):
        def events():
            return [{k: v for k, v in e.items() if k != "t"}
                    for e in self.B.task_events((self.d / "tasks.state").read_text())]

        for cmd in ("true", "false"):
            for gate in (0, 1):
                with self.subTest(cmd=cmd, gate=gate):
                    def reset():
                        self.configure(cmd)
                        with (self.repo / ".drover.conf").open("a") as f:
                            f.write(f"TASK_GATE={gate}\n")
                        with (self.d / "queue.md").open("a") as f:
                            f.write("\n## T2 next\n")

                    reset()
                    baseline = self.done()
                    expected = events()
                    self.assertEqual(baseline.returncode, 9 if cmd == "false" else 8 if gate else 0)
                    self.result.unlink()
                    self.result.mkdir()
                    reset()
                    try:
                        actual = self.done()
                        self.assertEqual((actual.returncode, actual.stdout),
                                         (baseline.returncode, baseline.stdout), actual.stderr)
                        self.assertEqual(events(), expected, "显示记录故障不能阻止 done 或推进下一件")
                        self.assertIn(".check-result", actual.stderr)
                        self.assertIn("未能发布", actual.stderr)
                        self.assertTrue(self.result.is_dir(), "不能删除异常目标")
                    finally:
                        self.result.rmdir()

    def test_surrogate_body_preserves_done(self):
        for cmd, code in (("true", 8), ("false", 9)):
            with self.subTest(cmd=cmd):
                self.configure(cmd)
                self.task["body"] = "验收：正常前缀\ud800正常中间\udfff正常后缀"
                state = self.d / "tasks.state"
                state.write_text(json.dumps(self.task) + "\n", encoding="utf-8")
                actual = self.strict_cli("done", "T1")
                self.assertEqual(actual.returncode, code, actual.stderr)
                self.assertNotIn(b"UnicodeEncodeError", actual.stderr)
                self.assertEqual(self.B.task_events(state.read_text())[0], self.task)

    def test_surrogate_body_manual_resend(self):
        with (self.repo / ".drover.conf").open("a") as f:
            f.write("MAIN_AGENT=\n")
        self.task["body"] = "正文\ud800甲\udbff乙\udc00丙\udcff丁\udfff尾\u00a0🙂"
        state = self.d / "tasks.state"
        original = json.dumps(self.task) + "\n"
        state.write_text(original, encoding="utf-8")
        actual = self.strict_cli("next")
        self.assertEqual(actual.returncode, 0, actual.stderr)
        self.assertEqual(actual.stderr, b"")
        self.assertIn("正文\\ud800甲\\udbff乙\\udc00丙\\udcff丁\\udfff尾\u00a0🙂",
                      actual.stdout.decode("utf-8"))
        self.assertEqual(state.read_text(), original, "输出不能改写任务正文")

    def test_publish_encoding_error_preserves_done(self):
        D = load("drover_encoding_check", DROVER)
        for cmd, code in (("true", 8), ("false", 9)):
            with self.subTest(cmd=cmd):
                self.configure(cmd)
                previous = os.getcwd()
                try:
                    os.chdir(self.repo)
                    D.setup()
                finally:
                    os.chdir(previous)
                # 正文已不再覆盖 CHECK_CMD；直接给核对入口传入含代理码的命令。
                # U+DCFF 可经 POSIX surrogateescape 传给 shell，注释不影响执行。
                D.CHECK_CMD = cmd + " # 正常前缀\udcff正常后缀"
                rows = D.B.criteria(str(self.repo), self.base, D.CHECK_CMD)
                why = ("`" + D.CHECK_CMD + "` " + ("过了" if code == 8 else "退出码 1"))
                self.assertEqual(rows[2]["why"], why)
                self.assertIs(rows[2]["ok"], code == 8)
                self.assertIn(why, D.criteria_report(self.task, rows)[-1])
                self.assertEqual(rows[2]["why"], why, "报告生成不能改写判据理由")
                self.result.write_text("previous complete result", encoding="utf-8")
                # 自建严格流，不继承调用者 stdout 的编码或错误策略。
                with io.TextIOWrapper(io.BytesIO(), encoding="utf-8", errors="strict") as output, \
                        io.TextIOWrapper(io.BytesIO(), encoding="utf-8", errors="strict") as errors:
                    with redirect_stdout(output), redirect_stderr(errors):
                        actual = D.cmd_done("T1")
                    output.flush()
                    errors.flush()
                    stdout = output.buffer.getvalue().decode("utf-8")
                    stderr = errors.buffer.getvalue().decode("utf-8")
                self.assertEqual(actual, code)
                self.assertNotIn("UnicodeEncodeError", stderr)
                self.assertIn("正常前缀\\udcff正常后缀", stdout)
                self.assertIn("WARNING: 未能发布", stderr)
                self.assertIn(".check-result", stderr)
                self.assertIn("surrogates not allowed", stderr)
                self.assertEqual(self.result.read_text(), "previous complete result")
                self.assertEqual(D.B.criteria(str(self.repo), self.base, D.CHECK_CMD), rows,
                                 "显示不能改写判据理由")
                events = self.B.task_events((self.d / "tasks.state").read_text())
                self.assertEqual([e["ev"] for e in events],
                                 ["start", "done"] if code == 8 else ["start"])

    def test_publish_io_errors_preserve_check_done(self):
        D = load("drover_io_check", DROVER)
        for cmd in ("true", "false"):
            self.configure(cmd)
            previous = os.getcwd()
            try:
                os.chdir(self.repo)
                D.setup()
            finally:
                os.chdir(previous)
            expected_problems, expected_rows = D.check_done(self.task)
            real_open = open

            def denied_tmp(path, mode="r", *args, **kwargs):
                if os.fspath(path) == str(self.result) + f".{os.getpid()}.tmp":
                    raise PermissionError("tmp denied")
                return real_open(path, mode, *args, **kwargs)

            for failure in (patch("builtins.open", denied_tmp),
                            patch.object(D.json, "dump", side_effect=OSError("disk full")),
                            patch.object(D.os, "replace", side_effect=OSError("replace denied"))):
                with failure, redirect_stderr(io.StringIO()) as errors:
                    self.assertEqual(D.check_done(self.task), (expected_problems, expected_rows))
                self.assertIn("未能发布", errors.getvalue())

    def test_board_matching_results(self):
        # 若渲染真跑验收，会留下这个文件；只看 ok 不足以守住此边界。
        check_marker = self.root / "unexpected-check"
        cmd = f"touch {check_marker}"
        self.configure(cmd)
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
                     ("t", True), ("ok", 1), ("why", []), ("cmd", None), ("why", "\ud800")]]
        for raw in invalid:
            with self.subTest(raw=raw):
                self.result.write_bytes(raw)
                row, text = self.display()
                self.assertIsNone(row["ok"])
                self.assertIn("没跑过", row["why"])
                self.assertIn("– 验收命令过了", text)

    def test_record_and_reason_limits(self):
        for length, expected in ((4096, True), (4097, None), (2 * 1024 * 1024, None)):
            with self.subTest(why_length=length):
                self.result.write_text(json.dumps(self.saved(why="x" * length)))
                row, _ = self.display()
                self.assertIs(row["ok"], expected)
        content = json.dumps(self.saved())
        self.result.write_text(content + " " * (65536 - len(content)))
        self.assertIs(self.display()[0]["ok"], True)
        with self.result.open("a") as f:
            f.write(" ")
        self.assertIsNone(self.display()[0]["ok"])

        # 实测单次读取量，避免只在无界 read() 之后检查长度而伪装成有界读取。
        self.result.write_text(json.dumps(self.saved(why="x" * (2 * 1024 * 1024))))
        p = self.B.collect(str(self.projects))[0]
        real_open, reads = open, []

        class Reader:
            def __init__(self, file): self.file = file
            def __enter__(self): return self
            def __exit__(self, *args): self.file.close()
            def read(self, size=-1):
                data = self.file.read(size)
                reads.append((size, len(data)))
                return data

        def observed_open(path, *args, **kwargs):
            file = real_open(path, *args, **kwargs)
            return Reader(file) if os.path.realpath(path) == os.path.realpath(self.result) else file

        with patch("builtins.open", observed_open):
            card = self.B.card_vm(p, p["tasks"])
        self.assertIsNone(card["criteria"][3]["ok"])
        self.assertTrue(reads)
        self.assertTrue(all(0 < size <= 65537 for size, _ in reads), reads)
        self.assertLessEqual(sum(length for _, length in reads), 65537)

    def test_future_time_and_collection_skew(self):
        now = int(time.time())
        with patch.object(self.B.time, "time", return_value=now):
            self.result.write_text(json.dumps(self.saved(t=now + 86400)))
            row, text = self.display()
            self.assertIsNone(row["ok"])
            self.assertIn("没跑过", row["why"])
            self.assertNotIn("0s 前跑的", text)
            self.result.write_text(json.dumps(self.saved(t=now + 3)))
            self.assertIs(self.display()[0]["ok"], True)
            p = self.B.collect(str(self.projects))[0]
        self.result.write_text(json.dumps(self.saved(t=now + 59)))
        with patch.object(self.B.time, "time", return_value=now + 60):
            vm = self.B.view_model([p])
            self.draw(vm)
        row = vm["projects"][0]["queue"]["card"]["criteria"][3]
        self.assertIs(row["ok"], True, "采集耗时不能把正常并发发布的记录误判为未来")
        self.assertIn("1s 前跑的", row["name"])

    def test_check_row_is_selected_by_number(self):
        self.result.write_text(json.dumps(self.saved(ok=False, why="上次核对失败")))
        p = self.B.collect(str(self.projects))[0]
        criteria = self.B.criteria

        def reordered(*args, **kwargs):
            rows = criteria(*args, **kwargs)
            return [rows[2], rows[0], rows[1]]

        with patch.object(self.B, "criteria", reordered):
            card = self.B.card_vm(p, p["tasks"])
        self.assertIs(card["criteria"][1]["ok"], False)
        self.assertEqual(card["criteria"][1]["why"], "上次核对失败")
        self.assertIs(card["criteria"][-1]["ok"], True, "最后一条不是第 3 条，不得被覆盖")

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

    def test_done_report_and_failure_output(self):
        for cmd, code, check_line in [
                ("true", 8, "  ✓ 3 验收命令过了：`true` 过了"),
                ("", 8, "  — 3 验收命令过了：没有验收命令：CHECK_CMD 空着，队列条目也没写"),
                ("echo failed; exit 1", 9, "")]:
            with self.subTest(cmd=cmd):
                self.configure(cmd)
                r = self.done()
                self.assertEqual(r.returncode, code)
                self.assertEqual(r.stderr, "")
                if code == 8:
                    expected = ("核对通过 T1：\n"
                                f"  ✓ 依据 收尾记号：{self.sha[:7]} 收尾: test\n"
                                f"  ✓ 1 main 前进了：{self.base[:7]} → {self.sha[:7]}\n"
                                "  ✓ 2 这次建的分支都合进去了：没有未合并的分支\n"
                                f"{check_line}\n"
                                "DONE T1：核对通过。放行模式：等人放行（drover go）。\n")
                else:
                    expected = ("NOT DONE: T1 还没收尾：\n"
                                "  - 判据 3（验收命令过了）没满足：`echo failed; exit 1` 退出码 1\n"
                                "failed\n处理完再运行 drover done T1。\n")
                self.assertEqual(r.stdout, expected)
                events = self.B.task_events((self.d / "tasks.state").read_text())
                self.assertEqual([e["ev"] for e in events],
                                 ["start", "done"] if code == 8 else ["start"])

    def test_done_runs_check_once(self):
        counter = self.root / "checks"
        self.configure(f"echo run >> {counter}")
        r = self.done()
        self.assertEqual(r.returncode, 8, r.stdout + r.stderr)
        self.assertEqual(counter.read_text().splitlines(), ["run"], "验收命令只能执行一次")
        events = self.B.task_events((self.d / "tasks.state").read_text())
        self.assertEqual([e["ev"] for e in events], ["start", "done"])

    def test_done_publishes_once_atomically(self):
        counter = self.root / "checks"
        # 计数断言守住只跑一次；若回归到重跑，第二次失败暴露报告或发布串错结果。
        cmd = f"echo run >> {counter}; test $(wc -l < {counter}) -eq 1"
        self.configure(cmd)
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
            output = io.StringIO()
            with patch("builtins.open", guarded_open), patch.object(D.os, "replace", replace), \
                    patch.object(D.os, "getpid", return_value=pid), redirect_stdout(output):
                self.assertEqual(D.cmd_done("T1"), 8)
            self.assertEqual(output.getvalue().splitlines()[4],
                             f"  ✓ 3 验收命令过了：`{cmd}` 过了")
            self.assertEqual(counter.read_text().splitlines(), ["run"], "验收命令只能执行一次")
            saved = json.loads(self.result.read_text())
            self.assertEqual(set(saved), {"task", "main", "cmd", "ok", "why", "t"})
            self.assertEqual((saved["task"], saved["main"], saved["cmd"], saved["why"]),
                             ("T1", self.sha, cmd, f"`{cmd}` 过了"))
            self.assertIs(saved["ok"], True)
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

    @contextmanager
    def observe_result_reads(self):
        """只观察同进程三种标准库打开入口；不覆盖 subprocess cat 或其它进程。

        计数独立于被测调用，吞异常不能藏掉尝试。真正 CLI 另做内容污染对照，
        check_done 及它单独加载的 board 模块另在本进程直接调用，不冒充文件沙箱。
        """
        attempts = []
        target = os.path.realpath(self.result)
        real_open, real_io_open, real_os_open = open, io.open, os.open

        def observe(path, reading, entry):
            if not isinstance(path, int) and reading:
                resolved = os.path.realpath(os.fsdecode(path))
                if resolved == target:
                    attempts.append((entry, resolved))

        def builtin_open(path, mode="r", *args, **kwargs):
            observe(path, "r" in mode or "+" in mode, "builtins.open")
            return real_open(path, mode, *args, **kwargs)

        def io_open(path, mode="r", *args, **kwargs):
            observe(path, "r" in mode or "+" in mode, "io.open")
            return real_io_open(path, mode, *args, **kwargs)

        def os_open(path, flags, *args, **kwargs):
            observe(path, flags & os.O_ACCMODE != os.O_WRONLY, "os.open")
            return real_os_open(path, flags, *args, **kwargs)

        with patch("builtins.open", builtin_open), patch("io.open", io_open), patch("os.open", os_open):
            yield
        self.assertEqual(attempts, [], "判断路径尝试读取 .check-result")

    def test_result_never_enters_decisions(self):
        B = self.B
        D = load("drover_decision_check", DROVER)

        def setup_drover():
            previous = os.getcwd()
            try:
                os.chdir(self.repo)
                D.setup()
            finally:
                os.chdir(previous)
            D.B.CORRAL = str(self.corral)

        def reset(cmd, raw):
            self.configure(cmd)
            stamp = self.d / ".criteria-checked"
            if stamp.exists():
                stamp.unlink()
            if raw is None:
                if self.result.exists():
                    self.result.unlink()
            else:
                self.result.write_bytes(raw)

        def events():
            return [{k: v for k, v in e.items() if k != "t"}
                    for e in B.task_events((self.d / "tasks.state").read_text())]

        (self.d / "loop").touch()
        for cmd, expected_code in (("false", 9), ("true", 8)):
            reset(cmd, None)
            setup_drover()
            criteria = B.criteria(str(self.repo), self.base, cmd)
            unchecked = B.criteria(str(self.repo), self.base, cmd, do_check=False)
            conf = B.parse_conf(str(self.repo / ".drover.conf"))
            human = B.project_state(str(self.repo), conf)["human"]
            problems, rows = D.check_done(self.task)
            reset(cmd, None)
            baseline = self.done()
            self.assertEqual(baseline.returncode, expected_code)
            expected_events = events()
            reset(cmd, None)
            B.loop_tick(str(self.projects))
            baseline_log = (self.d / ".loop.log").read_text().splitlines()[-1].split(" done ", 1)[1]
            self.assertEqual(events(), expected_events)
            self.assertIs(json.loads(self.result.read_text())["ok"], cmd == "true")

            # 成功侧伪造成失败、失败侧伪造成成功；两侧还各试坏 JSON 与非法 UTF-8。
            for raw in (json.dumps(self.saved(cmd=cmd, ok=cmd != "true")).encode(), b"not json", b"\xff"):
                with self.subTest(cmd=cmd, raw=raw):
                    reset(cmd, raw)
                    with self.observe_result_reads():
                        self.assertEqual(B.criteria(str(self.repo), self.base, cmd), criteria)
                        self.assertEqual(B.criteria(str(self.repo), self.base, cmd, do_check=False), unchecked)
                        self.assertEqual(B.project_state(str(self.repo), conf)["human"], human)
                        self.assertEqual(D.check_done(self.task), (problems, rows))
                    reset(cmd, raw)  # check_done 已发布新值；每条路径重新喂伪造记录。
                    with self.observe_result_reads():
                        B.loop_tick(str(self.projects))
                    self.assertEqual(events(), expected_events)
                    log = (self.d / ".loop.log").read_text().splitlines()[-1].split(" done ", 1)[1]
                    self.assertEqual(log, baseline_log)
                    reset(cmd, raw)
                    actual = self.done()
                    self.assertEqual((actual.returncode, actual.stdout, actual.stderr),
                                     (baseline.returncode, baseline.stdout, baseline.stderr))
                    self.assertEqual(events(), expected_events)


if __name__ == "__main__":
    unittest.main()
