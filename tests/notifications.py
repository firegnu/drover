#!/usr/bin/env python3
"""通知定向验证：隔离 HOME、合成项目、假 corral / OS 发送器。"""
import importlib.machinery
import importlib.util
import json
import io
from contextlib import redirect_stderr
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

CLI = Path(os.environ.get('DROVER_BIN', Path(__file__).resolve().parents[1] / 'bin/drover')).resolve()
sys.dont_write_bytecode = True


class Notifications(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='drover-notifications-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.env = {**os.environ, 'HOME': str(self.home)}

    def cli(self, action, code=0):
        result = subprocess.run([sys.executable, str(CLI), 'notifications', action, '--json'],
                                cwd=self.root, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertEqual(result.stderr, '')
        return json.loads(result.stdout)

    def test_preferences_are_user_scoped_read_only_and_idempotent(self):
        expected = dict(schema_version=1, ok=True, scope='user', system_enabled=True,
                        revision=0, application='next_notification_check')
        self.assertEqual(self.cli('status'), expected)
        self.assertEqual(list(self.home.iterdir()), [])
        self.assertEqual(self.cli('on'), expected)
        expected.update(system_enabled=False, revision=1)
        self.assertEqual(self.cli('off'), expected)
        self.assertEqual(self.cli('off'), expected)
        self.assertEqual(self.cli('status'), expected)
        expected.update(system_enabled=True, revision=2)
        self.assertEqual(self.cli('on'), expected)
        self.assertEqual(self.cli('status'), expected)

    def engine_fixture(self):
        self.repo, self.data = self.root / 'repo', self.root / 'data'
        self.repo.mkdir()
        self.data.mkdir()
        self.projects = self.root / 'projects'
        self.projects.write_text(str(self.repo) + '\n')
        self.state = self.data / 'tasks.state'
        self.state.write_text('')
        (self.data / 'queue.md').write_text('## T2 next task\n')
        (self.repo / '.drover.conf').write_text(
            f'HANDOFF_DIR={self.data}\nMAIN_AGENT=fake/main\nTASK_GATE=1\n')
        self.log = self.root / 'notifications.log'
        sender = self.root / 'sender'
        sender.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$NOTIFY_LOG"\n')
        sender.chmod(0o755)
        corral = self.root / 'corral'
        corral.write_text("#!/bin/sh\nprintf '%s\\n' '{\"ok\":true,\"agents\":[]}'\n")
        corral.chmod(0o755)
        self.env.update(DROVER_NOTIFY_BIN=str(sender), NOTIFY_LOG=str(self.log),
                        DROVER_CORRAL_BIN=str(corral))
        env_patch = patch.dict(os.environ, self.env)
        env_patch.start()
        self.addCleanup(env_patch.stop)
        self.clock = 2800000000
        self.engine = self.load_engine()

    def load_engine(self):
        loader = importlib.machinery.SourceFileLoader('notification_test_cli', str(CLI))
        module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
        loader.exec_module(module)
        return module

    def observe(self):
        self.clock += 61
        with patch('time.time', return_value=self.clock):
            self.engine.tick(str(self.projects))

    def task(self, stamp=100, gate=True, title='任务 "引号"', **overrides):
        start = dict(ev='start', id='T1', title=title, sha='a' * 40, main='b' * 40, t=stamp)
        start.update(overrides)
        self.state.write_text(json.dumps(start) + '\n' + json.dumps(
            dict(ev='done', id='T1', sha='c' * 40, t=200, gate=gate)) + '\n')

    def sent(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_startup_scope_and_stable_identity(self):
        self.engine_fixture()
        self.task()
        self.observe()
        self.assertEqual(self.sent(), [], 'startup must baseline existing awaiting')
        self.task(stamp=101)
        before = self.state.read_bytes()
        self.observe()
        self.assertEqual(len(self.sent()), 1, 'new run with same task ID must notify')
        self.assertIn('做完了', self.sent()[0])
        self.assertIn(r'\"引号\"', self.sent()[0])
        self.assertEqual(self.state.read_bytes(), before, 'notifications must not release tasks')
        self.task(stamp=101, title='edited wording')
        self.observe()
        self.state.write_text('')
        self.observe()
        self.task(stamp=101)
        self.observe()
        self.engine = self.load_engine()
        self.observe()
        self.state.write_text('')
        self.observe()
        self.task(stamp=101)
        self.observe()
        self.assertEqual(len(self.sent()), 1, 'wording, absence and restart must retain seen identity')
        self.task(stamp=102, gate=False)
        self.observe()
        self.assertEqual(len(self.sent()), 1, 'auto completion has no awaiting notification')

    def test_revision_switch_and_read_failures_preserve_baseline(self):
        self.engine_fixture()
        self.state.write_bytes(b'\xff')
        self.observe()
        self.task()
        self.observe()
        self.assertEqual(self.sent(), [], 'failed first observation must not establish empty baseline')
        self.cli('off')
        self.task(stamp=101)
        self.observe()
        self.assertEqual(self.sent(), [])
        self.cli('on')
        self.observe()
        self.assertEqual(self.sent(), [], 'enabling must baseline existing tasks')
        self.task(stamp=102)
        self.observe()
        self.assertEqual(len(self.sent()), 1)
        self.cli('off')
        self.cli('on')
        self.task(stamp=103)
        self.observe()
        self.assertEqual(len(self.sent()), 1, 'off/on between checks must trigger baseline')
        self.task(stamp=104)
        self.observe()
        self.assertEqual(len(self.sent()), 2)

    def test_notification_throttle_does_not_throttle_progress(self):
        self.engine_fixture()
        self.observe()
        self.task()
        with patch('time.time', return_value=self.clock + 59):
            self.engine.tick(str(self.projects))
        self.assertEqual(self.sent(), [], 'notification checks are throttled for at least 60 seconds')
        self.observe()
        self.assertEqual(len(self.sent()), 1)

    def test_preference_errors_never_claim_success(self):
        directory = self.home / '.drover'
        directory.mkdir()
        prefs = directory / 'notifications.json'
        for contents in ('{', '[]', '{"schema_version":1,"system_enabled":0,"revision":0}',
                         '{"schema_version":1,"system_enabled":true,"revision":-1}',
                         '[' * 1100 + '0' + ']' * 1100):
            with self.subTest(contents=contents):
                prefs.write_text(contents)
                for action in ('status', 'off'):
                    result = self.cli(action, code=2)
                    self.assertFalse(result['ok'])
                    self.assertEqual(result['error']['code'], 'preferences_invalid')
                    self.assertTrue(result['error']['message'])
                self.assertEqual(prefs.read_text(), contents)
        prefs.unlink()
        prefs.mkdir()
        self.assertEqual(self.cli('status', code=2)['error']['code'], 'preferences_unreadable')
        prefs.rmdir()
        (directory / 'notifications.json.lock').unlink()
        directory.rmdir()
        directory.write_text('cannot create files here')
        self.assertEqual(self.cli('off', code=2)['error']['code'], 'preferences_write_failed')
        self.assertEqual(self.cli('unknown', code=2)['error']['code'], 'invalid_arguments')

    def test_missing_identity_idle_and_failed_sender_do_not_popup_or_retry(self):
        self.engine_fixture()
        self.observe()
        for field, value in (('t', None), ('t', True), ('t', float('nan')),
                             ('sha', ''), ('main', ''), ('id', '')):
            with self.subTest(field=field, value=value):
                self.task(**{field: value})
                self.observe()
                self.assertEqual(self.sent(), [])
        # idle with unmet checks remains visible through the unchanged Attention helpers.
        self.task()
        self.state.write_text(self.state.read_text().splitlines()[0] + '\n')
        self.observe()
        self.assertEqual(self.sent(), [])
        self.task()
        original = self.engine.NOTIFY_BIN
        self.engine.NOTIFY_BIN = str(self.root / 'missing-sender')
        self.observe()
        self.engine.NOTIFY_BIN = original
        self.observe()
        self.assertEqual(self.sent(), [], 'failed delivery is processed, never retried')
        self.task(stamp=101)
        self.observe()
        self.assertEqual(len(self.sent()), 1)
        alias = self.root / 'alias'
        alias.symlink_to(self.repo, target_is_directory=True)
        self.projects.write_text(str(alias) + '\n' + str(self.repo) + '\n')
        self.observe()
        self.assertEqual(len(self.sent()), 1, 'repository aliases share identity')

    def test_record_upgrade_and_observation_failure_during_switch(self):
        self.engine_fixture()
        records = self.home / '.drover/board-notified.json'
        records.parent.mkdir()
        records.write_text('["legacy-text-key"]')
        self.task()
        self.observe()
        self.assertEqual(self.sent(), [])
        self.task(stamp=101)
        self.observe()
        self.assertEqual(len(self.sent()), 1)
        self.cli('off')
        self.cli('on')
        self.state.write_text('{invalid')
        self.observe()
        self.task(stamp=102)
        self.observe()
        self.assertEqual(len(self.sent()), 1, 'failed observation cannot baseline a switched project')
        self.task(stamp=103)
        self.observe()
        self.assertEqual(len(self.sent()), 2)

    def test_preference_and_record_failures_do_not_block_real_loop_progress(self):
        self.engine_fixture()
        def git(*args):
            return subprocess.run(['git', '-C', str(self.repo), *args], env=self.env,
                                  check=True, text=True, capture_output=True).stdout.strip()
        git('init', '-q', '-b', 'main')
        git('config', 'user.name', 'test')
        git('config', 'user.email', 'test@example.com')
        git('commit', '--allow-empty', '-qm', 'base')
        corral = self.root / 'corral'
        corral.write_text("#!/bin/sh\nprintf '%s\\n' '{\"ok\":true,\"name\":\"fake/main\","
                          "\"state\":\"idle\",\"idle_for\":1000,\"last_input_source\":\"send\"}'\n")
        self.observe()
        prefs = self.home / '.drover/notifications.json'
        records = self.home / '.drover/board-notified.json'
        for mode in ('off', 'invalid-preferences', 'unwritable-record'):
            with self.subTest(mode=mode):
                self.state.write_text('')
                if mode == 'off':
                    self.cli('off')
                elif mode == 'invalid-preferences':
                    prefs.write_text('{')
                else:
                    prefs.write_text('{"schema_version":1,"system_enabled":true,"revision":2}')
                    records.unlink()
                    records.mkdir()
                (self.data / 'loop').touch()
                (self.data / '.loop-wait').write_text('{"reason":"empty"}')
                with redirect_stderr(io.StringIO()), patch('time.time', return_value=self.clock):
                    self.engine.tick(str(self.projects))
                events = [json.loads(line) for line in self.state.read_text().splitlines()]
                self.assertEqual([e['ev'] for e in events], ['start'], 'loop must still send next task')
                git('commit', '--allow-empty', '-qm', '收尾: synthetic completion')
                self.clock += 301
                with redirect_stderr(io.StringIO()):
                    self.observe()
                events = [json.loads(line) for line in self.state.read_text().splitlines()]
                self.assertEqual([e['ev'] for e in events], ['start', 'done'])
                self.assertTrue(events[-1]['gate'], 'notifications must not release the completed task')
        self.assertEqual(self.sent(), [])


if __name__ == '__main__':
    unittest.main()
