#!/usr/bin/env python3
"""Public CLI lifecycle contract; only temporary repositories and fake transports."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[1] / 'bin/drover'


class Flow(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='drover-flow-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.data = self.root / 'data'
        self.repo.mkdir()
        self.data.mkdir()
        self.env = {**os.environ, 'HOME': str(self.root / 'home'),
                    'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_CONFIG_NOSYSTEM': '1',
                    'DROVER_CORRAL_BIN': str(self.root / 'fake'),
                    'DROVER_NOTIFY_BIN': str(self.root / 'fake'), 'CALLS': str(self.root / 'calls')}
        fake = self.root / 'fake'
        fake.write_text('#!/usr/bin/env python3\nimport os,sys,json\n'
                        'with open(os.environ["CALLS"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n'
                        'print(os.environ.get("REPLY",\'{"ok":true,"confirmed":true}\'))\n'
                        'sys.exit(int(os.environ.get("SEND_CODE","0")))\n')
        fake.chmod(0o755)
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.com')
        self.git('commit', '-qm', 'base', '--allow-empty')
        (self.repo / '.drover.conf').write_text(f'HANDOFF_DIR={self.data}\nMAIN_AGENT=fake/main\nTASK_GATE=0\nCHECK_CMD=touch {self.root}/checked\n')
        (self.data / 'queue.md').write_text('## T1 A\nA body\n\n## T2 B\nB body\n')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo, env=self.env, text=True).strip()

    def cli(self, *args, code=0):
        p = subprocess.run([sys.executable, str(CLI), *args], cwd=self.repo,
                           env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(p.returncode, code, p.stdout + p.stderr)
        return json.loads(p.stdout)

    def listing(self):
        return self.cli('list', '--json')

    def start(self, pos=1):
        target = self.listing()['pending'][pos-1]['actions']['dispatch-pending']
        return self.cli('dispatch-pending', '--pos', str(pos), '--target-token', target['target_token'], '--json')

    def action(self, name, tid, code=0, token=None):
        if token is None:
            token = self.cli('show', tid, '--json')['task']['actions'][name]['target_token']
        args = [name, tid, '--target-token', token, '--json']
        if name == 'return-to-pending':
            args += ['--reason', 'needs revision', '--work-stopped']
        return self.cli(*args, code=code)

    def test_explicit_submit_accept_and_independent_tasks(self):
        self.start()
        self.git('checkout', '-qb', 'old-A')
        self.git('commit', '--allow-empty', '-qm', 'unfinished A work')
        self.git('checkout', '-q', 'main')
        self.action('return-to-pending', 'T1')
        self.assertEqual(self.cli('show', 'T1', '--json')['task']['status'], 'pending')
        self.assertFalse((self.data / 'paused').exists())
        self.start(2)
        self.assertIn('Running 请先 done', self.cli('go', code=2)['error']['why'])
        self.git('checkout', '-qb', 'B-unmerged')
        self.git('commit', '--allow-empty', '-qm', 'B reference work')
        self.git('checkout', '-q', 'main')
        self.assertEqual(set(self.cli('show','T2','--json')['evidence']['git']['unmerged_local_branches']), {'old-A','B-unmerged'})
        (self.repo / 'dirty').write_text('unfinished reference evidence')
        self.git('add', 'dirty')
        result = self.action('done', 'T2')
        self.assertEqual(result['state'], 'awaiting_release')
        self.assertFalse((self.root / 'checked').exists())
        self.assertIsNone(self.listing()['current'])
        self.action('go', 'T2')
        after = self.listing()
        self.assertIsNone(after['current'])
        self.assertEqual(after['pending'][0]['id'], 'T1')
        self.assertEqual(after['history'][0]['status'], 'done')
        self.assertIn('old-A', self.git('branch'))

    def test_board_uses_the_same_fold_and_has_no_automatic_engine(self):
        import importlib.machinery
        import importlib.util
        sys.path.insert(0, str(CLI.parent))
        loader = importlib.machinery.SourceFileLoader('flow_board', str(CLI.parent / 'drover-board'))
        board = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
        loader.exec_module(board)
        self.start()
        self.action('done', 'T1')
        events = board.task_events((self.data / 'tasks.state').read_text())
        tasks, current, awaiting = board.task_fold(events)
        self.assertEqual(awaiting, 'T1')
        self.assertEqual(tasks['T1']['status'], 'awaiting_release')
        self.assertIsNone(current)
        self.assertFalse(hasattr(board, 'loop_tick'))
        self.assertFalse(hasattr(board, 'close_if_done'))

    def raw(self, *args):
        p = subprocess.run([sys.executable, str(CLI), *args], cwd=self.repo, env=self.env,
                           capture_output=True, text=True, timeout=20)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return p.stdout

    def state_bytes(self):
        p = self.data / 'tasks.state'
        return p.read_bytes() if p.exists() else b''

    def save_events(self, events):
        (self.data / 'tasks.state').write_text(''.join(json.dumps(e) + '\n' for e in events))

    def old_start(self, tid='T1', t=1):
        sha = self.git('rev-parse', 'HEAD')
        return dict(ev='start', id=tid, title='old task', body='retained work', key='old task',
                    sha=sha, main=sha, t=t)

    def patched_cli(self, args, patch):
        script = 'import os,sys,runpy\nfrom unittest.mock import patch\n' + patch
        script += '\nsys.argv=sys.argv[1:]\nwith context:\n    runpy.run_path(sys.argv[0],run_name="__main__")\n'
        return subprocess.run([sys.executable, '-c', script, str(CLI), *args], cwd=self.repo,
                              env=self.env, capture_output=True, text=True, timeout=20)

    def test_return_awaiting_and_restart_preserves_submission(self):
        self.start()
        first = self.listing()['current']['run_id']
        self.action('done', 'T1')
        self.action('return-to-pending', 'T1')
        pending = self.cli('show', 'T1', '--json')['task']
        self.assertEqual(pending['submission']['ev'], 'submitted')
        self.assertFalse((self.data / 'paused').exists())
        self.start()
        now = self.listing()['current']
        self.assertNotEqual(first, now['run_id'])
        self.assertEqual(now['previous_runs'][0]['submission']['ev'], 'submitted')
        self.assertEqual(now['previous_runs'][0]['return_history'][0]['reason'], 'needs revision')
        self.action('done', 'T1')
        self.action('go', 'T1')
        self.assertEqual(len(self.listing()['history'][0]['previous_runs']), 1)

    def test_stale_duplicate_cross_action_and_cross_run_are_rejected(self):
        dispatch = self.start()
        old = self.cli('show', 'T1', '--json')['task']['actions']['done']['target_token']
        before = self.state_bytes()
        self.action('go', 'T1', code=3, token=old)
        self.assertEqual(before, self.state_bytes())
        self.action('done', 'T1', token=old)
        before = self.state_bytes()
        self.action('done', 'T1', code=3, token=old)
        self.assertEqual(before, self.state_bytes())
        self.action('return-to-pending', 'T1')
        self.start()
        self.action('done', 'T1', code=3, token=old)
        self.assertNotEqual(dispatch['run_id'], self.listing()['current']['run_id'])

    def test_token_does_not_depend_on_git_and_rejects_queue_config_pause_changes(self):
        self.start()
        token = self.cli('show', 'T1', '--json')['task']['actions']['done']['target_token']
        self.git('branch', 'unrelated')
        self.git('commit', '--allow-empty', '-qm', 'other change')
        self.action('done', 'T1', token=token)
        for path in (self.data / 'queue.md', self.repo / '.drover.conf', self.data / 'paused'):
            token = self.cli('show', 'T1', '--json')['task']['actions']['go']['target_token']
            path.write_text((path.read_text() if path.exists() else '') + '\n')
            self.action('go', 'T1', code=3, token=token)
        self.assertEqual(self.listing()['awaiting']['id'], 'T1')

    def test_failed_and_unavailable_evidence_never_blocks_or_becomes_passed(self):
        self.start()
        cur = self.listing()['current']
        record = dict(task='T1', main=self.git('rev-parse','main'), cmd=f'touch {self.root}/checked',
                      ok=False, why='exit 1', t=cur['t0'])
        (self.data / '.check-result').write_text(json.dumps(record))
        detail = self.cli('show','T1','--json')
        self.assertEqual(detail['evidence']['last_check']['state'], 'stale')
        self.assertFalse(detail['evidence']['last_check']['record']['ok'])
        record['run_id'] = cur['run_id']
        (self.data / '.check-result').write_text(json.dumps(record))
        self.assertEqual(self.cli('show','T1','--json')['evidence']['last_check']['state'], 'failed')
        self.git('update-ref', '-d', 'refs/heads/main')
        (self.data / '.check-result').write_text('{broken')
        detail = self.cli('show','T1','--json')
        self.assertEqual(detail['evidence']['git']['state'], 'unavailable')
        self.assertEqual(detail['evidence']['last_check']['state'], 'unavailable')
        self.action('done', 'T1')
        self.action('go', 'T1')
        self.assertFalse((self.root / 'checked').exists())

    def test_legacy_records_keep_facts_without_rewriting(self):
        receipt = dict(method='manual', reason='old override', confirmed_at=2)
        events = [self.old_start('T9'), dict(ev='done',id='T9',t=2,gate=False),
                  self.old_start('T8',3),dict(ev='done',id='T8',t=4,gate=True,completion_record=receipt),
                  dict(ev='go',id='T8',t=5), self.old_start('T1',6),
                  dict(ev='return',id='T1',t=7,return_record=dict(work_stopped=True,reason='old',dispatched_at=6,returned_at=7)),
                  self.old_start('T2',8)]
        self.save_events(events)
        before = self.state_bytes()
        data = self.listing()
        self.assertEqual(before,self.state_bytes())
        self.assertEqual(data['current']['status'],'running')
        self.assertTrue(data['current']['run_id'].startswith('legacy:'))
        hist = {t['id']:t for t in data['history']}
        self.assertNotIn('t2',hist['T9'])
        self.assertEqual(hist['T8']['completion_record'],receipt)
        self.assertEqual(data['pending'][0]['id'],'T1')
        self.action('done','T2')
        self.action('go','T2')
        self.assertTrue(self.state_bytes().startswith(before))

    def test_legacy_gate_false_go_preserves_acceptance_and_unblocks_project(self):
        self.save_events([self.old_start(), dict(ev='done', id='T1', t=2, gate=False),
                          dict(ev='go', id='T1', t=3)])
        before = self.state_bytes()
        data = self.listing()
        self.assertIsNone(data['current'])
        self.assertIsNone(data['awaiting'])
        historical = data['history'][0]
        self.assertEqual((historical['id'], historical['status'], historical['t1'], historical['t2']),
                         ('T1', 'done', 2, 3))
        self.assertEqual(self.cli('show', 'T1', '--json')['task']['t2'], 3)
        self.assertEqual(before, self.state_bytes())
        self.assertEqual(data['pending'][0]['id'], 'T2')
        self.start()
        self.action('done', 'T2')
        self.action('go', 'T2')
        historical = {t['id']: t for t in self.listing()['history']}
        self.assertEqual(historical['T1']['t2'], 3)
        self.assertEqual(historical['T2']['status'], 'done')
        self.assertTrue(self.state_bytes().startswith(before))

    def test_acceptance_decoder_keeps_new_transitions_strict(self):
        start = dict(self.old_start(), run_id='test-run')
        done = dict(ev='done', id='T1', t=2, gate=False)
        submitted = dict(ev='submitted', id='T1', t=2, run_id='test-run')
        accepted = dict(ev='accepted', id='T1', t=3, run_id='test-run')
        go = dict(ev='go', id='T1', t=3)
        for tail in ([accepted], [done, accepted],
                     [submitted, accepted, dict(accepted, t=4)],
                     [submitted, accepted, dict(go, t=4)],
                     [done, go, dict(go, t=4)]):
            with self.subTest(events=tail):
                self.save_events([start, *tail])
                before = self.state_bytes()
                self.assertEqual(self.cli('list', '--json', code=2)['error']['code'], 'state_invalid')
                self.assertEqual(before, self.state_bytes())

    def test_old_awaiting_returns_without_fabricating_new_submission(self):
        events = [self.old_start(),dict(ev='done',id='T1',t=2,gate=True)]
        self.save_events(events)
        self.action('return-to-pending','T1')
        task = self.cli('show','T1','--json')['task']
        self.assertEqual(task['submission']['ev'],'done')
        self.assertNotIn('t2', task)
        self.assertEqual([json.loads(e)['ev'] for e in self.state_bytes().splitlines()], ['start','done','returned'])

    def test_write_failure_never_claims_submission_or_acceptance(self):
        self.start()
        patch = '''original=os.replace
def fail(src,dst):
    if str(dst).endswith('/tasks.state'): raise OSError('synthetic disk failure')
    return original(src,dst)
context=patch('os.replace',fail)'''
        for name, status in (('done','running'),('go','awaiting_release')):
            token = self.cli('show','T1','--json')['task']['actions'][name]['target_token']
            before = self.state_bytes()
            p = self.patched_cli([name,'T1','--target-token',token,'--json'],patch)
            self.assertEqual(p.returncode,5,p.stdout+p.stderr)
            self.assertFalse(json.loads(p.stdout)['ok'])
            self.assertEqual(before,self.state_bytes())
            self.assertEqual(self.cli('show','T1','--json')['task']['status'],status)
            if name == 'done': self.action('done','T1')

    def test_return_partial_failure_retains_run_and_work_does_not_pause(self):
        self.start()
        (self.data / 'queue.md').write_text('## T2 B\nB body\n')
        token = self.cli('show','T1','--json')['task']['actions']['return-to-pending']['target_token']
        before = self.state_bytes()
        p = self.patched_cli(['return-to-pending','T1','--target-token',token,'--reason','retry','--work-stopped','--json'],
            '''original=os.replace
def fail(src,dst):
    if str(dst).endswith('/tasks.state'): raise OSError('synthetic disk failure')
    return original(src,dst)
context=patch('os.replace',fail)''')
        self.assertEqual(p.returncode,5,p.stdout+p.stderr)
        self.assertEqual(before,self.state_bytes())
        self.assertEqual(self.listing()['current']['id'],'T1')
        self.assertIn('A body',(self.data / 'queue.md').read_text())
        self.assertFalse((self.data / 'paused').exists())
        self.action('return-to-pending','T1')

    def test_pause_remains_explicit_and_does_not_block_submit_accept_return(self):
        self.start()
        self.raw('pause')
        self.action('done','T1')
        self.action('return-to-pending','T1')
        self.assertTrue(self.listing()['paused'])
        self.assertEqual(self.listing()['pending'][0]['actions']['dispatch-pending']['unavailable_reason'],'paused')
        self.raw('resume')
        self.assertIsNone(self.listing()['current'])
        self.start()

    def test_retired_paths_and_observer_cannot_progress(self):
        self.start()
        self.git('commit','--allow-empty','-qm','收尾: all checks look ready')
        (self.data / 'loop').touch()
        (self.data / '.loop-wait').write_text('{"reason":"empty"}')
        projects = self.root / 'projects'
        projects.write_text(str(self.repo)+'\n')
        before = self.state_bytes()
        for args in (('loop','--once'),('loop','on'),('next',),('hold','1','on'),('complete-manually','T1')):
            value=self.cli(*args,code=2)
            self.assertEqual(value['error']['code'],'command_retired')
        self.raw('notifications','watch','--once','--projects',str(projects))
        self.assertEqual(before,self.state_bytes())
        self.action('done','T1')
        self.action('go','T1')
        before = self.state_bytes()
        self.raw('notifications','watch','--once','--projects',str(projects))
        self.assertEqual(before,self.state_bytes())
        self.assertIsNone(self.listing()['current'])

    def test_send_outcomes_and_write_failure_are_honest(self):
        for code, reply, expected, recorded in (
            (7,{},'rejected',False),(1,{},'unknown',False),(3,{},'unconfirmed',True),
            (0,{'ok':True,'confirmed':False},'unconfirmed',True)):
            self.save_events([])
            self.env.update(SEND_CODE=str(code),REPLY=json.dumps(reply))
            token=self.listing()['pending'][0]['actions']['dispatch-pending']['target_token']
            value=self.cli('dispatch-pending','--pos','1','--target-token',token,'--json',code=8)
            self.assertEqual(value['delivery']['status'],expected)
            self.assertEqual(value['record']['status'],'recorded' if recorded else 'not_attempted')
            self.assertEqual(self.listing()['current'] is not None,recorded)
        self.save_events([])
        self.env.update(SEND_CODE='0',REPLY='{"ok":true,"confirmed":true}')
        token=self.listing()['pending'][0]['actions']['dispatch-pending']['target_token']
        p=self.patched_cli(['dispatch-pending','--pos','1','--target-token',token,'--json'],
            "context=patch('os.replace',side_effect=OSError('disk failure'))")
        self.assertEqual(p.returncode,5,p.stdout+p.stderr)
        value=json.loads(p.stdout)
        self.assertEqual(value['delivery']['status'],'confirmed')
        self.assertEqual(value['record']['status'],'unknown')
        self.assertIsNone(self.listing()['current'])

    def test_busy_lock_corrupt_records_and_read_only_queries(self):
        import fcntl
        self.assertFalse((self.data / '.tasks.lock').exists())
        self.listing()
        self.assertFalse((self.data / '.tasks.lock').exists())
        self.start()
        token=self.cli('show','T1','--json')['task']['actions']['done']['target_token']
        with (self.data / '.tasks.lock').open('a') as f:
            fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
            self.action('done','T1',code=4,token=token)
        (self.data / 'tasks.state').write_text('{broken')
        self.assertEqual(self.cli('list','--json',code=2)['error']['code'],'state_invalid')
        self.assertEqual(self.action('done','T1',code=2,token=token)['error']['code'],'state_invalid')
        self.assertEqual((self.data / 'tasks.state').read_text(),'{broken')

    def test_queue_edits_and_manual_dispatch_keep_existing_workflow(self):
        self.raw('add','C','notes')
        self.raw('move','3','1')
        self.raw('edit','1','C revised','new notes')
        self.assertEqual(self.listing()['pending'][0]['title'],'C revised')
        self.raw('drop','--pos','1','cancelled')
        self.assertEqual(self.listing()['history'][0]['status'],'dropped')
        conf=self.repo / '.drover.conf'
        conf.write_text(f'HANDOFF_DIR={self.data}\nMAIN_AGENT=\n')
        value=self.start()
        self.assertEqual(value['delivery']['status'],'not_sent')
        self.assertEqual(value['manual_text'],'TASK T1: A\n\nA body')
        self.assertFalse((self.root / 'calls').exists())

    def test_unnumbered_dispatch_and_ambiguous_queue(self):
        queue=self.data / 'queue.md'
        for content in ('## same\na\n## same\nb\n', '## T1 same\na\n## same\nb\n',
                        '## T1 a\na\n## T1 b\nb\n'):
            queue.write_text(content)
            target=self.listing()['pending'][0]['actions']['dispatch-pending']
            self.assertEqual(target['unavailable_reason'],'target_ambiguous')
            self.assertIsNone(target['target_token'])
        queue.write_text('## no number\nbody\n')
        value=self.start()
        self.assertEqual(value['task_id'],'T1')
        self.action('return-to-pending','T1')
        self.assertEqual(len(self.listing()['pending']),1)
        self.assertEqual(self.listing()['pending'][0]['id'],'T1')

    def test_show_unicode_refs_no_agent_and_historical_evidence_is_labelled(self):
        self.start()
        name='topic-甲\u2028乙\u00a0'
        self.git('branch',name)
        self.git('checkout','-q',name)
        self.git('commit','--allow-empty','-qm','branch work')
        self.git('checkout','-q','main')
        calls=(self.root / 'calls').read_bytes()
        detail=self.cli('show','T1','--json')
        self.assertIn(name,detail['evidence']['git']['unmerged_local_branches'])
        self.assertEqual((self.root / 'calls').read_bytes(),calls)
        self.action('done','T1')
        self.action('go','T1')
        detail=self.cli('show','T1','--json')
        self.assertEqual(detail['evidence']['scope'],'repository_reference')
        self.assertFalse(detail['evidence']['controls_transition'])
        self.assertEqual(detail['task']['actions'],{})
        self.cli('show','T1','--json','--with-agent-status')
        self.assertIn('status',(self.root / 'calls').read_text())

    def test_invalid_cache_is_reference_only_and_cannot_crash(self):
        self.start()
        for raw in ('['*2000+'0'+']'*2000, 'x'*65537, '[]', '{"ok":true}'):
            (self.data / '.check-result').write_text(raw)
            self.assertEqual(self.cli('show','T1','--json')['evidence']['last_check']['state'],'unavailable')
        self.action('done','T1')

    def test_missing_legacy_body_and_required_return_confirmation(self):
        e=self.old_start()
        del e['body']
        self.save_events([e])
        action=self.cli('show','T1','--json')['task']['actions']['return-to-pending']
        self.assertIsNone(action['target_token'])
        self.assertEqual(action['unavailable_reason'],'body_unavailable')
        self.action('done','T1')
        self.action('go','T1')
        self.assertEqual(self.listing()['history'][0]['status'],'done')

    def test_board_actions_use_observed_tokens_and_never_convert_running_go(self):
        import runpy
        from unittest.mock import patch
        with patch.dict(os.environ,self.env):
            b=runpy.run_path(str(CLI.parent / 'drover-board'))
            board=b['project_state'].__globals__
            conf=board['parse_conf'](str(self.repo / '.drover.conf'))
            self.start()
            def vm():
                return board['project_vm'](board['project_state'](str(self.repo),conf))
            view=vm()
            self.assertEqual(board['key_action'](ord('g'),view,{})[0],'note')
            self.assertIsNone(board['key_action'](ord('l'),view,{}))
            cmd=board['key_action'](ord('d'),view,{})[1]
            self.assertEqual(cmd[0],'done')
            self.cli(*cmd)
            self.cli(*cmd,code=3)
            view=vm()
            main,_=board['detail_sections'](view)
            self.assertFalse(any('Checks passed' in line[2] for line in main))
            self.cli(*board['key_action'](ord('g'),view,{})[1])
            self.assertIsNone(self.listing()['current'])
            view=vm()
            self.assertIsNone(view['queue']['finished'][0]['commits'], 'new submissions have no recorded Git end point')
            self.assertEqual(board['key_action'](ord('n'),view,{})[1][0],'dispatch-pending')
            (self.data / 'tasks.state').write_text('{broken')
            projects=self.root / 'projects'
            projects.write_text(str(self.repo)+'\n')
            self.assertIsNone(board['collect'](str(projects))[0]['tasks'])

    def test_shared_lock_is_held_during_transport(self):
        import socket
        path=str(self.root / 'send.sock')
        fake=self.root / 'fake'
        fake.write_text('#!/usr/bin/env python3\nimport socket,json\n'
                        f'with socket.socket(socket.AF_UNIX) as s:\n s.connect({path!r})\n s.sendall(b"ready")\n s.recv(1)\n'
                        'print(json.dumps({"ok":True,"confirmed":True}))\n')
        token=self.listing()['pending'][0]['actions']['dispatch-pending']['target_token']
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(path)
            server.listen(1)
            server.settimeout(10)
            proc=subprocess.Popen([sys.executable,str(CLI),'dispatch-pending','--pos','1',
                                   '--target-token',token,'--json'],cwd=self.repo,env=self.env,
                                  stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            connection=None
            try:
                connection,_=server.accept()
                self.assertEqual(connection.recv(5),b'ready')
                self.cli('dispatch-pending','--pos','1','--target-token',token,'--json',code=4)
                self.cli('pause',code=4)
                self.cli('add','concurrent',code=4)
                self.assertIsNone(self.listing()['current'])
            finally:
                if connection:
                    connection.sendall(b'x')
                    connection.close()
                out,err=proc.communicate(timeout=20)
            self.assertEqual(proc.returncode,0,out+err)
            self.assertEqual(json.loads(out)['state'],'running')

    def test_submit_and_accept_do_not_need_git_executable(self):
        self.start()
        for action in ('done', 'go'):
            token=self.cli('show','T1','--json')['task']['actions'][action]['target_token']
            p=self.patched_cli([action,'T1','--target-token',token,'--json'],
                "context=patch('subprocess.run',side_effect=FileNotFoundError('git unavailable'))")
            self.assertEqual(p.returncode,0,p.stdout+p.stderr)
            self.assertTrue(json.loads(p.stdout)['ok'])

    def test_legacy_unicode_events_and_cache_text_validation(self):
        event=self.old_start()
        event['title']='甲\u2028乙\u0085丙'
        (self.data / 'tasks.state').write_text(json.dumps(event,ensure_ascii=False)+'\n')
        self.assertEqual(self.listing()['current']['title'],event['title'])
        for why in ('bad\0text', 'surrogate\ud800', 'x'*4097):
            (self.data / '.check-result').write_text(json.dumps(dict(task='T1', main='a', cmd='', ok=False, why=why, t=1)))
            self.assertEqual(self.cli('show','T1','--json')['evidence']['last_check']['state'],'unavailable')
        self.action('done','T1')

    def test_return_restores_body_after_unterminated_queue_preamble(self):
        self.start()
        (self.data / 'queue.md').write_text('intro without final newline')
        self.action('return-to-pending','T1')
        self.assertEqual(self.listing()['pending'][0]['id'],'T1')
        self.assertTrue((self.data / 'queue.md').read_text().startswith('intro without final newline\n## T1'))


if __name__ == '__main__':
    unittest.main()
