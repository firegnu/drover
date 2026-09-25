#!/usr/bin/env python3
"""u 待办详情页：打开、↑↓/jk 切换、Esc 原样返回、操作键不触发、任务单三种情况、PgUp/PgDn 读全、帮助页与底栏提示。
只用合成 VM、临时目录里的合成仓库和假屏幕。"""
import copy
import curses
from pathlib import Path
import runpy
import tempfile
from unittest.mock import patch

D = runpy.run_path(str(Path(__file__).with_name('board-demo.py')))
B = D['load_board']()
fixture = D['fixture']
ESC = 27


class Screen:
    def __init__(self, h, w, keys=()):
        self.h, self.w, self.keys = h, w, list(keys)
        self.rows, self.frames = [], []
    def getmaxyx(self): return self.h, self.w
    def erase(self): self.rows = []
    def timeout(self, ms): pass
    def refresh(self): self.frames.append(sorted(self.rows))
    def getch(self): return self.keys.pop(0)
    def addstr(self, y, x, text, attr=0):
        assert 0 <= y < self.h and 0 <= x < self.w, (y, x)
        assert x + B.width(text) <= self.w - (y == self.h - 1), (y, x, text)
        self.rows.append((y, x, text, attr))


def run_tui(screen, vm):
    calls = []
    with patch.object(B, 'collect', lambda _: None), patch.object(B, 'view_model', lambda _: vm), \
         patch.object(B, 'init_colors', lambda: None), patch.object(B, 'init_mouse', lambda: True), \
         patch.object(B, 'run_drover', lambda *a, **k: calls.append(('run', a)) or 'ran'), \
         patch.object(B, 'edit_queue', lambda *a: calls.append(('edit', a)) or 'edited'), \
         patch.object(B.curses, 'curs_set', lambda _: None), \
         patch.object(B.curses, 'set_escdelay', lambda _: None, create=True):
        B.tui(screen, '/nonexistent')
    return calls


def text(frame):
    return '\n'.join(t for _, _, t, _ in frame)


# 1. 数据层：只认正文显式的「任务文件：」；找得到读全文，找不到 text 为 None，没写就没有这一项
with tempfile.TemporaryDirectory() as repo:
    (Path(repo) / 'docs').mkdir()
    (Path(repo) / 'docs/t1.md').write_text('# T1 任务单\n\n任务单正文第二段\n', encoding='utf-8')
    (Path(repo) / 'docs/T2 同名前缀.md').write_text('# 不该被按标题匹配出来\n', encoding='utf-8')
    tv = {'card': None, 'paused': False, 'loop': False, 'gate': True, 'awaiting': None, 'done': 0, 'dropped': 0,
          'holds': set(), 'finished': [], 'todo': [
              {'id': 'T1', 'title': '有引用', 'body': '任务文件：docs/t1.md\n按任务文件做。\n'},
              {'id': 'T2', 'title': '没有引用', 'body': '只有正文'},
              {'id': None, 'title': '引用缺失', 'body': '任务文件： docs/missing.md'}]}
    todo = B.queue_vm({'repo': repo, 'crew': []}, tv)['todo']
    assert todo[0]['body'] == ['任务文件：docs/t1.md', '按任务文件做。'], todo[0]
    assert todo[0]['task_file'] == {'path': 'docs/t1.md', 'text': ['# T1 任务单', '', '任务单正文第二段']}, todo[0]
    assert todo[1]['task_file'] is None, '没写那一行就不去按标题前缀找'
    assert todo[2]['task_file'] == {'path': 'docs/missing.md', 'text': None}, todo[2]

# 合成看板：第 2 个项目的待办带正文；第 1 件有任务单，第 2 件缺，其余没引用
vm, _ = fixture('long', True)
vm = copy.deepcopy(vm)
for p in vm['projects']:
    for i, t in enumerate(p['queue']['todo']):
        t.update(body=[f'{t["id"]} 正文第一行', '', f'{t["id"]} 正文末行【{i}】'], task_file=None)
pv = vm['projects'][1]
todo = pv['queue']['todo']
todo[0]['task_file'] = {'path': 'docs/任务/T43.md',
                        'text': [f'任务单第{i:02d}行：' + '很长的说明 ' * 6 for i in range(40)] + ['【任务单末尾】']}
todo[1]['task_file'] = {'path': 'docs/任务/T44 丢了.md', 'text': None}

# 2. 纯按键层：u 打开；没有待办不打开；详情页里操作键、项目选择、鼠标都不产生动作
assert B.key_action(ord('u'), pv, {'sel': 1, 'n': 3}) == ('pending', True)
empty = copy.deepcopy(pv)
empty['queue']['todo'] = []
assert B.key_action(ord('u'), empty, {'sel': 1, 'n': 3})[0] != 'pending'
assert B.key_action(ord('u'), dict(pv, queue=None), {'sel': 1, 'n': 3})[0] != 'pending'
inside = {'sel': 1, 'n': 3, 'pending': True, 'pending_sel': 1, 'pending_n': 3,
          'pending_total': 80, 'pending_room': 10, 'pending_offset': 0}
for k in (ord('g'), ord('n'), ord('p'), ord('a'), ord('l'), ord('u'), ord('?')):
    assert B.key_action(k, pv, inside) is None, chr(k)
assert B.key_action(curses.KEY_MOUSE, pv, inside, (0, 5, 5, 0, getattr(curses, 'BUTTON5_PRESSED', 0))) is None
for k, want in ((curses.KEY_UP, 0), (ord('k'), 0), (curses.KEY_DOWN, 2), (ord('j'), 2)):
    assert B.key_action(k, pv, inside) == ('pending_sel', want), (k, want)
assert B.key_action(ord('j'), pv, dict(inside, pending_sel=2)) is None, '到头就停'
assert B.key_action(ord('k'), pv, dict(inside, pending_sel=0)) is None, '到头就停'
assert B.key_action(curses.KEY_NPAGE, pv, inside) == ('pending_scroll', 9)
assert B.key_action(ESC, pv, inside) == ('pending', False)
assert B.key_action(ord('q'), pv, inside) == ('quit',)
assert B.key_action(ord('r'), pv, inside) == ('refresh',)

# 3. 真实 tui：选第 2 个项目、翻一页 → u → j 切到第 2 件 → 狂按操作键 → Esc，画面与状态和打开前逐格一致
ops = [ord(c) for c in 'gnpal?u'] + [curses.KEY_NPAGE, curses.KEY_PPAGE]
screen = Screen(24, 52, [curses.KEY_DOWN, curses.KEY_NPAGE, ord('u'), ord('j')] + ops + [ESC, ord('q')])
calls = run_tui(screen, vm)
assert calls == [], calls
before, opened, second, after = screen.frames[2], screen.frames[3], screen.frames[4], screen.frames[-1]
assert 'billing-api' in text(before) and before != screen.frames[1], '前置：选中第二个项目且已翻页'
assert 'Up next 1/' in text(opened) and 'T43 正文第一行' in text(opened), text(opened)
assert 'Up next 2/' in text(second) and 'Task file not found: docs/任务/T44 丢了.md' in text(second), text(second)
assert all('Up next 2/' in text(f) for f in screen.frames[4:-1]), '详情页一直开着直到 Esc'
assert after == before, '返回后项目选择和滚动位置不变'

# 4. 内容：正文、任务单全文窄屏翻页读全；没引用的不出现 Task file 这一节；k 回到第 1 件
for h, w in ((24, 20), (24, 40), (24, 80), (12, 52), (8, 30)):
    screen = Screen(h, w, [curses.KEY_DOWN, ord('u')] + [curses.KEY_NPAGE] * 80 + [ord('q')])
    run_tui(screen, vm)
    pages = screen.frames[2:]
    body = ''.join(t for f in pages for y, x, t, _ in f if 2 <= y < h - 3 and x < w - 1).replace(' ', '')
    for word in ['T43正文第一行', 'T43正文末行【0】', 'Taskfile', 'docs/任务/T43.md', '任务单第00行', '任务单第39行', '【任务单末尾】']:
        assert word in body, ((h, w), word)
    for f in pages:
        assert not any(a & curses.A_REVERSE for *_, a in f), (h, w)
screen = Screen(24, 80, [curses.KEY_DOWN, ord('u'), ord('j'), ord('j'), ord('k'), ord('k'), ord('k'), ord('q')])
run_tui(screen, vm)
third, back = screen.frames[4], screen.frames[-1]
assert 'Up next 3/' in text(third) and 'T45 正文第一行' in text(third) and 'Task file' not in text(third), text(third)
assert 'Up next 1/' in text(back), text(back)

# 5. 发现入口：? 帮助页有 u 一行，看板底栏有 u 提示
screen = Screen(40, 100, [ord('?'), ord('q')])
run_tui(screen, vm)
rows = {}
for y, _, t, _ in screen.frames[1]:
    rows[y] = rows.get(y, '') + t
assert any(r.startswith('u ') and 'pending' in r for r in rows.values()), rows
footer = [t for y, _, t, _ in screen.frames[0] if y == 38]
assert 'u' in footer, footer

print('PASS 待办详情页：u 打开、↑↓/jk 切换、Esc 原样返回、操作键不触发、任务单三种情况、窄屏读全、帮助与底栏提示')
