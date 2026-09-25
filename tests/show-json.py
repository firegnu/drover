#!/usr/bin/env python3
"""show 的公开 CLI 契约；隔离合成仓库、假 corral，不启动服务或 PTY。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

CLI = Path(__file__).resolve().parents[1] / "bin/drover"


class ShowJSON(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="drover-show-json-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo, self.data = self.root / "repo", self.root / "data"
        self.repo.mkdir()
        self.data.mkdir()
        self.fake = self.root / "corral"
        self.fake.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALLS"\ncat "$REPLY"\n')
        self.fake.chmod(0o755)
        self.reply, self.calls = self.root / "reply", self.root / "calls"
        self.reply.write_text(json.dumps({"ok": True, "state": "idle", "idle_for": 999,
                                         "last_input_source": "send"}))
        self.env = {**os.environ, "HOME": str(self.root), "DROVER_CORRAL_BIN": str(self.fake),
                    "CALLS": str(self.calls), "REPLY": str(self.reply)}
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.com")
        self.git("commit", "-q", "--allow-empty", "-m", "base")
        self.base = self.git("rev-parse", "HEAD")
        self.cmd = f"touch {self.root / 'check-must-not-run'}"
        self.configure()
        self.events = [{"ev": "start", "id": "T1", "title": "原始标题", "body": "原始正文\n第二行",
                        "main": self.base, "sha": self.base, "t": 100}]
        self.save()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], text=True).strip()

    def configure(self, extra="", directory=None):
        (self.repo / ".drover.conf").write_text(
            f"HANDOFF_DIR={directory or self.data}\nCHECK_CMD={self.cmd}\nMAIN_AGENT=fake/main\n" + extra)

    def save(self):
        (self.data / "tasks.state").write_text("".join(json.dumps(e) + "\n" for e in self.events))

    def snapshot(self):
        return {str(p): (p.read_bytes(), p.stat().st_mtime_ns) if p.is_file() else None
                for p in self.root.rglob("*") if p != self.calls}

    def invoke(self, *args, code=0, cwd=None, external_writer=False):
        before = self.snapshot()
        r = subprocess.run([sys.executable, str(CLI), "show", *args], cwd=cwd or self.repo,
                           env=self.env, capture_output=True, text=True)
        if not external_writer:
            self.assertEqual(self.snapshot(), before, "查询必须完全只读")
        self.assertEqual(r.returncode, code, r.stdout + r.stderr)
        self.assertEqual(r.stderr, "")
        try:
            return json.loads(r.stdout)
        except ValueError:
            self.fail(f"stdout 不是单个 JSON: {r.stdout!r}")

    def show(self, *flags):
        return self.invoke("T1", "--json", *flags)

    def test_selected_task_and_read_only(self):
        result = self.show()
        self.assertEqual(result["schema_version"], 1)
        self.assertIs(result["ok"], True)
        self.assertEqual(result["task"]["location"], "current")
        self.assertEqual(result["task"]["body"], "原始正文\n第二行")
        self.assertEqual(result["task"]["status"], "doing")
        self.assertFalse(self.calls.exists(), "默认禁止调用 corral")

    def test_unicode_line_separator_in_branch_name(self):
        branch = "feature/name\u2028tail"
        self.git("checkout", "-q", "-b", branch)
        self.git("commit", "-q", "--allow-empty", "-m", "branch work")
        self.git("checkout", "-q", "main")
        before = self.show()
        row = next(r for r in before["completion"]["rows"] if r["id"] == "branches_merged")
        self.assertIs(row["ok"], False)
        self.assertEqual(row["state"], "unmet")
        self.assertIn(branch, row["why"], "合法 ref 必须原样保留，不能截断、替换或跳过")
        self.assertEqual(before["warnings"], [])

        self.git("merge", "-q", "--ff-only", branch)
        after = self.show()
        row = next(r for r in after["completion"]["rows"] if r["id"] == "branches_merged")
        self.assertIs(row["ok"], True)
        self.assertEqual(row["state"], "met")
        self.assertIn(branch, row["why"])
        self.assertEqual(after["git"]["main_commits_since_start"], 1)
        self.assertEqual(after["warnings"], [])
        self.assertFalse(self.calls.exists())

    def test_lifecycle_timing_git_and_completion(self):
        current = self.show()
        self.assertEqual(current["timing"]["elapsed_seconds"], current["observed_at"] - 100)
        self.assertIsNone(current["timing"]["release_wait_seconds"])
        self.assertEqual(current["git"]["range_commits"], 0)
        rows = {r["id"]: r for r in current["completion"]["rows"]}
        self.assertIs(rows["main_advanced"]["ok"], False)
        self.assertEqual(rows["check_command"]["state"], "not_run")
        self.git("commit", "-q", "--allow-empty", "-m", "收尾: synthetic")
        end = self.git("rev-parse", "HEAD")
        result = self.show()
        self.assertEqual(result["git"]["range_commits"], 1)
        self.assertEqual(result["git"]["main_commits_since_start"], 1)
        self.assertTrue(all(r["ok"] for r in result["completion"]["rows"][:3]))
        self.events.append({"ev": "done", "id": "T1", "sha": end, "t": 160, "gate": True})
        self.save()
        waiting = self.show()
        self.assertEqual(waiting["task"]["location"], "awaiting")
        self.assertEqual(waiting["timing"]["elapsed_seconds"], 60)
        self.assertEqual(waiting["timing"]["release_wait_seconds"], waiting["observed_at"] - 160)
        self.events.append({"ev": "go", "id": "T1", "t": 190})
        self.save()
        historical = self.show()
        self.assertEqual(historical["task"]["location"], "history")
        self.assertEqual(historical["timing"]["release_wait_seconds"], 30)
        self.assertEqual(historical["git"]["end_head"], end)
        self.assertIsNone(historical["git"]["main_commits_since_start"])
        self.assertEqual(historical["completion"]["unavailable_reason"], "completion_snapshot_not_recorded")
        self.assertIsNone(historical["completion"]["rows"])

    def test_missing_endpoints_and_git_failure(self):
        self.events = [{"ev": "drop", "id": "T1", "title": "没开始", "reason": "取消", "t": 200}]
        self.save()
        result = self.show()
        self.assertIsNone(result["timing"]["elapsed_seconds"])
        self.assertIsNone(result["timing"]["release_wait_seconds"])
        self.assertIsNone(result["git"]["range_commits"])
        self.assertEqual(result["git"]["unavailable_reasons"]["range_commits"], "start_head_not_recorded")
        self.events = [{"ev": "start", "id": "T1", "sha": "f" * 40, "main": "f" * 40, "t": 100}]
        self.save()
        result = self.show()
        self.assertIsNone(result["git"]["range_commits"])
        self.assertEqual(result["git"]["unavailable_reasons"]["range_commits"], "git_query_failed")
        self.assertTrue(all(r["ok"] is None for r in result["completion"]["rows"]))

    def test_structured_errors_and_absent_handoff(self):
        for args in ([], ["T1"], ["pending", "--json"], ["T1", "--json", "--json"]):
            self.assertEqual(self.invoke(*args, code=2)["error"]["code"], "invalid_arguments")
        self.assertEqual(self.invoke("T99", "--json", code=2)["error"]["code"], "task_not_found")
        self.configure(directory=self.root / "absent")
        self.assertEqual(self.invoke("T1", "--json", code=2)["error"]["code"], "task_not_found")
        self.assertFalse((self.root / "absent").exists())
        (self.repo / ".drover.conf").write_text("")
        self.assertEqual(self.invoke("T1", "--json", code=2)["error"]["code"], "not_configured")
        self.assertEqual(self.invoke("T1", "--json", code=2, cwd=self.root)["error"]["code"], "not_repository")

    def cache(self, **changes):
        record = {"task": "T1", "main": self.git("rev-parse", "main"), "cmd": self.cmd,
                  "ok": True, "why": "上次通过", "t": time.time() - 10, **changes}
        (self.data / ".check-result").write_text(json.dumps(record))
        return record

    def test_cache_identity_and_history_sample(self):
        self.assertEqual(self.show()["last_check"]["status"], "missing")
        saved = self.cache()
        result = self.show()
        self.assertEqual(result["last_check"]["status"], "valid")
        self.assertEqual(result["last_check"]["record"], saved)
        self.assertIs(result["last_check"]["ok"], True)
        self.assertEqual(result["completion"]["rows"][3]["state"], "not_run")
        for changes, reason in (({"main": "a" * 40}, "main_changed"),
                                ({"cmd": "old"}, "command_changed"), ({"task": "T2"}, "task_changed")):
            self.cache(**changes)
            cache = self.show()["last_check"]
            self.assertEqual(cache["status"], "stale")
            self.assertIn(reason, cache["stale_reasons"])
            self.assertIsNone(cache["ok"])
            if reason == "task_changed":
                self.assertIsNone(cache["record"], "不得泄漏别的任务缓存结果")
                self.assertIsNone(cache["checked_at"])
        self.cache()
        self.events.append({"ev": "done", "id": "T1", "sha": self.base, "t": 160, "gate": False})
        self.save()
        cache = self.show()["last_check"]
        self.assertEqual(cache["scope"], "retained_sample")
        self.assertEqual(cache["status"], "valid")

    def test_invalid_cache_and_unconfigured_command(self):
        for raw in (b"broken", b"\xff", b"[]", b"[" * 2000, b"x" * 65537):
            (self.data / ".check-result").write_bytes(raw)
            self.assertEqual(self.show()["last_check"]["status"], "invalid")
        for changes in ({"ok": 1}, {"t": float("nan")}, {"t": time.time() + 1000},
                        {"why": "\ud800"}, {"why": "x" * 4097}, {"why": "\0"}):
            self.cache(**changes)
            self.assertEqual(self.show()["last_check"]["status"], "invalid")
        self.cmd = ""
        self.configure()
        self.assertEqual(self.show()["last_check"]["unavailable_reason"], "check_not_configured")

    def test_routing_hold_replay_and_attention(self):
        route = self.repo / "task.md"
        route.write_text("路由：常规 / 交叉审查不要 / 影响面：改行为\n")
        self.events[0]["body"] = "任务文件：task.md\n做完：等我放行"
        self.save()
        result = self.show()
        self.assertEqual(result["routing"], {"source": "task_file_now", "tier": "常规",
                                            "cross": False, "overridden": False})
        self.assertIs(result["hold"]["enabled"], True)
        self.assertEqual(result["attention"]["reason"], "agent_status_not_queried")
        self.assertFalse(self.calls.exists())
        result = self.show("--with-agent-status")
        self.assertEqual(result["attention"]["state"], "suggested")
        self.assertIn("main_advanced", result["attention"]["unmet_rows"])
        self.assertEqual(self.calls.read_text().splitlines(), ["status fake/main"])
        for status, expected in (({"state": "unknown"}, "unknown"),
                                 ({"state": "idle", "idle_for": 999}, "unknown"),
                                 ({"state": "idle", "idle_for": 999, "last_input_source": "agent"}, "none"),
                                 ({"state": "idle", "idle_for": 10, "last_input_source": "send"}, "none")):
            self.reply.write_text(json.dumps({"ok": True, **status}))
            self.assertEqual(self.show("--with-agent-status")["attention"]["state"], expected)
        self.events[0]["body"] = "任务文件：task.md"
        self.events += [{"ev": "hold", "key": "T1", "on": True},
                        {"ev": "done", "id": "T1", "sha": self.base, "t": 160, "gate": True}]
        self.save()
        self.assertEqual(self.show()["attention"]["state"], "awaiting_release")
        self.events += [{"ev": "go", "id": "T1", "t": 190}, {"ev": "hold", "key": "T1", "on": False}]
        self.save()
        previous_calls = self.calls.read_text()
        historical = self.show("--with-agent-status")
        self.assertIs(historical["hold"]["enabled"], True)
        self.assertEqual(historical["hold"]["scope"], "task_end_events")
        self.assertEqual(historical["attention"]["state"], "not_applicable")
        self.assertEqual(self.calls.read_text(), previous_calls)
        route.write_bytes(b"\xff")
        self.assertIsNone(self.show()["routing"])

    def test_concurrent_writer_marks_snapshot_changed(self):
        # 假 status 服务在读取中模拟另一进程完成任务；查询自身仍只能发 status。
        self.fake.write_text("#!/bin/sh\n"
                             'printf "%s\\n" "$*" >> "$CALLS"\n'
                             f"printf '%s\\n' '{{\"ev\":\"done\",\"id\":\"T1\",\"t\":160,\"gate\":true}}' >> '{self.data}/tasks.state'\n"
                             "git commit -q --allow-empty -m 'concurrent writer'\n"
                             'cat "$REPLY"\n')
        result = self.invoke("T1", "--json", "--with-agent-status", external_writer=True)
        self.assertEqual(result["task"]["location"], "current")
        self.assertEqual(result["git"]["observed_main"], self.base)
        changed = next(w for w in result["warnings"] if w["code"] == "snapshot_changed")
        self.assertIn("tasks.state", changed["sources"])
        self.assertIn("git_refs", changed["sources"])

    def test_unreadable_state_and_bad_configuration(self):
        (self.data / "tasks.state").unlink()
        (self.data / "tasks.state").mkdir()
        self.assertEqual(self.invoke("T1", "--json", code=2)["error"]["code"], "state_unreadable")
        (self.repo / ".drover.conf").write_bytes(b"\xff")
        self.assertEqual(self.invoke("T1", "--json", code=2)["error"]["code"], "configuration_unreadable")

    def test_hold_not_implied_by_gate_and_missing_main(self):
        self.events.append({"ev": "done", "id": "T1", "sha": self.base, "t": 160, "gate": True})
        self.save()
        self.assertIs(self.show()["hold"]["enabled"], False)
        self.git("branch", "-m", "other")
        result = self.show()
        self.assertEqual(result["task"]["status"], "done")
        self.assertIsNone(result["git"]["observed_main"])
        self.assertIsNone(result["git"]["main_commits_since_start"])
        self.assertTrue(all(r["ok"] is None for r in result["completion"]["rows"]))

    def test_end_head_is_not_main_and_unmerged_branch(self):
        self.git("checkout", "-q", "-b", "work")
        self.git("commit", "-q", "--allow-empty", "-m", "work")
        head = self.git("rev-parse", "HEAD")
        result = self.show()
        self.assertEqual(result["git"]["observed_head"], head)
        self.assertEqual(result["git"]["observed_main"], self.base)
        self.assertEqual(result["git"]["range_commits"], 1)
        self.assertEqual(result["git"]["main_commits_since_start"], 0)
        self.assertEqual(result["completion"]["rows"][2]["state"], "unmet")
        self.events.append({"ev": "done", "id": "T1", "sha": head, "t": 160, "gate": True})
        self.save()
        result = self.show()
        self.assertEqual(result["task"]["status"], "done")
        self.assertEqual(result["git"]["end_head"], head)
        self.assertEqual(result["git"]["main_commits_since_start"], 0)
        self.assertEqual(result["completion"]["rows"][2]["state"], "unmet")

    def test_failed_git_command_does_not_look_like_zero_or_pass(self):
        real_git = shutil.which("git")
        wrapper = self.root / "git"
        self.env["PATH"] = str(self.root) + os.pathsep + self.env["PATH"]
        self.git("commit", "-q", "--allow-empty", "-m", "收尾: synthetic")
        for fail_command in ("rev-list", "diff-tree", "for-each-ref", "merge-base"):
            self.git("branch", "-f", "work", self.base)
            wrapper.write_text(f'#!/bin/sh\nfor arg in "$@"; do\n'
                               f'  if [ "$arg" = "{fail_command}" ]; then exit 128; fi\ndone\n'
                               f'exec "{real_git}" "$@"\n')
            wrapper.chmod(0o755)
            result = self.show()
            if fail_command == "rev-list":
                self.assertIsNone(result["git"]["range_commits"])
                self.assertIsNone(result["git"]["main_commits_since_start"])
            self.assertTrue(all(r["ok"] is None for r in result["completion"]["rows"][:3]))

    def test_no_marker_or_command_is_not_applicable(self):
        self.cmd = ""
        self.configure(extra="DONE_MARK=\n")
        result = self.show()
        self.assertEqual(result["completion"]["rows"][0]["state"], "not_applicable")
        self.assertEqual(result["completion"]["rows"][3]["state"], "not_applicable")
        self.assertEqual(result["warnings"], [])

    def test_raw_text_and_damaged_events(self):
        self.events[0]["body"] = "  原文\n\ud800\t\x1b[31m"
        self.save()
        self.assertEqual(self.show()["task"]["body"], self.events[0]["body"])
        for raw in ("[]\n", "{bad\n", "[" * 2000, '{"ev":"start","id":[],"t":100}\n'):
            (self.data / "tasks.state").write_text(raw)
            self.assertEqual(self.invoke("T1", "--json", code=2)["error"]["code"], "state_invalid")

    def test_unreadable_routing_path_is_optional(self):
        self.configure(extra="TASK_FILE_DIR=bad\0path\n")
        self.assertIsNone(self.show()["routing"])
        self.configure()
        self.events[0]["body"] = "任务文件：bad\0path"
        self.save()
        self.assertIsNone(self.show()["routing"])


if __name__ == "__main__":
    unittest.main()
