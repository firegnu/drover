#!/usr/bin/env python3
"""显示层检查：字符网格、两栏滚动可达性、输入不变和小窗口边界。"""
import copy
import curses
from pathlib import Path
import runpy
from unittest.mock import patch

D = runpy.run_path(str(Path(__file__).with_name('board-demo.py')))
B = D['load_board']()
fixture = D['fixture']


class Screen:
    def __init__(self, h, w):
        self.h, self.w = h, w
        self.rows = []
    def getmaxyx(self): return self.h, self.w
    def erase(self): self.rows = []
    def addstr(self, y, x, text, attr=0):
        assert 0 <= y < self.h and 0 <= x < self.w, (y, x)
        assert x + B.width(text) <= self.w - (y == self.h - 1), (y, x, text)
        self.rows.append((y, x, text, attr))


# 换行不折叠空格或合法 Unicode；每行不超列宽、组合字符不被拆到下一行。
for text in ('中文标题' * 15, 'a  b\u00a0c\u2028d' * 12, 'Cafe\u0301' * 20, '/very-long/path/' * 12):
    for cols in (2, 3, 8, 19, 45, 70):
        lines = B.wrap_lines([('', 2, text)], cols)
        assert ''.join(t for _, _, t in lines) == text
        assert all(i + B.width(t) <= cols for _, i, t in lines), (cols, lines)
        assert all(not t.startswith('\u0301') for _, _, t in lines)

# 标准色无色终端仍保留文字，DIM 只留在分隔线上。
with patch.object(B.curses, 'start_color'), patch.object(B.curses, 'use_default_colors'), \
     patch.object(B.curses, 'init_pair'), patch.object(B.curses, 'color_pair', return_value=0):
    B.init_colors()
assert not B.COLORS['dim'] & curses.A_DIM
assert B.COLORS['bar'] & curses.A_REVERSE
assert B.COLORS['sel'] & curses.A_REVERSE

for scene in D['SCENES']:
    for multi in (False, True):
        vm, msg = fixture(scene, multi)
        original = copy.deepcopy(vm)
        for h, w in ((32, 120), (24, 80), (32, 160), (16, 60), (10, 40), (6, 20), (3, 12), (1, 1)):
            screen, state = Screen(h, w), {'sel': 0, 'n': len(vm['projects']), 'msg': msg, 'body_mouse': True}
            B.draw(screen, vm, state)
            assert screen.rows or (h, w) == (1, 1)
            if (h, w) == (32, 120) and not multi and scene == 'working':
                assert any(y == 5 and x == 1 and t == '任务正文' for y, x, t, _ in screen.rows)
                assert any(y == 5 and x == 74 and t.startswith('干活的 agent') for y, x, t, _ in screen.rows)
                assert not any(t == '项目' for _, _, t, _ in screen.rows)
            if (h, w) == (32, 120) and multi:
                assert any(t == '项目' for _, _, t, _ in screen.rows)
                assert not any(x > 23 and t == '│' for _, x, t, _ in screen.rows)
            if (h, w) == (24, 80):
                assert not any(t == '│' for _, _, t, _ in screen.rows)
                if multi:
                    assert any(y == 1 and '[1/3]' in t for y, _, t, _ in screen.rows)
                assert any(y == h - 2 and 'PgUp/Dn' in t and 'g 核对放行' in t for y, _, t, _ in screen.rows)
            # 真正翻所有页，包含辅助栏溢出。标记不能只存在于未绘制的逻辑行。
            seen = []
            while True:
                seen.extend(t for y, _, t, _ in screen.rows if 0 < y < h - 1)
                # 布局遍历也进入正文局部视口；输入分发/步长另由 T8 回归守住。
                if state.get('body_rect') and state['body_offset'] < state['body_total'] - state['body_page']:
                    state['body_offset'] += 1
                    B.draw(screen, vm, state)
                    continue
                before = state.copy()
                act = B.key_action(curses.KEY_NPAGE, vm['projects'][0], state)
                assert state == before
                if act[1] == state['detail_offset']:
                    break
                state['detail_offset'] = act[1]
                B.draw(screen, vm, state)
            if scene == 'long' and w >= 60 and h >= 16:
                text = ''.join(seen)
                for marker in ('【标题末尾】', '【正文末尾】', '【判据末尾】', '【路径末尾】', '【历史末尾】', '【消息末尾】', '待办59完整条目'):
                    assert marker in text, (w, h, multi, marker)
            if h >= 12:
                assert any(y == h - 1 and t.startswith(msg[:3]) for y, _, t, _ in screen.rows) if msg else not any(y == h - 1 for y, _, _, _ in screen.rows)
            # 缩放后偏移总在有效范围，全部输入保持原业务映射。
            for nh, nw in ((24, 80), (32, 120), (6, 20)):
                screen.h, screen.w = nh, nw
                B.draw(screen, vm, state)
                assert 0 <= state['detail_offset'] <= state['detail_total']
            assert vm == original

vm, msg = fixture('long', True)
state = {'sel': 0, 'n': 3, 'msg': msg}
screen = Screen(32, 120)
B.draw(screen, vm, state)
state['detail_offset'] = 10
state['sel'] = B.key_action(ord('j'), vm['projects'][0], state)[1]
B.draw(screen, vm, state)
assert state['detail_offset'] == 0
for key in ('h', '\t', '?', 'e'):
    assert B.key_action(ord(key), vm['projects'][0], state) is None
runpy.run_path(str(Path(__file__).with_name('board-tab-pty.py')), run_name='__main__')
print('PASS 字符网格：单/多项目、各类状态、列宽、双栏及正文全部末尾、缩放和输入不变')
