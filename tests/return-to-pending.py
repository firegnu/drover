#!/usr/bin/env python3
"""Running 撤回 Pending 公开 CLI：独立环境、合成项目、假 corral/通知器，不启动 PTY。"""
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


class ReturnToPending(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="drover-return-")
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
        self.assertIn("return_to_pending", result, "show 必须提供独立撤回目标")
        target = result["return_to_pending"]
        self.assertIsNone(target["unavailable_reason"])
        return target["target_token"]

    def withdraw(self, token, reason=" 换个时间做\n用户已停止工作 ", code=0):
        return self.cli("return-to-pending", "T1", "--target-token", token,
                        "--reason", reason, "--work-stopped", "--json", code=code)

    def test_return_restores_body_first_pauses_and_retains_run_history(self):
        (self.data / "queue.md").write_text("# 队列\n\n## T2 下一件\n保留\n\n## T1 被改过的标题\n被改过的正文\n")
        (self.data / "loop").touch()
        original = {p: p.read_bytes() for p in self.repo.rglob("*") if p.is_file()}
        token = self.token()
        self.assertFalse((self.data / ".tasks.lock").exists())
        result = self.withdraw(token)
        self.assertEqual({k: result[k] for k in ("schema_version", "ok", "task_id", "state", "paused")},
                         {"schema_version": 1, "ok": True, "task_id": "T1", "state": "pending", "paused": True})
        record = result["return_record"]
        self.assertEqual(record["dispatched_at"], 100)
        self.assertGreater(record["returned_at"], 100)
        self.assertEqual(record["reason"], "换个时间做\n用户已停止工作")
        self.assertIs(record["work_stopped"], True)
        state = self.cli("list", "--json")
        self.assertIsNone(state["current"])
        self.assertIsNone(state["awaiting"])
        self.assertTrue(state["paused"])
        self.assertTrue(state["mode"]["loop"])
        self.assertEqual(state["history"], [])
        self.assertEqual([(p["id"], p["title"], p["body"]) for p in state["pending"]],
                         [("T1", "调研", "正文"), ("T2", "下一件", "保留")])
        self.assertEqual(state["pending"][0]["return_history"], [record])
        detail = self.cli("show", "T1", "--json")
        self.assertEqual(detail["task"]["location"], "pending")
        self.assertEqual(detail["task"]["status"], "pending")
        self.assertEqual(detail["task"]["return_history"], [record])
        self.assertIsNone(detail["completion"]["rows"])
        self.assertIsNone(detail["return_to_pending"]["target_token"])
        self.assertIsNone(detail["manual_completion"]["target_token"])
        self.assertNotIn("T1 调研 · 放弃", self.cli("list"))
        self.assertEqual(self.withdraw(token, code=3)["error"]["code"], "target_changed")
        self.cli("next", code=8)
        projects = self.root / "projects"
        projects.write_text(str(self.repo) + "\n")
        self.cli("loop", "--once", "--projects", str(projects))
        self.assertEqual(self.cli("list", "--json")["pending"], state["pending"])
        self.assertFalse((self.root / "calls").exists())
        self.assertFalse((self.root / "checks").exists())
        self.assertEqual(original, {p: p.read_bytes() for p in self.repo.rglob("*") if p.is_file()})
        self.cli("resume")
        self.cli("next")
        current = self.cli("list", "--json")["current"]
        self.assertEqual(current["id"], "T1")
        self.assertEqual(current["return_history"], [record])
        self.assertEqual(self.withdraw(token, code=3)["error"]["code"], "target_changed")
        second = self.withdraw(self.token(), reason="第二次撤回")["return_record"]
        self.assertEqual(self.cli("show", "T1", "--json")["task"]["return_history"], [record, second])

    def snapshot(self):
        return {p.name: p.read_bytes() for p in self.data.iterdir() if p.is_file() and p.name != ".tasks.lock"}

    def test_old_targets_other_projects_awaiting_and_missing_confirmation_are_rejected(self):
        token = self.token()
        before = self.snapshot()
        for args in (("--reason", "原因", "--json"),
                     ("--reason", " ", "--work-stopped", "--json"),
                     ("--reason", "原因", "--work-stopped", "--work-stopped", "--json")):
            result = self.cli("return-to-pending", "T1", "--target-token", token, *args, code=2)
            self.assertEqual(result["error"]["code"], "invalid_arguments")
        manual = self.cli("show", "T1", "--json")["manual_completion"]["target_token"]
        self.assertEqual(self.withdraw(manual, code=2)["error"]["code"], "invalid_arguments")
        other = self.root / "other"
        shutil.copytree(self.repo, other)
        result = self.cli("return-to-pending", "T1", "--target-token", token, "--reason", "原因",
                          "--work-stopped", "--json", cwd=other, code=3)
        self.assertEqual(result["error"]["code"], "target_changed")
        self.assertEqual(self.snapshot(), before)
        for path in (self.data / "queue.md", self.repo / ".drover.conf"):
            original = path.read_bytes()
            path.write_bytes(original + b"\n")
            self.assertEqual(self.withdraw(token, code=3)["error"]["code"], "target_changed")
            path.write_bytes(original)
            self.assertEqual(self.withdraw(token, code=3)["error"]["code"], "target_changed")
            token = self.token()
        self.cli("complete-manually", "T1", "--target-token", self.cli("show", "T1", "--json")["manual_completion"]["target_token"],
                 "--reason", "完成", "--json")
        before = self.snapshot()
        self.assertEqual(self.withdraw(token, code=3)["error"]["code"], "target_changed")
        self.assertIsNone(self.cli("show", "T1", "--json")["return_to_pending"]["target_token"])
        self.assertEqual(self.snapshot(), before)

    def test_reason_is_literal_even_when_it_equals_confirmation_flag(self):
        self.assertEqual(self.withdraw(self.token(), reason="--work-stopped")["return_record"]["reason"], "--work-stopped")

    def test_returned_pending_can_be_edited_moved_dropped_or_completed_after_restart(self):
        record = self.withdraw(self.token())["return_record"]
        self.cli("edit", "1", "新标题", "新正文")
        self.cli("move", "1", "2")
        self.assertEqual([p["id"] for p in self.cli("list", "--json")["pending"]], ["T2", "T1"])
        self.cli("drop", "--pos", "2", "决定放弃")
        detail = self.cli("show", "T1", "--json")
        self.assertEqual(detail["task"]["status"], "dropped")
        self.assertEqual(detail["task"]["return_history"], [record])
        self.save()
        record = self.withdraw(self.token())["return_record"]
        self.cli("resume")
        self.cli("next")
        token = self.cli("show", "T1", "--json")["manual_completion"]["target_token"]
        self.cli("complete-manually", "T1", "--target-token", token, "--reason", "已完成", "--json")
        self.cli("go")
        detail = self.cli("show", "T1", "--json")
        self.assertEqual(detail["task"]["return_history"], [record])
        self.assertEqual(detail["task"]["status"], "done")

    def test_unassigned_or_removed_queue_entry_restored_once_with_same_id(self):
        for queue in ("## 调研\n原文\n\n## T2 下一件\n", "## T2 下一件\n", ""):
            self.save()
            (self.data / "queue.md").write_text(queue)
            self.withdraw(self.token())
            pending = self.cli("list", "--json")["pending"]
            self.assertEqual(pending[0]["id"], "T1")
            self.assertEqual(pending[0]["body"], "正文")
            self.assertEqual(len([p for p in pending if p["title"] == "调研"]), 1)

    def test_write_lock_rejects_all_concurrent_writers_and_stale_target_after_unlock(self):
        import fcntl
        token = self.token()
        before = self.snapshot()
        with (self.data / ".tasks.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.withdraw(token, code=4)["error"]["code"], "state_busy")
            for args in (("next",), ("done", "T1"), ("drop", "T1", "取消"), ("resume",), ("edit", "1", "变更")):
                self.cli(*args, code=4)
            self.assertEqual(self.token(), token)
        self.assertEqual(self.snapshot(), before)
        self.events += [{"ev": "drop", "id": "T1", "t": 101}, {**self.events[0], "t": 102}]
        self.save()
        self.assertEqual(self.withdraw(token, code=3)["error"]["code"], "target_changed")
        self.withdraw(self.token())

    def test_invalid_state_and_unreadable_queue_disable_return(self):
        token = self.token()
        original = (self.data / "tasks.state").read_bytes()
        (self.data / "tasks.state").write_bytes(original + b'{"ev":"unknown","id":"T1","t":101}\n')
        self.assertEqual(self.withdraw(token, code=2)["error"]["code"], "state_invalid")
        self.assertIsNone(self.cli("show", "T1", "--json")["return_to_pending"]["target_token"])
        (self.data / "tasks.state").write_bytes(original)
        queue = self.data / "queue.md"
        queue.unlink()
        queue.mkdir()
        self.assertEqual(self.withdraw(token, code=2)["error"]["code"], "snapshot_unavailable")
        self.assertIsNone(self.cli("show", "T1", "--json")["return_to_pending"]["target_token"])

    def test_missing_dispatch_body_is_not_invented_and_corrupt_return_is_json_error(self):
        token = self.token()
        del self.events[0]["body"]
        self.save()
        detail = self.cli("show", "T1", "--json")
        self.assertIsNone(detail["return_to_pending"]["target_token"])
        self.assertEqual(detail["return_to_pending"]["unavailable_reason"], "state_invalid")
        self.assertEqual(self.withdraw(token, code=2)["error"]["code"], "state_invalid")
        self.events[0]["body"] = "正文"
        self.events.append({"ev": "return", "id": "T1", "t": 101})
        self.save()
        self.assertEqual(self.cli("show", "T1", "--json", code=2)["error"]["code"], "state_invalid")

    def run_with_os_patch(self, token, patch):
        script = "import os, runpy, sys\nfrom unittest.mock import patch\n" + patch + "\nsys.argv = sys.argv[1:]\nwith patch_context:\n    runpy.run_path(sys.argv[0], run_name='__main__')\n"
        return subprocess.run([sys.executable, "-c", script, str(CLI), "return-to-pending", "T1",
                               "--target-token", token, "--reason", "暂停", "--work-stopped", "--json"],
                              cwd=self.repo, env=self.env, capture_output=True, text=True, timeout=30)

    def test_write_failure_never_publishes_return_before_pause_and_body(self):
        for suffix in ("/paused", "/queue.md", "/tasks.state"):
            with self.subTest(suffix=suffix):
                self.save()
                (self.data / "queue.md").write_text("## T2 下一件\n")
                (self.data / "paused").unlink(missing_ok=True)
                token = self.token()
                if suffix == "/paused":
                    patch = """import builtins
original = builtins.open
def fail(path, *args, **kwargs):
    if str(path).endswith('/paused'):
        raise OSError('synthetic failure')
    return original(path, *args, **kwargs)
patch_context = patch('builtins.open', fail)"""
                else:
                    patch = f"""original = os.replace
def fail(src, dst):
    if str(dst).endswith({suffix!r}):
        raise OSError('synthetic failure')
    return original(src, dst)
patch_context = patch('os.replace', fail)"""
                result = self.run_with_os_patch(token, patch)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(json.loads(result.stdout)["error"]["code"], "write_failed")
                state = self.cli("list", "--json")
                self.assertEqual(state["current"]["id"], "T1")
                self.assertNotIn("return_history", state["current"])
                self.assertEqual(state["history"], [])
                self.assertEqual(state["paused"], suffix != "/paused")
                self.assertEqual(list(self.data.glob(".return-pending-*")), [])
                self.assertFalse((self.root / "calls").exists())
        self.withdraw(self.token())

    def test_external_change_during_preparation_rejects_stale_target(self):
        token = self.token()
        original = (self.data / "tasks.state").read_bytes()
        result = self.run_with_os_patch(token, """original = os.fsync
def change(fd):
    with open('.drover.conf', 'a') as dest:
        dest.write('DONE_MARK=changed\\n')
    return original(fd)
patch_context = patch('os.fsync', change)""")
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["error"]["code"], "target_changed")
        self.assertEqual((self.data / "tasks.state").read_bytes(), original)
        self.assertFalse((self.data / "paused").exists())

    def test_return_holds_lock_through_publication(self):
        token = self.token()
        path = str(self.root / "publish.sock")
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(path)
            server.listen(1)
            server.settimeout(10)
            script = f"""import os, runpy, socket, sys
from unittest.mock import patch
original = os.replace
def replace(src, dst):
    if str(dst).endswith('/queue.md'):
        with socket.socket(socket.AF_UNIX) as client:
            client.connect({path!r})
            client.sendall(b'ready')
            client.recv(1)
    return original(src, dst)
sys.argv = sys.argv[1:]
with patch('os.replace', replace):
    runpy.run_path(sys.argv[0], run_name='__main__')
"""
            proc = subprocess.Popen([sys.executable, "-c", script, str(CLI), "return-to-pending", "T1",
                                     "--target-token", token, "--reason", "停止", "--work-stopped", "--json"],
                                    cwd=self.repo, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            connection = None
            try:
                connection, _ = server.accept()
                self.assertEqual(connection.recv(5), b"ready")
                for args in (("next",), ("done", "T1"), ("go",), ("resume",), ("drop", "T1", "取消")):
                    self.cli(*args, code=4)
                self.assertEqual(self.withdraw(token, code=4)["error"]["code"], "state_busy")
            finally:
                if connection:
                    connection.sendall(b"x")
                    connection.close()
                out, err = proc.communicate(timeout=20)
            self.assertEqual(proc.returncode, 0, out + err)
            self.assertEqual(json.loads(out)["state"], "pending")
            self.assertFalse((self.root / "calls").exists())


if __name__ == "__main__":
    unittest.main()
