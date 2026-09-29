#!/usr/bin/env python3
"""指定 Pending 的公开 CLI 合成专项；临时项目和假 corral，无 PTY。"""
import fcntl
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


class DispatchPending(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="drover-dispatch-")
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.repo, self.data = self.root / "repo", self.root / "data"
        for name in ("repo", "data", "home", "config", "cache", "state", "tmp"):
            (self.root / name).mkdir()
        fake = self.root / "corral"
        fake.write_text("#!" + sys.executable + "\n" + '''import json, os, sys
from pathlib import Path
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
if os.environ.get("SOCKET"):
    import socket
    with socket.socket(socket.AF_UNIX) as client:
        client.connect(os.environ["SOCKET"])
        client.sendall(b'ready')
        client.recv(1)
print(os.environ.get("REPLY", '{"ok":true,"confirmed":true,"merged_with_draft":false}'))
sys.exit(int(os.environ.get("SEND_CODE", "0")))
''')
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
        self.git("commit", "--allow-empty", "-qm", "base")
        self.configure()
        self.queue = self.data / "queue.md"
        self.queue.write_text("## T1 同名\n前面的正文\n\n## T2 同名\n选中的正文\n\n## 手写任务\n最后的正文\n")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, env=self.env, text=True).strip()

    def configure(self, agent="fake/main"):
        (self.repo / ".drover.conf").write_text(
            f"HANDOFF_DIR={self.data}\nTASK_GATE=1\nMAIN_AGENT={agent}\n"
            f"CHECK_CMD=touch {self.root / 'checked'}\n")

    def cli(self, *args, code=0, cwd=None):
        result = subprocess.run([sys.executable, str(CLI), *args], cwd=cwd or self.repo,
                                env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        return json.loads(result.stdout) if "--json" in args else result.stdout

    def target(self, pos=2):
        entry = self.cli("list", "--json")["pending"][pos - 1]
        self.assertIn("dispatch_pending", entry, "list 必须公开指定待办的目标令牌")
        target = entry["dispatch_pending"]
        self.assertEqual(target["pos"], pos)
        self.assertIsNone(target["unavailable_reason"])
        self.assertRegex(target["target_token"], r"^d1:[0-9a-f]{64}$")
        return target

    def dispatch(self, target, code=0):
        return self.cli("dispatch-pending", "--pos", str(target["pos"]),
                        "--target-token", target["target_token"], "--json", code=code)

    def calls(self):
        path = self.root / "calls"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def snapshot(self):
        return {p.name: p.read_bytes() for p in self.data.iterdir()
                if p.is_file() and p.name != ".tasks.lock"}

    def save_events(self, events):
        (self.data / "tasks.state").write_text("".join(json.dumps(e) + "\n" for e in events))

    def run_with_patch(self, target, patch):
        script = "import os, runpy, sys\nfrom unittest.mock import patch\n" + patch
        script += "\nsys.argv = sys.argv[1:]\nwith patch_context:\n    runpy.run_path(sys.argv[0], run_name='__main__')\n"
        return subprocess.run([sys.executable, "-c", script, str(CLI), "dispatch-pending", "--pos",
                               str(target["pos"]), "--target-token", target["target_token"], "--json"],
                              cwd=self.repo, env=self.env, capture_output=True, text=True, timeout=20)

    def test_selected_numbered_task_is_sent_without_reordering(self):
        before = self.queue.read_bytes()
        target = self.target()
        self.assertFalse((self.data / ".tasks.lock").exists())
        self.assertEqual(self.calls(), [])
        result = self.dispatch(target)
        self.assertTrue(result["ok"])
        self.assertEqual(result["task_id"], "T2")
        self.assertEqual(result["delivery"]["status"], "confirmed")
        self.assertEqual(result["record"]["status"], "recorded")
        self.assertEqual(result["state"], "current")
        self.assertEqual(self.calls(), [["send", "fake/main", "TASK T2: 同名\n\n选中的正文"]])
        after = self.cli("list", "--json")
        self.assertEqual(after["current"]["id"], "T2")
        self.assertEqual(after["current"]["body"], "选中的正文")
        self.assertEqual([p["title"] for p in after["pending"]], ["同名", "手写任务"])
        self.assertEqual(self.queue.read_bytes(), before)
        self.assertFalse((self.root / "checked").exists())

    def test_identity_changes_reject_without_sending_or_writing(self):
        target = self.target()
        mutations = [
            (self.queue, self.queue.read_text().replace("选中的正文", "新正文")),
            (self.queue, self.queue.read_text().replace("T2 同名", "T2 改名")),
            (self.queue, self.queue.read_text().replace("T2 同名", "T9 同名")),
            (self.queue, "## 插队\n\n" + self.queue.read_text()),
            (self.queue, "## 手写任务\n最后的正文\n\n## T2 同名\n选中的正文\n\n## T1 同名\n前面的正文\n"),
            (self.repo / ".drover.conf", (self.repo / ".drover.conf").read_text() + "DONE_MARK=changed\n"),
            (self.data / "tasks.state", '{"ev":"hold","key":"T2","on":true,"t":1}\n'),
        ]
        for path, changed in mutations:
            with self.subTest(path=path, changed=changed):
                previous = path.read_text() if path.exists() else ""
                path.write_text(changed)
                before = self.snapshot()
                self.assertEqual(self.dispatch(target, code=3)["error"]["code"], "target_changed")
                self.assertEqual(self.snapshot(), before)
                path.write_text(previous)
                self.assertEqual(self.dispatch(target, code=3)["error"]["code"], "target_changed")
                target = self.target()
        other = self.root / "other"
        shutil.copytree(self.repo, other)
        result = self.cli("dispatch-pending", "--pos", "2", "--target-token", target["target_token"],
                          "--json", cwd=other, code=3)
        self.assertEqual(result["error"]["code"], "target_changed")
        target["pos"] = 1
        self.assertEqual(self.dispatch(target, code=3)["error"]["code"], "target_changed")
        self.assertEqual(self.calls(), [])

    def test_current_paused_awaiting_never_resend_or_release(self):
        start = {"ev": "start", "id": "T9", "title": "运行中", "body": "旧任务",
                 "sha": self.git("rev-parse", "HEAD"), "t": 1}
        for events, paused, expected in (([start], False, "current_exists"),
                                         ([], True, "paused"),
                                         ([start, {"ev": "done", "id": "T9", "gate": True, "t": 2}],
                                          False, "awaiting_release")):
            with self.subTest(expected=expected):
                self.save_events(events)
                if paused:
                    (self.data / "paused").touch()
                else:
                    (self.data / "paused").unlink(missing_ok=True)
                (self.data / "loop").touch()
                target = self.target()
                before = self.snapshot()
                result = self.dispatch(target, code=8)
                self.assertEqual(result["error"]["code"], expected)
                self.assertEqual(result["delivery"]["status"], "not_attempted")
                self.assertEqual(self.snapshot(), before)
                self.assertEqual(self.calls(), [])

    def test_unnumbered_and_manual_mode_keep_existing_recording_rules(self):
        self.configure(agent="")
        target = self.target(3)
        result = self.dispatch(target)
        self.assertTrue(result["ok"])
        self.assertEqual(result["task_id"], "T3")
        self.assertEqual(result["manual_text"], "TASK T3: 手写任务\n\n最后的正文")
        self.assertEqual(result["delivery"]["status"], "not_sent")
        self.assertFalse(result["delivery"]["attempted"])
        self.assertEqual(result["record"]["status"], "recorded")
        self.assertEqual(self.cli("list", "--json")["current"]["id"], "T3")
        self.assertEqual(self.dispatch(target, code=3)["error"]["code"], "target_changed")
        self.assertEqual(self.calls(), [])

    def test_ambiguous_targets_require_distinct_numbers(self):
        for queue in ("## 同名\n第一份\n## 同名\n第二份\n",
                      "## T1 同名\n第一份\n## 同名\n第二份\n",
                      "## T1 甲\n第一份\n## T1 乙\n第二份\n"):
            with self.subTest(queue=queue):
                self.queue.write_text(queue)
                before = self.snapshot()
                entry = self.cli("list", "--json")["pending"][0]["dispatch_pending"]
                self.assertEqual(entry["unavailable_reason"], "target_ambiguous")
                self.assertIsNone(entry["target_token"])
                entry["target_token"] = "d1:" + "0" * 64
                self.assertEqual(self.dispatch(entry, code=2)["error"]["code"], "target_ambiguous")
                self.assertEqual(self.snapshot(), before)
                self.assertEqual(self.calls(), [])

    def test_send_outcomes_distinguish_transport_and_record(self):
        cases = [
            (0, {"ok": True, "confirmed": True, "merged_with_draft": True}, 0, "confirmed", "recorded"),
            (0, {"ok": True, "confirmed": False}, 8, "unconfirmed", "recorded"),
            (0, {"ok": False, "confirmed": True}, 8, "unconfirmed", "recorded"),
            (0, "bad JSON", 8, "unconfirmed", "recorded"),
            (3, {"ok": False, "error": "not_delivered"}, 8, "unconfirmed", "recorded"),
            (2, {"ok": False, "error": "not_found"}, 8, "rejected", "not_attempted"),
            (7, {"ok": False, "state": "working"}, 8, "rejected", "not_attempted"),
            (8, {"ok": False, "error": "human_active"}, 8, "rejected", "not_attempted"),
            (1, "unexpected failure", 8, "unknown", "not_attempted"),
        ]
        for send_code, reply, rc, delivery, record in cases:
            with self.subTest(send_code=send_code, reply=reply):
                self.save_events([])
                (self.data / "loop").touch()
                self.env.update(SEND_CODE=str(send_code), REPLY=reply if isinstance(reply, str) else json.dumps(reply))
                before = self.queue.read_bytes()
                calls = len(self.calls())
                result = self.dispatch(self.target(), code=rc)
                self.assertEqual(result["delivery"]["status"], delivery)
                self.assertEqual(result["delivery"]["corral_exit_code"], send_code)
                self.assertEqual(result["record"]["status"], record)
                self.assertEqual(len(self.calls()), calls + 1)
                self.assertFalse((self.data / ".loop-wait").exists(), "指定派发不能挂自动 next 重试")
                self.assertEqual(self.queue.read_bytes(), before)
                current = self.cli("list", "--json")["current"]
                self.assertEqual(current["id"] if current else None, "T2" if record == "recorded" else None)

    def test_write_failure_reports_confirmed_delivery_and_uncertain_record(self):
        target = self.target()
        result = self.run_with_patch(target, '''import builtins
original = builtins.open
def fail(path, mode='r', *args, **kwargs):
    if str(path).endswith('/tasks.state') and mode == 'a':
        raise OSError('synthetic append failure')
    return original(path, mode, *args, **kwargs)
patch_context = patch('builtins.open', fail)''')
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        result = json.loads(result.stdout)
        self.assertEqual(result["error"]["code"], "write_failed")
        self.assertEqual(result["delivery"]["status"], "confirmed")
        self.assertEqual(result["record"]["status"], "unknown")
        self.assertEqual(result["state"], "unknown")
        self.assertEqual(len(self.calls()), 1)
        self.assertIsNone(self.cli("list", "--json")["current"])

    def test_cleanup_failure_preserves_recorded_status(self):
        (self.data / ".loop-wait").mkdir()
        result = self.dispatch(self.target(), code=2)
        self.assertEqual(result["error"]["code"], "write_failed")
        self.assertEqual(result["delivery"]["status"], "confirmed")
        self.assertEqual(result["record"]["status"], "recorded")
        self.assertEqual(result["state"], "current")
        self.assertEqual(self.cli("list", "--json")["current"]["id"], "T2")
        self.assertEqual(len(self.calls()), 1)

    def test_transport_timeout_is_unknown_and_does_not_record_or_retry(self):
        target = self.target()
        result = self.run_with_patch(target, '''import subprocess
original = subprocess.run
def timeout(args, *rest, **kwargs):
    if args[0] == os.environ['DROVER_CORRAL_BIN']:
        original(args, *rest, **kwargs)   # 外部已经接收，调用侧却没拿到结果
        raise subprocess.TimeoutExpired(args, 60)
    return original(args, *rest, **kwargs)
patch_context = patch('subprocess.run', timeout)''')
        self.assertEqual(result.returncode, 8, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        result = json.loads(result.stdout)
        self.assertEqual(result["error"]["code"], "delivery_unknown")
        self.assertEqual(result["delivery"]["status"], "unknown")
        self.assertIsNone(result["delivery"]["corral_exit_code"])
        self.assertEqual(result["record"]["status"], "not_attempted")
        self.assertEqual(len(self.calls()), 1)
        self.assertIsNone(self.cli("list", "--json")["current"])

    def test_changed_configuration_at_send_boundary_is_rejected(self):
        target = self.target(3)
        result = self.run_with_patch(target, '''original = os.path.exists
def change(path):
    if str(path).endswith('/paused'):
        with open('.drover.conf', 'a') as dest:
            dest.write('MAIN_AGENT=different/main\\n')
    return original(path)
patch_context = patch('os.path.exists', change)''')
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["error"]["code"], "target_changed")
        self.assertEqual(self.calls(), [])
        self.assertIsNone(self.cli("list", "--json")["current"])

    def test_invalid_arguments_and_damaged_state_never_send(self):
        target = self.target()
        for args in (("--pos", "0", "--target-token", target["target_token"], "--json"),
                     ("--pos", "2", "--target-token", "r1:" + "0" * 64, "--json"),
                     ("--pos", "2", "--target-token", target["target_token"], "--json", "--json"),
                     ("--pos", "9" * 5000, "--target-token", target["target_token"], "--json")):
            result = self.cli("dispatch-pending", *args, code=2)
            self.assertEqual(result["error"]["code"], "invalid_arguments")
        state = self.data / "tasks.state"
        state.write_text('{broken event}\n')
        before = self.snapshot()
        entry = self.cli("list", "--json")["pending"][1]["dispatch_pending"]
        self.assertEqual(entry["unavailable_reason"], "state_invalid")
        self.assertIsNone(entry["target_token"])
        self.assertEqual(self.dispatch(target, code=2)["error"]["code"], "state_invalid")
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.calls(), [])

    def test_busy_lock_is_checked_before_reading_partial_state(self):
        target = self.target()
        with (self.data / ".tasks.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            (self.data / "tasks.state").write_text('{partial')
            self.assertEqual(self.dispatch(target, code=4)["error"]["code"], "state_busy")
        self.assertEqual(self.calls(), [])

    def test_shared_lock_is_held_through_send_and_record(self):
        target = self.target()
        path = str(self.root / "send.sock")
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(path)
            server.listen(1)
            server.settimeout(10)
            self.env["SOCKET"] = path
            script = '''import builtins, os, runpy, socket, sys
from unittest.mock import patch
original = builtins.open
def wait_for_write(path, mode='r', *args, **kwargs):
    if str(path).endswith('/tasks.state') and mode == 'a':
        with socket.socket(socket.AF_UNIX) as client:
            client.connect(os.environ['SOCKET'])
            client.sendall(b'ready')
            client.recv(1)
    return original(path, mode, *args, **kwargs)
sys.argv = sys.argv[1:]
with patch('builtins.open', wait_for_write):
    runpy.run_path(sys.argv[0], run_name='__main__')
'''
            proc = subprocess.Popen([sys.executable, "-c", script, str(CLI), "dispatch-pending", "--pos", "2",
                                     "--target-token", target["target_token"], "--json"],
                                    cwd=self.repo, env=self.env, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, text=True)
            connection = None
            try:
                for phase in ("send", "record"):
                    with self.subTest(phase=phase):
                        connection, _ = server.accept()
                        self.assertEqual(connection.recv(5), b"ready")
                        for args in (("next",), ("pause",), ("resume",), ("move", "2", "1"),
                                     ("edit", "2", "新标题"), ("drop", "T2", "取消"), ("go",),
                                     ("done", "T2"), ("hold", "2", "on")):
                            self.cli(*args, code=4)
                        self.assertEqual(self.dispatch(target, code=4)["error"]["code"], "state_busy")
                        self.assertIsNone(self.cli("list", "--json")["current"])
                        connection.sendall(b'x')
                        connection.close()
                        connection = None
            finally:
                if connection:
                    connection.sendall(b'x')
                    connection.close()
                out, err = proc.communicate(timeout=20)
            self.assertEqual(proc.returncode, 0, out + err)
            self.assertEqual(json.loads(out)["record"]["status"], "recorded")
            self.assertEqual(self.cli("list", "--json")["current"]["id"], "T2")
            self.assertEqual(len(self.calls()), 1)


if __name__ == "__main__":
    unittest.main()
