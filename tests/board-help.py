#!/usr/bin/env python3
"""? 快捷键帮助页：内容、Esc 原样返回、帮助页里操作键不触发、沙色与窄屏读全。只用合成 VM 和假屏幕。"""
import curses
from pathlib import Path
import runpy
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


def colors(n):
    B.COLORS.clear()
    with patch.object(B.curses, 'start_color'), patch.object(B.curses, 'use_default_colors'), \
         patch.object(B.curses, 'COLORS', n, create=True), patch.object(B.curses, 'init_pair'), \
         patch.object(B.curses, 'color_pair', side_effect=lambda i: i << 8):
        B.init_colors()


def run_tui(screen, vm):
    """跑真实 tui()：数据、写操作、编辑器都打桩，记下会不会被调用。"""
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


colors(256)

# 1. 纯按键层：? 打开；帮助页里操作键、选择键、鼠标都不产生动作；Esc/? 关闭；q 仍可退出
vm, _ = fixture('long', True)
pv = vm['projects'][1]
assert B.key_action(ord('?'), pv, {'sel': 1, 'n': 3}) == ('help', True)
assert B.key_action(ord('?'), None, {'n': 0}) == ('help', True), '没有项目也能看帮助'
inside = {'sel': 1, 'n': 3, 'help': True, 'detail_total': 80, 'detail_room': 10, 'detail_offset': 0}
for k in (ord('g'), ord('n'), ord('p'), ord('a'), ord('l'), ord('j'), ord('k'), curses.KEY_UP, curses.KEY_DOWN):
    act = B.key_action(k, pv, inside)
    assert not act or act[0] not in ('run', 'edit', 'sel', 'scroll'), (chr(k) if k < 256 else k, act)
assert B.key_action(curses.KEY_MOUSE, pv, inside, (0, 5, 5, 0, getattr(curses, 'BUTTON5_PRESSED', 0))) is None
assert B.key_action(ESC, pv, inside) == ('help', False)
assert B.key_action(ord('?'), pv, inside) == ('help', False)
assert B.key_action(ord('q'), pv, inside) == ('quit',)

# 2. 真实 tui：选第 2 个项目、翻一页详情 → ? → 狂按操作键 → Esc，画面与状态和打开前逐格一致
ops = [ord(c) for c in 'gnpaljk'] + [curses.KEY_UP, curses.KEY_DOWN, curses.KEY_NPAGE, curses.KEY_PPAGE, -1]
screen = Screen(24, 52, [curses.KEY_DOWN, curses.KEY_NPAGE, ord('?')] + ops + [ESC, ord('q')])
calls = run_tui(screen, vm)
assert calls == [], calls
before, opened, after = screen.frames[2], screen.frames[3], screen.frames[-1]
assert 'billing-api' in text(before) and before != screen.frames[1], '前置：选中第二个项目且已翻页'
assert before != opened and 'Keyboard help' in text(opened)
assert all('Keyboard help' in text(f) for f in screen.frames[3:-1]), '帮助页一直开着直到 Esc'
assert after == before, '返回后项目选择和滚动位置不变'

# 3. 内容：现有快捷键、用途、滚动说明全部可读；窄屏翻页也能读全；沙色、无反色
EXPECT = ['g', 'Verify', 'release', 'n', 'next task', 'p', 'Pause', 'resume', 'a', 'queue.md', 'l', 'loop',
          'r', 'Refresh', 'q', 'Quit', '↑↓', 'jk', 'Select project', '?', 'Esc',
          'PgUp', 'PgDn', 'Mouse wheel', 'task body', 'history']
for h, w in ((24, 20), (24, 32), (24, 40), (24, 52), (24, 80), (24, 99), (32, 120), (12, 52), (8, 30)):
    screen = Screen(h, w, [ord('?')] + [curses.KEY_NPAGE] * 12 + [ord('q')])
    run_tui(screen, vm)
    helps = screen.frames[1:]
    body = ''.join(t for f in helps for y, x, t, _ in f if 2 <= y < h - 3 and x < w - 1).replace(' ', '')
    for word in EXPECT:
        assert word.replace(' ', '') in body, ((h, w), word)
    for f in helps:
        assert not any(a & curses.A_REVERSE for *_, a in f), (h, w)
    first = helps[0]
    assert any(t == 'Keyboard help' and a == B.COLORS['h2'] for _, _, t, a in first), (h, w)
    assert any(t.strip() == 'g' and a == B.COLORS['key'] for _, _, t, a in first) or h < 12, (h, w)
    assert any(t == 'Esc' and a == B.COLORS['key'] for _, _, t, a in first), (h, w)
assert B.COLORS['key'] == B.COLORS['accent'] | curses.A_BOLD, '按键用沙色强调'

print('PASS 快捷键帮助页：? 打开、Esc 原样返回、操作键不触发、沙色、窄屏读全')
