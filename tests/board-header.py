#!/usr/bin/env python3
"""窄面板三行 header：排版预算、去重、优先级、完整原文可达、配色与缩放。只用合成 VM。"""
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


def row(screen, y):
    """按列位置拼回一行（前导空格保留，行尾空白去掉）。"""
    out = ''
    for _, x, t, _ in sorted(r for r in screen.rows if r[0] == y):
        out += ' ' * (x - B.width(out)) + t
    return out.rstrip()


def colors(n):
    B.COLORS.clear()
    with patch.object(B.curses, 'start_color', side_effect=None if n else curses.error), \
         patch.object(B.curses, 'use_default_colors'), patch.object(B.curses, 'COLORS', n, create=True), \
         patch.object(B.curses, 'init_pair'), patch.object(B.curses, 'color_pair', side_effect=lambda i: i << 8):
        B.init_colors()


def pages(screen, vm, state):
    """翻完全部详情页（含正文、历史局部视口），返回 [(header 三行)] 和详情区逐行文字。"""
    B.draw(screen, vm, state)
    heads, seen = [row(screen, y) for y in range(3)], []
    while True:
        top = screen.h - 2 - state['detail_room']
        page = state['detail_room'] - (state['detail_total'] > state['detail_room'])
        seen += [t for y, _, t, _ in sorted(screen.rows) if top <= y < top + page]
        if state.get('body_rect') and state['body_offset'] < state['body_total'] - state['body_page']:
            state['body_offset'] += 1
        elif state.get('history_rect') and state['history_offset'] < state['history_total'] - state['history_page']:
            state['history_offset'] += 1
        else:
            act = B.key_action(curses.KEY_NPAGE, (vm['projects'] or [None])[state.get('sel', 0)], state)
            offset = act[1] if act else state['detail_offset']
            if offset == state['detail_offset']:
                return heads, ''.join(seen)
            state['detail_offset'] = offset
        B.draw(screen, vm, state)


def variants():
    for scene in D['SCENES']:
        for multi in (False, True):
            yield scene, multi, *fixture(scene, multi)
    vm, msg = fixture('working', True)
    for p in vm['projects']:  # 长项目名、中英文、组合字符、Tab；标题同样带 Tab
        p['name'] = p['name'] + '/超长项目名\tCafé-' + 'x' * 30 + '【项目末尾】'
    vm['projects'][0]['queue']['card']['title'] = '标题\t含 Tab 与 é'
    yield 'unicode', True, vm, msg
    yield 'none', False, {'health': {'ok': False, 'text': 'corral unavailable: synthetic【无项目错误】'},
                          'waits': [], 'projects': []}, ''


PRIORITY = ('!', 'corral', 'Paused', 'loop ')
colors(256)
for scene, multi, vm, msg in variants():
    original = copy.deepcopy(vm)
    pv = vm['projects'][0] if vm['projects'] else None
    q = pv['queue'] if pv else None
    c = q['card'] if q else None
    for w in (20, 32, 40, 52, 80, 99):
        screen, state = Screen(24, w), {'sel': 0, 'msg': msg, 'body_mouse': True}
        heads, details = pages(screen, vm, state)
        where = (scene, multi, w)
        assert set(row(screen, 3).strip()) == {'─'} and not any(t == '─' * (w - 2) for y, _, t, _ in screen.rows if y != 3), where
        assert heads[0].startswith(' drover'), where
        header = ' '.join(heads)
        assert '\t' not in header, where
        # 去重：没有黄色切换条、相邻项目、重复的 Idle 和添加提示；项目名只在产品标识旁出现一次
        for gone in ('Idle', 'press a', '›', '↑↓/jk', '[', '1/1'):
            assert gone not in header, (where, gone, heads)
        assert not any(a & curses.A_REVERSE for y, _, _, a in screen.rows if y < 3), where
        if pv:
            assert pv['name'][:4] not in heads[1] + heads[2], where
        # 优先级：第一行出现的状态，比它优先的（本场景存在时）一定也在
        present = [bool(vm['waits']), not vm['health']['ok'], bool(q and q['paused']), bool(q)]
        visible = [token in heads[0] for token in PRIORITY]
        for i, lower in enumerate(visible):
            assert not lower or all(visible[j] for j in range(i) if present[j]), (where, heads[0])
        if w >= 52:
            assert all(v for v, p in zip(visible, present) if p), (where, heads[0])
            if q and not q['paused'] and scene != 'unicode':  # 长项目名时同义的模式词先让出
                assert ('Manual' if not q['loop'] else q['mode']) in heads[0], (where, heads[0])
        # 完整原文：header 里没放全的，详情里逐字可达
        full = [vm['health']['text']]
        if pv:
            full.append(pv['name'].replace('\t', '    '))
        if multi and pv:
            full.append(f'1/{len(vm["projects"])}')
        if vm['waits'] and len(vm['waits']) != len(pv['waits'] if pv else []):
            full.append(f'Needs you {len(vm["waits"])}')
        elif vm['waits']:  # 全属当前项目：详情原有的「Needs you · N」就是完整副本
            assert f'Needs you · {len(vm["waits"])}' in details, where
        if q:
            full += ['Paused' if q['paused'] else 'Manual' if not q['loop'] else q['mode'],
                     'loop on' if q['loop'] else 'loop off']
        if c:
            full += [B.task_heading(pv).replace('\t', '    '), B.task_metrics(pv)]
        elif pv:
            full.append(f'HEAD {pv["head"]}')
        for text in full:
            assert text in header or text in details, (where, text)
        if c:  # 当前任务在第二行，指标在第三行
            assert heads[1].startswith(' ■ Ready to rel' if c['waiting'] else ' ▶ In progress'), where
            assert heads[2].startswith(' Elapsed'), where
        else:
            quiet = '○ ' + ('No registered projects' if not pv else 'No task queue' if not q else
                            'No active task' if q['todo'] else 'Queue empty')
            assert heads[1].strip() == B.trunc(quiet, w - 2) and (quiet in header or quiet in details), where
        assert vm == original, where
    # 宽屏和极矮屏保持原布局：顶栏还是「drover · 项目」一行
    for h, w in ((32, 100), (32, 120), (10, 52), (11, 80)):
        screen = Screen(h, w)
        B.draw(screen, vm, {'sel': 0, 'msg': msg, 'body_mouse': True})
        assert row(screen, 0).startswith(' drover · '), (scene, h, w)

# Tab 展开后才超宽的临界标题/指标：判断要不要补完整副本，必须按展开后的显示宽度（主控首轮审查）
# 标题：52 列（内容宽 50）下原宽 48–50、展开后 51–53；指标：路由档位带 Tab，73–75 列同样落在临界区
for w, n, tier in [(52, n, '常规') for n in (25, 26, 27)] + [(w, 25, 'Y' * 10 + '\tEND') for w in (73, 74, 75)]:
    for multi in (False, True):
        vm, _ = fixture('working', multi)
        pv = vm['projects'][0]
        pv['queue']['card']['title'] = 'X' * n + '\tEND'
        pv['queue']['card']['route']['tier'] = tier
        original = copy.deepcopy(vm)
        heads, details = pages(Screen(24, w), vm, {'sel': 0, 'body_mouse': True})
        for text in (B.task_heading(pv), B.task_metrics(pv)):
            text = text.replace('\t', '    ')
            assert text in ' '.join(heads) or text in details, (w, n, multi, text, heads)
        assert vm == original

# 52 列空闲：示意的三行
screen = Screen(24, 52)
B.draw(screen, fixture('empty', True)[0], {'sel': 0})
assert row(screen, 0).startswith(' drover ▸ demo-shop 1/3 ') and row(screen, 0).endswith('Manual · loop off')
assert row(screen, 1) == ' ○ Queue empty'
assert row(screen, 2) == ' HEAD a1f3c2 · corral connected (synthetic)'
single = Screen(24, 52)
B.draw(single, fixture('empty')[0], {'sel': 0})
assert row(single, 0).startswith(' drover ▸ demo-shop ') and '1/' not in row(single, 0)
assert not any(t == 'Status' for _, _, t, _ in single.rows), '全放得下就不重复'

# 配色：256 色、基础色、无色。只有状态词着色，灰点号，蓝箭头，没有反色和黄条
for n in (256, 8, 0):
    colors(n)
    for multi in (False, True):
        vm, _ = fixture('alert', multi)
        screen = Screen(24, 80)
        B.draw(screen, vm, {'sel': 0})
        head = [(t, a) for y, _, t, a in sorted(screen.rows) if y == 0]
        assert head[0] == ('drover', B.COLORS['h1'])
        chip = multi and n == 256
        assert ('▸', B.COLORS.get('rail_mark' if chip else 'accent', 0)) in head
        assert any(t.lstrip().startswith('demo-shop') and a == B.COLORS.get('chip' if chip else '', 0) for t, a in head)
        for text, kind in (('! Needs you 3' if multi else '! Needs you 1', 'wait'), ('corral unavailable', 'bad'),
                           ('Paused', 'wait'), ('loop on', 'ok'), (' · ', 'line')):
            assert (text, B.COLORS.get(kind, 0)) in head, (n, text)
        assert all(not a & curses.A_REVERSE for y, _, _, a in screen.rows if y < 3)
        assert all(a != B.COLORS['sel'] for y, _, _, a in screen.rows if y < 3)
        assert (' ○ No active task', B.COLORS.get('accent', 0)) == (row(screen, 1), [a for y, _, _, a in screen.rows if y == 1][0])
    vm, _ = fixture('working')
    screen = Screen(24, 80)
    B.draw(screen, vm, {})
    assert ('Manual', B.COLORS.get('accent', 0)) in [(t, a) for y, _, t, a in screen.rows if y == 0]
    assert ('loop off', B.COLORS.get('dim', 0)) in [(t, a) for y, _, t, a in screen.rows if y == 0]
    assert ('▶ In progress', B.COLORS['heading_active']) in [(t, a) for y, _, t, a in screen.rows if y == 1]
    assert any(t.startswith('  T42') and a == B.COLORS['h1'] for y, _, t, a in screen.rows if y == 1)
    assert ('Elapsed 1h12m', B.COLORS.get('dim', 0)) in [(t, a) for y, _, t, a in screen.rows if y == 2]

# 来回缩放：同一 state 过宽、窄、超窄再回来，和新画一帧一致，偏移合法，VM 不变
colors(256)
vm, msg = fixture('long', True)
original = copy.deepcopy(vm)
state = {'sel': 1, 'msg': msg, 'body_mouse': True}
screen = Screen(24, 52)
for h, w in ((24, 52), (32, 120), (24, 20), (10, 40), (24, 99), (24, 52)):
    screen.h, screen.w = h, w
    B.draw(screen, vm, state)
    assert 0 <= state['detail_offset'] <= state['detail_total']
fresh = Screen(24, 52)
B.draw(fresh, vm, {'sel': 1, 'msg': msg, 'body_mouse': True})
assert sorted(fresh.rows) == sorted(screen.rows)
assert row(screen, 0).startswith(' drover ▸ billing-api 2/3')
assert vm == original
print('PASS 窄面板 header：三行排版、去重、优先级、完整原文可达、配色与缩放')
