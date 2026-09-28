#!/usr/bin/env python3
"""T36 公开 CLI：独立环境、合成项目、假 corral/通知器，不启动 PTY。"""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[1] / "bin/drover"


class ManualComplete(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="drover-manual-")
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.repo, self.data = self.root / "repo", self.root / "data"
        for name in ("repo", "data", "home", "config", "cache", "state", "tmp"):
            (self.root / name).mkdir()
        fake = self.root / "fake"
        fake.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALLS"\n'
                        'printf \'{"ok":true,"agents":[]}\\n\'\n')
        fake.chmod(0o755)
        self.env = {**os.environ, "HOME": str(self.root / "home"),
                    "XDG_CONFIG_HOME": str(self.root / "config"),
                    "XDG_CACHE_HOME": str(self.root / "cache"),
                    "XDG_STATE_HOME": str(self.root / "state"), "TMPDIR": str(self.root / "tmp"),
                    "DROVER_CORRAL_BIN": str(fake), "DROVER_NOTIFY_BIN": str(fake),
                    "CALLS": str(self.root / "calls"), "DROVER_BOARD_ENGLISH": "0",
                    "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.com")
        (self.repo / "tracked").write_text("base\n")
        self.git("add", "tracked")
        self.git("commit", "-qm", "base")
        self.base = self.git("rev-parse", "HEAD")
        self.check = f"echo checked >> {self.root / 'checks'}; exit 1"
        self.configure()
        (self.data / "queue.md").write_text("## T1 调研\n正文\n\n## T2 下一件\n")
        self.events = [{"ev": "start", "id": "T1", "title": "调研", "body": "正文",
                        "main": self.base, "sha": self.base, "t": 100}]
        self.save()

    def configure(self):
        (self.repo / ".drover.conf").write_text(
            f"HANDOFF_DIR={self.data}\nTASK_GATE=0\nCHECK_CMD={self.check}\nMAIN_AGENT=fake/main\n")

    def save(self):
        (self.data / "tasks.state").write_text("".join(json.dumps(e) + "\n" for e in self.events))

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, env=self.env, text=True).strip()

    def cli(self, *args, code=0, cwd=None):
        r = subprocess.run([sys.executable, str(CLI), *args], cwd=cwd or self.repo,
                           env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, code, r.stdout + r.stderr)
        self.assertEqual(r.stderr, "")
        return json.loads(r.stdout) if "--json" in args else r.stdout

    def token(self):
        result = self.cli("show", "T1", "--json")
        self.assertIn("manual_completion", result, "show 必须提供人工完成目标")
        target = result["manual_completion"]
        self.assertIsNone(target["unavailable_reason"])
        self.assertIsInstance(target["target_token"], str)
        return target["target_token"]

    def complete(self, token, reason=" 已验收调研\n保留分支 ", code=0):
        return self.cli("complete-manually", "T1", "--target-token", token,
                        "--reason", reason, "--json", code=code)

    def test_manual_receipt_waits_with_gate_off_then_normal_go(self):
        self.git("checkout", "-qb", "research")
        self.git("commit", "-q", "--allow-empty", "-m", "research")
        self.git("checkout", "-q", "main")
        (self.repo / "tracked").write_text("dirty\n")
        (self.data / "paused").touch()
        original = {p: p.read_bytes() for p in self.repo.rglob("*") if p.is_file()}
        state = (self.data / "tasks.state").read_bytes()
        token = self.token()
        self.assertFalse((self.data / ".tasks.lock").exists(), "show 不创建锁")
        receipt = self.complete(token)["completion_record"]
        self.assertEqual(receipt["method"], "manual")
        self.assertEqual(receipt["reason"], "已验收调研\n保留分支")
        self.assertIsInstance(receipt["confirmed_at"], (float, int))
        self.assertEqual(receipt["workspace"], {"state": "dirty", "tracked_dirty": True})
        self.assertEqual([r["state"] for r in receipt["completion"]["rows"]],
                         ["unmet", "unmet", "unmet", "not_run"])
        self.assertEqual(receipt["last_check"]["status"], "missing")
        result = self.cli("list", "--json")
        self.assertIsNone(result["current"])
        self.assertEqual(result["awaiting"]["completion_record"], receipt)
        self.assertEqual(result["mode"], {"loop": False, "gate": False})
        self.assertTrue(result["paused"])
        self.assertIn("人工确认", self.cli("list"))
        waiting = self.cli("show", "T1", "--json")
        self.assertEqual(waiting["task"]["completion_record"], receipt)
        self.assertIsNone(waiting["manual_completion"]["target_token"])
        self.assertEqual(self.complete(token, code=3)["error"]["code"], "target_changed")
        self.assertTrue((self.data / "tasks.state").read_bytes().startswith(state))
        self.assertEqual(len((self.data / "tasks.state").read_text().splitlines()), 2)
        self.cli("go")
        history = self.cli("show", "T1", "--json")
        self.assertEqual(history["task"]["location"], "history")
        self.assertEqual(history["task"]["completion_record"], receipt)
        self.assertIsNone(history["completion"]["rows"])
        self.assertEqual(original, {p: p.read_bytes() for p in self.repo.rglob("*") if p.is_file()})
        self.assertFalse((self.root / "checks").exists())
        self.assertFalse((self.root / "calls").exists())

    def test_board_waiting_text_distinguishes_manual_confirmation(self):
        self.complete(self.token())
        projects = self.root / "projects"
        projects.write_text(str(self.repo) + "\n")
        script = '''
import importlib.machinery, importlib.util, json, sys
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("board", sys.argv[1])
B = importlib.util.module_from_spec(importlib.util.spec_from_loader("board", loader))
loader.exec_module(B)
projects = B.collect(sys.argv[2])
pv = B.view_model(projects)["projects"][0]
print(json.dumps({"steps": projects[0]["tasks"]["card"]["steps"], "waits": projects[0]["human"],
                  "lines": B.detail_lines(pv),
                  "styled": B.detail_sections(pv, presentation=True)}, ensure_ascii=False))
'''
        r = subprocess.run([sys.executable, "-c", script, str(CLI.with_name("drover-board")), str(projects)],
                           cwd=self.repo, env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Manually confirmed", r.stdout)
        self.assertIn("人工确认", r.stdout)
        self.assertNotIn("Checks passed", r.stdout)
        self.assertNotIn("checks passed", r.stdout)
        self.assertNotIn("核对已通过", r.stdout)
        self.assertNotIn("核对通过", r.stdout)

    def test_tokens_reject_other_project_changed_config_and_restarted_id(self):
        token = self.token()
        other = self.root / "other"
        shutil.copytree(self.repo, other)
        result = self.cli("complete-manually", "T1", "--target-token", token,
                          "--reason", "已验收", "--json", code=3, cwd=other)
        self.assertEqual(result["error"]["code"], "target_changed")
        before = (self.data / "tasks.state").read_bytes()
        conf = self.repo / ".drover.conf"
        original = conf.read_text()
        conf.write_text(original + "DONE_MARK=finish\n")
        self.assertEqual(self.complete(token, code=3)["error"]["code"], "target_changed")
        conf.write_text(original)
        self.assertEqual(self.complete(token, code=3)["error"]["code"], "target_changed")
        self.assertEqual((self.data / "tasks.state").read_bytes(), before)
        token = self.token()
        self.events += [{"ev": "drop", "id": "T1", "t": 101}, {**self.events[0], "t": 102}]
        self.save()
        self.assertEqual(self.complete(token, code=3)["error"]["code"], "target_changed")
        self.assertNotEqual(token, self.token())
        # 另一个合法状态事件也让已展示的确认目标失效。
        token = self.token()
        self.cli("hold", "1", "on")
        self.assertEqual(self.complete(token, code=3)["error"]["code"], "target_changed")

    def test_failed_and_corrupt_check_samples_are_preserved_without_rerun(self):
        self.cli("done", "T1", code=9)
        checks = (self.root / "checks").read_bytes()
        before = self.cli("show", "T1", "--json")
        record = self.complete(self.token(), reason=" 接受失败\u2028保存证据 ")["completion_record"]
        self.assertEqual(record["last_check"], before["last_check"])
        self.assertIs(record["last_check"]["ok"], False)
        self.assertEqual(record["completion"]["rows"][3]["state"], "not_run")
        self.assertEqual(self.cli("show", "T1", "--json")["task"]["completion_record"], record)
        self.cli("go")
        self.assertEqual((self.root / "checks").read_bytes(), checks)
        self.save()
        (self.data / ".check-result").write_text("{broken")
        record = self.complete(self.token())["completion_record"]
        self.assertEqual(record["last_check"]["status"], "invalid")
        self.assertEqual((self.root / "checks").read_bytes(), checks)
        self.save()
        self.check = ""
        self.configure()
        state = self.data / "tasks.state"
        prefix = state.read_bytes().replace(b"\n", b"\r\n")
        state.write_bytes(prefix)
        record = self.complete(self.token(), reason="--json")["completion_record"]
        self.assertEqual(record["completion"]["rows"][3]["state"], "not_applicable")
        self.assertEqual(record["reason"], "--json")
        self.assertTrue(state.read_bytes().startswith(prefix), "不得改写原历史字节")

    def test_loop_only_continues_after_go_and_resume(self):
        (self.data / "loop").touch()
        (self.data / "paused").touch()
        projects = self.root / "projects"
        projects.write_text(str(self.repo) + "\n")
        self.complete(self.token())
        state = (self.data / "tasks.state").read_bytes()
        self.cli("loop", "--once", "--projects", str(projects))
        self.assertEqual((self.data / "tasks.state").read_bytes(), state)
        self.assertFalse((self.root / "checks").exists())
        self.assertFalse((self.root / "calls").exists())
        self.cli("go")
        state = (self.data / "tasks.state").read_bytes()
        self.cli("loop", "--once", "--projects", str(projects))
        self.assertEqual((self.data / "tasks.state").read_bytes(), state)
        self.cli("resume")
        self.cli("loop", "--once", "--projects", str(projects))
        result = self.cli("list", "--json")
        self.assertEqual(result["current"]["id"], "T2")
        self.assertEqual(result["history"][0]["completion_record"]["method"], "manual")
        self.assertEqual((self.root / "calls").read_text().count("send fake/main TASK T2"), 1)
        self.assertFalse((self.root / "checks").exists())

    def test_invalid_input_and_unreadable_state_config_or_snapshot_never_complete(self):
        token = self.token()
        self.assertEqual(self.complete(token, reason=" \n ", code=2)["error"]["code"], "invalid_arguments")
        self.assertEqual(self.complete("bad", code=2)["error"]["code"], "invalid_arguments")
        self.assertEqual(self.cli("complete-manually", "--json", code=2)["error"]["code"], "invalid_arguments")
        self.assertEqual(self.cli("complete-manually", "T1", "--target-token", token,
                                 "--reason", "接受", "--json", code=2, cwd=self.root)["error"]["code"],
                         "repository_unavailable")
        for name, parent, code in ((".drover.conf", self.repo, "configuration_unreadable"),
                                   ("tasks.state", self.data, "state_unreadable"),
                                   (".check-result", self.data, "snapshot_unavailable")):
            with self.subTest(source=name):
                path = parent / name
                original = path.read_bytes() if path.exists() else None
                if path.exists():
                    path.unlink()
                path.mkdir()
                try:
                    self.assertEqual(self.complete(token, code=2)["error"]["code"], code)
                finally:
                    path.rmdir()
                    if original is not None:
                        path.write_bytes(original)
                token = self.token()
        config = self.repo / ".drover.conf"
        original = config.read_text()
        config.write_text("HANDOFF_DIR=bad\0path\n")
        self.assertEqual(self.complete(token, code=2)["error"]["code"], "configuration_unreadable")
        config.write_text(original)
        token = self.token()
        state = (self.data / "tasks.state").read_bytes()
        for tail in ("{bad\n", '{"ev":"unknown","id":"T1","t":101}\n',
                     '{"ev":"done","id":"T1","t":101}\n'):
            (self.data / "tasks.state").write_bytes(state + tail.encode())
            self.assertEqual(self.complete(token, code=2)["error"]["code"], "state_invalid")
            self.assertEqual((self.data / "tasks.state").read_bytes(), state + tail.encode())
        (self.data / "tasks.state").write_bytes(state)
        token = self.token()
        self.git("branch", "-m", "main", "elsewhere")
        self.assertEqual(self.complete(token, code=2)["error"]["code"], "snapshot_unavailable")
        self.assertIsNone(self.cli("show", "T1", "--json")["manual_completion"]["target_token"])

    def test_publish_failure_leaves_no_completion_event(self):
        token = self.token()
        before = (self.data / "tasks.state").read_bytes()
        script = '''
import os, runpy, sys
from unittest.mock import patch
original = os.replace
def replace(src, dst):
    if str(dst).endswith("/tasks.state"):
        raise OSError("simulated storage failure")
    return original(src, dst)
sys.argv = sys.argv[1:]
with patch("os.replace", replace):
    runpy.run_path(sys.argv[0], run_name="__main__")
'''
        r = subprocess.run([sys.executable, "-c", script, str(CLI), "complete-manually", "T1",
                            "--target-token", token, "--reason", "接受", "--json"],
                           cwd=self.repo, env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertEqual(json.loads(r.stdout)["error"]["code"], "write_failed")
        self.assertEqual((self.data / "tasks.state").read_bytes(), before)
        self.assertEqual(list(self.data.glob(".manual-complete-*")), [])

    def test_config_change_while_preparing_write_rejects_without_event(self):
        token = self.token()
        before = (self.data / "tasks.state").read_bytes()
        script = '''
import os, runpy, sys
from unittest.mock import patch
original = os.fsync
def fsync(fd):
    with open(".drover.conf", "a") as config:
        config.write("DONE_MARK=changed\\n")
    return original(fd)
sys.argv = sys.argv[1:]
with patch("os.fsync", fsync):
    runpy.run_path(sys.argv[0], run_name="__main__")
'''
        r = subprocess.run([sys.executable, "-c", script, str(CLI), "complete-manually", "T1",
                            "--target-token", token, "--reason", "接受", "--json"],
                           cwd=self.repo, env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.assertEqual(json.loads(r.stdout)["error"]["code"], "target_changed")
        self.assertEqual((self.data / "tasks.state").read_bytes(), before)
        self.assertEqual(list(self.data.glob(".manual-complete-*")), [])

    def test_manual_operation_excludes_stale_cli_writers(self):
        token = self.token()
        path = str(self.root / "sync.sock")
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(path)
            server.listen(1)
            server.settimeout(10)
            bindir = self.root / "bin"
            bindir.mkdir()
            fake_git = bindir / "git"
            fake_git.write_text(f'''#!{sys.executable}
import os, socket, sys
if "status" in sys.argv:
    with socket.socket(socket.AF_UNIX) as s:
        s.connect({path!r})
        s.sendall(b"ready")
        s.recv(1)
os.execv({shutil.which('git')!r}, ["git", *sys.argv[1:]])
''')
            fake_git.chmod(0o755)
            env = {**self.env, "PATH": str(bindir) + os.pathsep + self.env["PATH"]}
            proc = subprocess.Popen([sys.executable, str(CLI), "complete-manually", "T1",
                                     "--target-token", token, "--reason", "接受", "--json"],
                                    cwd=self.repo, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            connection = None
            try:
                connection, _ = server.accept()
                self.assertEqual(connection.recv(5), b"ready")
                before = (self.data / "tasks.state").read_bytes()
                for args in (("done", "T1"), ("go",), ("next",), ("drop", "T1", "取消"),
                             ("hold", "1", "on"), ("add", "新任务"), ("loop", "off"), ("pause",)):
                    self.cli(*args, code=4)
                self.assertEqual(self.complete(token, code=4)["error"]["code"], "state_busy")
                self.assertEqual(self.token(), token, "查询不锁定或修改状态")
                self.assertEqual((self.data / "tasks.state").read_bytes(), before)
            finally:
                if connection:
                    connection.sendall(b"x")
                    connection.close()
                out, err = proc.communicate(timeout=20)
            self.assertEqual(proc.returncode, 0, out + err)
            self.assertEqual(json.loads(out)["state"], "awaiting_release")
        self.assertFalse((self.root / "checks").exists())
        self.assertFalse((self.root / "calls").exists())

    def test_done_holds_mutex_while_checking_and_invalidates_token(self):
        path = str(self.root / "done.sock")
        check = self.root / "check.py"
        check.write_text(f'''import socket
with socket.socket(socket.AF_UNIX) as s:
    s.connect({path!r})
    s.sendall(b"ready")
    s.recv(1)
''')
        self.check = f"{sys.executable} {check}"
        self.configure()
        with (self.repo / ".drover.conf").open("a") as f:
            f.write("TASK_GATE=1\n")
        self.git("commit", "-q", "--allow-empty", "-m", "收尾: completed")
        token = self.token()
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(path)
            server.listen(1)
            server.settimeout(10)
            proc = subprocess.Popen([sys.executable, str(CLI), "done", "T1"], cwd=self.repo,
                                    env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            connection = None
            try:
                connection, _ = server.accept()
                self.assertEqual(connection.recv(5), b"ready")
                self.assertEqual(self.complete(token, code=4)["error"]["code"], "state_busy")
            finally:
                if connection:
                    connection.sendall(b"x")
                    connection.close()
                out, err = proc.communicate(timeout=20)
            self.assertEqual(proc.returncode, 8, out + err)
        self.assertEqual(self.complete(token, code=3)["error"]["code"], "target_changed")
        self.assertNotIn("completion_record", self.cli("show", "T1", "--json")["task"])


if __name__ == "__main__":
    unittest.main()
