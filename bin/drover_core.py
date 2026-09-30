"""Task records and explicit transitions. No Git completion gates or scheduler.

Legacy events are decoded here, without rewriting them. CLI and board consume
this same projection; task mutations validate the snapshot again under one lock.
"""
from contextlib import contextmanager
import copy
import fcntl
import hashlib
import json
import math
import os
import re
import subprocess
import tempfile
import time
import uuid

SCHEMA = 2
TASK_HDR = re.compile(r'^##\s+(?:(T\d+)\s+)?(.+?)\s*$')
TRANSITIONS = {'done': ('running', 'awaiting_release'),
               'go': ('awaiting_release', 'done'),
               'return-to-pending': (('running', 'awaiting_release'), 'pending')}


class FlowError(Exception):
    def __init__(self, code, why):
        self.code, self.why = code, why
        super().__init__(why)


def locate_project():
    # Configuration identifies an already connected project; a missing Git
    # executable or broken ref must not prevent explicit submission/acceptance.
    path = os.path.realpath(os.getcwd())
    while True:
        if os.path.lexists(os.path.join(path, '.drover.conf')):
            return path
        parent = os.path.dirname(path)
        if os.path.lexists(os.path.join(path, '.git')) or parent == path:
            raise FlowError('not_configured', '请在已配置 .drover.conf 的目标项目内调用')
        path = parent


def read(path, missing=True):
    try:
        with open(path, encoding='utf-8', newline='') as f:
            return f.read()
    except FileNotFoundError:
        if missing:
            return ''
        raise FlowError('not_configured', '配置缺失')
    except (OSError, UnicodeError, ValueError) as exc:
        raise FlowError('state_unreadable', f'无法读取 {path}') from exc


def parse_conf(path, text=None):
    conf = {}
    for line in (read(path) if text is None else text).splitlines():
        m = re.match(r'\s*([A-Z_]+)=(.*)', line)
        if m:
            conf[m[1]] = m[2].strip().strip('"').strip("'")
    if conf.get('HANDOFF_DIR'):
        conf['HANDOFF_DIR'] = os.path.expanduser(conf['HANDOFF_DIR'])
    return conf


def task_blocks(text):
    blocks, cur = [], None
    for line in (text or '').splitlines():
        m = TASK_HDR.match(line)
        if m:
            cur = {'id': m[1], 'title': m[2], 'body': []}
            blocks.append(cur)
        elif cur is not None:
            cur['body'].append(line)
    for block in blocks:
        block['body'] = '\n'.join(block['body']).strip('\n')
    return blocks


def task_events(text):
    try:
        events = [json.loads(line) for line in (text or '').split('\n') if line.strip()]
        task_fold(events)
        return events
    except (ValueError, TypeError, KeyError, OverflowError, RecursionError) as exc:
        raise FlowError('state_invalid', '任务事件损坏或运行身份不明确') from exc


def task_fold(events):
    tasks = {}
    for index, e in enumerate(events):
        if (not isinstance(e, dict) or type(e.get('t')) not in (int, float)
                or not math.isfinite(e['t'])):
            raise ValueError('invalid event')
        ev, tid = e.get('ev'), e.get('id')
        if ev == 'hold':                 # Historical fact, no behavioral effect.
            if not e.get('key') or type(e.get('on')) is not bool:
                raise ValueError('invalid hold')
            continue
        if not isinstance(tid, str) or not re.fullmatch(r'T\d+', tid):
            raise ValueError('invalid task id')
        if any(k in e and not isinstance(e[k], str) for k in ('title', 'body', 'key', 'sha', 'main')):
            raise ValueError('invalid text')
        task = tasks.get(tid)
        active = [t for t in tasks.values() if t['status'] in ('running', 'awaiting_release')]
        if ev == 'start':
            if active or task and task['status'] != 'pending':
                raise ValueError('invalid start')
            run = e.get('run_id') or 'legacy:' + hashlib.sha256(
                json.dumps([index, tid, e['t'], e.get('sha'), e.get('main')], sort_keys=True, ensure_ascii=True).encode()).hexdigest()
            if not isinstance(run, str):
                raise ValueError('invalid run')
            old_runs = task.get('previous_runs', []) + [{k: v for k, v in task.items()
                                                        if k != 'previous_runs'}] if task else []
            task = {'id': tid, 'title': e.get('title', ''), 'body': e.get('body', ''),
                    'body_known': 'body' in e and 'title' in e,
                    'key': e.get('key', ''), 'start': e.get('sha', ''), 'main': e.get('main', ''),
                    't0': e['t'], 'status': 'running', 'run_id': run, 'previous_runs': old_runs}
            tasks[tid] = task
        elif ev in ('submitted', 'accepted', 'returned', 'done', 'go', 'return'):
            if not task:
                raise ValueError('missing start')
            if ev in ('submitted', 'accepted', 'returned') and e.get('run_id') != task['run_id']:
                raise ValueError('run mismatch')
            if ev in ('submitted', 'done'):
                if task['status'] != 'running' or ev == 'done' and type(e.get('gate')) is not bool:
                    raise ValueError('invalid submission')
                task.update(status='awaiting_release' if ev == 'submitted' or e['gate'] else 'done',
                            end=e.get('sha', ''), t1=e['t'])
                # A legacy gate=false event records completion, NOT user acceptance.
                task['submission'] = copy.deepcopy(e)
                if 'completion_record' in e:
                    task['completion_record'] = e['completion_record']
            elif ev in ('accepted', 'go'):
                if task['status'] != 'awaiting_release':
                    raise ValueError('invalid acceptance')
                task.update(status='done', t2=e['t'])
            else:
                if task['status'] not in ('running', 'awaiting_release'):
                    raise ValueError('invalid return')
                record = e.get('return_record')
                if (not isinstance(record, dict) or record.get('work_stopped') is not True
                        or not isinstance(record.get('reason'), str) or not record['reason'].strip()):
                    raise ValueError('invalid return record')
                task.update(status='pending', returned_at=e['t'])
                task.setdefault('return_history', []).append(record)
        elif ev == 'drop':
            if task and task['status'] != 'pending':
                # Old drop was allowed on Running; preserve it in the decoder only.
                if task['status'] != 'running':
                    raise ValueError('invalid drop')
            task = tasks.setdefault(tid, {'id': tid, 'title': e.get('title', ''), 'body': '',
                                          'key': e.get('key', ''), 'start': '', 'run_id': None})
            task.update(status='dropped', reason=e.get('reason', ''), t1=e['t'])
        else:
            raise ValueError('unknown event')
    current = next((t for t in tasks.values() if t['status'] == 'running'), None)
    awaiting = next((t['id'] for t in tasks.values() if t['status'] == 'awaiting_release'), None)
    return tasks, current, awaiting


def task_pending(blocks, tasks):
    active = {tid: t for tid, t in tasks.items() if t['status'] != 'pending'}
    keys = {t['key'] for t in active.values() if t.get('key')}
    pending = [dict(b) for b in blocks if not (b['id'] in active if b['id'] else b['title'] in keys)]
    for b in pending:
        old = tasks.get(b['id'])
        if old:
            b.update({k: v for k, v in old.items() if k not in ('id', 'title', 'body', 'status')})
        b['status'] = 'pending'
    return pending


def signature(path):
    try:
        s = os.stat(path)
        return [s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns]
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as exc:
        raise FlowError('state_unreadable', f'无法读取 {path}') from exc


def snapshot(repo, config_only=False):
    repo = os.path.realpath(repo)
    config_path = os.path.join(repo, '.drover.conf')
    signatures = {config_path: signature(config_path)}
    config = read(config_path, missing=False)
    conf = parse_conf(config_path, config)
    if not conf.get('HANDOFF_DIR') or '\0' in conf['HANDOFF_DIR']:
        raise FlowError('not_configured', '需要有效 HANDOFF_DIR')
    directory = os.path.realpath(os.path.join(repo, conf['HANDOFF_DIR']))
    snap = dict(repo=repo, directory=directory, config=config, conf=conf, signatures=signatures)
    if config_only:
        return snap
    for name, filename in (('state', 'tasks.state'), ('queue', 'queue.md')):
        path = os.path.join(directory, filename)
        signatures[path] = signature(path)
        snap[name] = read(path)
    pause_path = os.path.join(directory, 'paused')
    signatures[pause_path] = signature(pause_path)
    snap['paused'] = signatures[pause_path] is not None
    snap['events'] = task_events(snap['state'])
    snap['tasks'], snap['current'], snap['awaiting'] = task_fold(snap['events'])
    snap['pending'] = task_pending(task_blocks(snap['queue']), snap['tasks'])
    ensure_fresh(snap)
    return snap


def ensure_fresh(snap):
    if any(signature(p) != sig for p, sig in snap['signatures'].items()):
        raise FlowError('target_changed', '状态、配置或队列已改变；请刷新后重新确认，不自动重试')


def target_token(snap, action, target):
    identity = [snap[k] for k in ('repo', 'directory', 'config', 'state', 'queue', 'signatures')]
    return 'v2:' + hashlib.sha256(json.dumps([identity, action, target], sort_keys=True,
                                           ensure_ascii=True).encode()).hexdigest()


def ambiguous(todo, target):
    return any(t is not target and (t['id'] == target['id'] if t['id'] else t['title'] == target['title'])
               for t in todo)


def task_actions(snap, task, pos=None):
    actions = {}
    for action, (source, _) in TRANSITIONS.items():
        sources = (source,) if isinstance(source, str) else source
        if task['status'] in sources:
            reason = 'body_unavailable' if action == 'return-to-pending' and not task.get('body_known') else None
            actions[action] = {'target_token': None if reason else target_token(snap, action, task['id']),
                               'unavailable_reason': reason}
    if pos is not None:
        reason = ('target_ambiguous' if ambiguous(snap['pending'], task) else
                  'current_exists' if snap['current'] else 'awaiting_release' if snap['awaiting'] else
                  'paused' if snap['paused'] else None)
        actions['dispatch-pending'] = {'pos': pos, 'target_token': None if reason else
                                      target_token(snap, 'dispatch-pending', pos), 'unavailable_reason': reason}
    return actions


def notification_identity(repo, task):
    if not task or task.get('status') != 'awaiting_release':
        return None
    return json.dumps([os.path.realpath(repo), task['id'], task['run_id'], 'awaiting_release'],
                      ensure_ascii=True, separators=(',', ':'))


def listing(snap):
    def public(t):
        return {**t, 'actions': task_actions(snap, t),
                'notification_key': notification_identity(snap['repo'], t)} if t else None
    return {'schema_version': SCHEMA, 'ok': True, 'project': snap['repo'], 'paused': snap['paused'],
            'current': public(snap['current']), 'awaiting': public(snap['tasks'].get(snap['awaiting'])),
            'pending': [{**t, 'actions': task_actions(snap, t, pos)} for pos, t in enumerate(snap['pending'], 1)],
            'history': [public(t) for t in reversed(list(snap['tasks'].values()))
                        if t['status'] in ('done', 'dropped')]}


@contextmanager
def task_write_lock(directory):
    try:
        os.makedirs(directory, exist_ok=True)
        lock = open(os.path.join(directory, '.tasks.lock'), 'a')
    except OSError as exc:
        raise FlowError('write_failed', '无法打开任务操作锁') from exc
    with lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise FlowError('state_busy', '另一个写操作正在进行') from exc
        except OSError as exc:
            raise FlowError('write_failed', '无法锁定任务记录') from exc
        yield


def atomic_write(path, text):
    tmp = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=os.path.dirname(path),
                                         prefix='.drover-', delete=False) as f:
            tmp = f.name
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except (OSError, UnicodeError) as exc:
        raise FlowError('write_failed', '写入失败；请核对本地状态，不要自动重试') from exc
    finally:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def append_event(snap, event):
    ensure_fresh(snap)
    state = snap['state'] + ('\n' if snap['state'] and not snap['state'].endswith('\n') else '')
    atomic_write(os.path.join(snap['directory'], 'tasks.state'), state + json.dumps(event, ensure_ascii=True) + '\n')


def restore_queue(snap, task):
    # Restore the dispatched body before ending the run; a failed second write
    # can change ordering, but cannot remove the only recoverable task body.
    pre, blocks, cur = [], [], None
    for line in snap['queue'].splitlines(keepends=True):
        if TASK_HDR.match(line.rstrip('\r\n')):
            cur = []
            blocks.append(cur)
        (pre if cur is None else cur).append(line)
    kept = []
    for lines in blocks:
        raw = ''.join(lines)
        b = task_blocks(raw)[0]
        if b['id'] == task['id'] or not b['id'] and b['title'] == (task.get('key') or task['title']):
            continue
        kept.append(raw)
    restored = f"## {task['id']} {task['title']}\n{task['body']}\n\n"
    ensure_fresh(snap)
    path = os.path.join(snap['directory'], 'queue.md')
    prefix = ''.join(pre)
    if prefix and not prefix.endswith('\n'):
        prefix += '\n'
    atomic_write(path, prefix + restored + ''.join(kept))
    snap['signatures'][path] = signature(path)


def transition(repo, action, tid, token, reason='', work_stopped=False):
    initial = snapshot(repo, config_only=True)
    with task_write_lock(initial['directory']):
        snap = snapshot(repo)
        if initial['directory'] != snap['directory'] or token != target_token(snap, action, tid):
            raise FlowError('target_changed', '目标已过期；请刷新后重新确认')
        task = snap['tasks'].get(tid)
        if not task or action not in task_actions(snap, task):
            raise FlowError('invalid_state', '该任务当前状态不允许此操作；Running 请先 done，Awaiting 才能 go')
        if action == 'return-to-pending' and (not reason.strip() or not work_stopped):
            raise FlowError('invalid_arguments', '退回需要原因与 --work-stopped 明确确认')
        now = time.time()
        event = {'ev': {'done': 'submitted', 'go': 'accepted', 'return-to-pending': 'returned'}[action],
                 'id': tid, 'run_id': task['run_id'], 't': now}
        if action == 'return-to-pending':
            if not task.get('body_known'):
                raise FlowError('body_unavailable', '旧运行没有可恢复的任务正文；不猜测或改写队列')
            event['return_record'] = {'dispatched_at': task['t0'], 'returned_at': now,
                                      'reason': reason, 'work_stopped': True}
            restore_queue(snap, task)
        append_event(snap, event)
        return {'schema_version': SCHEMA, 'ok': True, 'task_id': tid, 'run_id': task['run_id'],
                'state': TRANSITIONS[action][1], 'record': {'status': 'recorded'}}


def git_value(repo, *args):
    try:
        r = subprocess.run(['git', '-C', repo, *args], capture_output=True, text=True, timeout=15)
        return r.stdout.rstrip('\n') if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError, UnicodeError):
        return None


def dispatch(repo, pos, token, send):
    initial = snapshot(repo, config_only=True)
    with task_write_lock(initial['directory']):
        snap = snapshot(repo)
        if initial['directory'] != snap['directory'] or token != target_token(snap, 'dispatch-pending', pos):
            raise FlowError('target_changed', '派发目标已过期；请刷新后重新确认')
        if not 1 <= pos <= len(snap['pending']):
            raise FlowError('target_changed', '目标不在 Pending 中')
        task = snap['pending'][pos - 1]
        reason = task_actions(snap, task, pos)['dispatch-pending']['unavailable_reason']
        if reason:
            raise FlowError(reason, '当前不能派发该待办；请查看 list')
        ids = list(snap['tasks']) + [b['id'] for b in task_blocks(snap['queue']) if b['id']]
        tid = task['id'] or 'T' + str(max([int(i[1:]) for i in ids], default=0) + 1)
        run_id = uuid.uuid4().hex
        text = f"TASK {tid}: {task['title']}" + ('\n\n' + task['body'] if task['body'] else '')
        agent = snap['conf'].get('MAIN_AGENT', '')
        # Git observations are optional reference metadata, never prerequisites.
        sha, main = git_value(repo, 'rev-parse', '--verify', 'HEAD'), git_value(repo, 'rev-parse', '--verify', 'main')
        ensure_fresh(snap)
        code, reply = send('send', agent, text, timeout=60) if agent else (None, {})
        reply = reply if isinstance(reply, dict) else {}
        confirmed = reply.get('confirmed') if type(reply.get('confirmed')) is bool else None
        merged = reply.get('merged_with_draft') if type(reply.get('merged_with_draft')) is bool else None
        status = ('not_sent' if not agent else 'confirmed' if code == 0 and reply.get('ok') is True and confirmed
                  else 'unconfirmed' if code in (0, 3) else 'rejected' if code in (2, 6, 7, 8) else 'unknown')
        result = {'schema_version': SCHEMA, 'ok': status in ('not_sent', 'confirmed'), 'task_id': tid,
                  'run_id': None, 'state': 'pending', 'record': {'status': 'not_attempted'},
                  'manual_text': text if not agent else None,
                  'delivery': {'status': status, 'attempted': bool(agent), 'corral_exit_code': code,
                               'confirmed': confirmed, 'merged_with_draft': merged}}
        if not result['ok']:
            result['error'] = {'code': {'unconfirmed': 'delivery_unconfirmed', 'rejected': 'send_rejected',
                                      'unknown': 'delivery_unknown'}[status],
                               'why': '请核对主控及记录；不要自动重发'}
        if not agent or code in (0, 3):
            try:
                append_event(snap, {'ev': 'start', 'id': tid, 'run_id': run_id, 't': time.time(),
                                    'title': task['title'], 'body': task['body'], 'key': task['title'],
                                    'sha': sha or '', 'main': main or ''})
                result.update(run_id=run_id, state='running', record={'status': 'recorded'})
            except FlowError as exc:
                result.update(ok=False, state='unknown', record={'status': 'unknown'},
                              error={'code': exc.code, 'why': exc.why + '；发送可能已送达'})
        return result


def evidence(snap, task):
    """Repository-wide reference facts, never attributed to this task or tested here."""
    repo = snap['repo']
    before = git_value(repo, 'show-ref', '--head')
    dirty = git_value(repo, 'status', '--porcelain', '--untracked-files=no')
    branches = git_value(repo, 'for-each-ref', '--format=%(refname:short)', '--no-merged=main', 'refs/heads/')
    head = git_value(repo, 'rev-parse', '--verify', 'HEAD')
    main = git_value(repo, 'rev-parse', '--verify', 'main')
    after = git_value(repo, 'show-ref', '--head')
    stale = before != after
    check = {'state': 'unknown', 'record': None, 'reason': 'no_record'}
    try:
        try:
            with open(os.path.join(snap['directory'], '.check-result'), encoding='utf-8') as f:
                raw = f.read(65537)
            if len(raw) > 65536:
                raise ValueError('oversized cache')
        except FileNotFoundError:
            raw = ''
        saved = json.loads(raw) if raw else None
        if saved is not None:
            if (not isinstance(saved, dict) or type(saved.get('t')) not in (int, float)
                    or not math.isfinite(saved['t']) or saved['t'] > time.time() + 5
                    or not all(isinstance(saved.get(k), str) and '\0' not in saved[k] for k in ('task', 'cmd', 'main', 'why'))
                    or len(saved['why']) > 4096
                    or 'ok' not in saved or type(saved.get('ok')) not in (bool, type(None))):
                raise ValueError('invalid cache')
            for key in ('task', 'cmd', 'main', 'why'):
                saved[key].encode('utf-8')
            # Legacy caches do not identify a run, so cannot certify a new run.
            current = (saved.get('run_id') == task.get('run_id') and saved['main'] == main
                       and saved['task'] == task['id'] and saved['cmd'] == snap['conf'].get('CHECK_CMD', ''))
            check = {'state': ('passed' if saved['ok'] else 'failed' if saved['ok'] is False else 'unknown')
                     if current and not stale else 'stale', 'record': saved,
                     'reason': None if current and not stale else 'reference_only_or_changed'}
    except (FlowError, OSError, ValueError, TypeError, RecursionError, OverflowError):
        check = {'state': 'unavailable', 'record': None, 'reason': 'invalid_or_unreadable_record'}
    return {'scope': 'repository_reference', 'controls_transition': False, 'observed_at': time.time(),
            'git': {'state': 'stale' if stale else 'available' if all(x is not None for x in (before, dirty, branches, head, main)) else 'unavailable',
                    'head_sha': head, 'main_sha': main, 'tracked_changes': dirty.split('\n') if dirty else [],
                    'unmerged_local_branches': branches.split('\n') if branches else []}, 'last_check': check}
