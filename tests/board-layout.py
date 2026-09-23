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


# 普通派发回执只有底部完整放得下时才去重；draw 不得清空原消息。
vm, _ = fixture('working')
card = vm['projects'][0]['queue']['card']
card['title'] = '中A\t完成'
message = '已送给 demo/main：T42 中A\t完成'
screen, state = Screen(32, 120), {'msg': message, 'body_mouse': True}
B.draw(screen, vm, state)
assert not any(t == '操作消息' for _, _, t, _ in screen.rows), '短普通回执在正文重复'
assert [t for y, _, t, _ in screen.rows if y == 31] == [message.replace('\t', '    ')]
assert state['msg'] == message

# 缩小后恢复正文；右下角保留格、中文宽度及 Tab 展开均算入边界。
original = copy.deepcopy(vm)
for w in (120, B.width(message.replace('\t', '    ')) + 2,
          B.width(message.replace('\t', '    ')) + 1, 120):
    screen.w = w
    B.draw(screen, vm, state)
    fits = w >= B.width(message.replace('\t', '    ')) + 2
    assert any(t == '操作消息' for _, _, t, _ in screen.rows) != fits
    footer = ''.join(t for y, _, t, _ in screen.rows if y == 31)
    if fits:
        assert footer == message.replace('\t', '    '), '末行丢尾字'
    assert state['msg'] == message and vm == original

for message in ('已送给 demo/main：T42 中A\t完成（额外说明）',
                '已送给 demo/main：T99 其它任务', '已放行 · ↑ 警告',
                '未放行 · - 拒绝原因', '未知成功消息', '第一行\n完整第二行',
                '未放行 · ' + '长拒绝原因' * 30 + '末尾END'):
    state = {'msg': message, 'body_mouse': True}
    screen = Screen(32, 80)
    seen = []
    while True:
        B.draw(screen, vm, state)
        top = 30 - state['detail_room']
        end = top + state['detail_room'] - (state['detail_total'] > state['detail_room'])
        seen.extend(t for y, _, t, _ in screen.rows if top <= y < end)
        offset = B.key_action(curses.KEY_NPAGE, vm['projects'][0], state)[1]
        if offset == state['detail_offset']:
            break
        state['detail_offset'] = offset
    assert '操作消息' in seen
    assert message.replace('\t', '    ').replace('\n', '') in ''.join(seen)
    assert state['msg'] == message

# 任务标题即使碰巧含警告标记，也保守保留完整消息块。
card['title'] = '警告示例'
state = {'msg': '已送给 demo/main：T42 警告示例'}
B.draw(screen, vm, state)
assert any(t == '操作消息' for _, _, t, _ in screen.rows)

# 换行不折叠空格或合法 Unicode；每行不超列宽、组合字符不被拆到下一行。
for text in ('中文标题' * 15, 'a  b\u00a0c\u2028d' * 12, 'Cafe\u0301' * 20, '/very-long/path/' * 12):
    for cols in (2, 3, 8, 19, 45, 70):
        lines = B.wrap_lines([('', 2, text)], cols)
        assert ''.join(t for _, _, t in lines) == text
        assert all(i + B.width(t) <= cols for _, i, t in lines), (cols, lines)
        assert all(not t.startswith('\u0301') for _, _, t in lines)

# 历史记账独立降低亮度；共用 dim 不变，只有选中项保留反色。
with patch.object(B.curses, 'start_color'), patch.object(B.curses, 'use_default_colors'), \
     patch.object(B.curses, 'init_pair'), patch.object(B.curses, 'color_pair', return_value=0):
    B.init_colors()
assert not B.COLORS['dim'] & curses.A_DIM
assert not B.COLORS['bar'] & curses.A_REVERSE
assert B.COLORS['account'] & curses.A_DIM
assert B.COLORS['key'] & curses.A_BOLD
assert B.COLORS['sel'] & curses.A_REVERSE

# 最终绘制属性：普通/少色/无色均保留层级，理由不被标签里的标点或符号误识别。
def limited_pair(number, *args):
    if number > 4:
        raise curses.error()


for colors in (True, False):
    B.COLORS.clear()
    with patch.object(B.curses, 'start_color', side_effect=None if colors else curses.error), \
         patch.object(B.curses, 'use_default_colors'), \
         patch.object(B.curses, 'init_pair', side_effect=limited_pair), \
         patch.object(B.curses, 'color_pair', side_effect=lambda i: i << 8):
        B.init_colors()
    vm, _ = fixture('working', True)
    q = vm['projects'][0]['queue']
    q['card'].update(body=[], route=None, criteria=[
        {'name': '名称：内含标点', 'ok': False, 'why': '✓ 理由：feature/a\u00a0b\u2028c Cafe\u0301'},
        {'name': '通过', 'ok': True, 'why': '成功理由'},
        {'name': '不适用', 'ok': None, 'why': '未配置理由'}])
    screen = Screen(32, 160)
    B.draw(screen, vm, {'body_mouse': True})
    for label, kind in (('✗ 名称：内含标点：', 'bad'), ('✓ 通过：', 'ok'), ('– 不适用：', 'dim')):
        assert any(t == label and a == B.COLORS.get(kind, 0) for _, _, t, a in screen.rows)
    for reason in ('✓ 理由：feature/a\u00a0b\u2028c Cafe\u0301', '成功理由', '未配置理由'):
        assert any(x == 27 and t == reason and a == 0 for _, x, t, a in screen.rows)
    assert all(not a & curses.A_REVERSE for y, _, _, a in screen.rows if y in (0, 30))
    assert any(t == 'g' and a & curses.A_BOLD for y, _, t, a in screen.rows if y == 30)
    assert any(t == ' 核对放行 ' and a == 0 for y, _, t, a in screen.rows if y == 30)
    assert any(t.startswith('▸') and a & curses.A_REVERSE for _, _, t, a in screen.rows)
    assert any(t.startswith('历史 ·') and not a & curses.A_BOLD for _, _, t, a in screen.rows)
    assert any('等放行' in t and a & curses.A_DIM for _, _, t, a in screen.rows)
    assert any(t.startswith('放弃：') and not a & curses.A_DIM for _, _, t, a in screen.rows)
    assert any(t.startswith('已进行') and not a & curses.A_DIM for _, _, t, a in screen.rows)
    assert B.COLORS['h1'] == B.COLORS['h2'] == curses.A_BOLD
    assert B.COLORS['heading_ok'] == (B.COLORS.get('ok', 0) | curses.A_BOLD)
    assert B.COLORS['heading_wait'] == (B.COLORS.get('wait', 0) | curses.A_BOLD)
    assert any(t == '▶ 进行中' and a == B.COLORS['heading_ok'] for _, _, t, a in screen.rows)
    assert any(t.startswith('  T42') and a == curses.A_BOLD for _, _, t, a in screen.rows)
    assert any(t == '任务正文' and a == curses.A_BOLD for _, _, t, a in screen.rows)
    for scene, label, kind in (('waiting', '■ 等你放行', 'heading_wait'),
                               ('idle', '○ 空闲', 'h1')):
        item, _ = fixture(scene)
        small = Screen(24, 80)
        B.draw(small, item, {'body_mouse': True})
        assert any(t.startswith(label) and a == B.COLORS[kind] for _, _, t, a in small.rows)
    compact = Screen(10, 40)
    B.draw(compact, fixture('working')[0], {'body_mouse': True})
    assert any(t == '▶ 进行中' and a == B.COLORS['heading_ok'] for _, _, t, a in compact.rows)

# 历史续行与记账同列，不截断长标题，当前任务继续最突出。
vm, _ = fixture('idle')
q = vm['projects'][0]['queue']
q['crew'], q['todo'] = [], []
q['finished'] = [q['finished'][0]]
q['finished'][0]['title'] = '历史标题' * 15 + 'END'
screen = Screen(32, 40)
B.draw(screen, vm, {})
history = [(x, t) for _, x, t, _ in screen.rows if '历史标题' in t or t.endswith('END')]
assert history[0][0] == 3 and all(x == 5 for x, _ in history[1:])
assert ''.join(t for _, t in history) == '✓ T41 ' + q['finished'][0]['title']
assert any(x == 5 and '等放行' in t for _, x, t, _ in screen.rows)
assert any(t.startswith('○ 空闲') and a & curses.A_BOLD for _, _, t, a in screen.rows)

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
                keys = ''.join(t for y, _, t, _ in screen.rows if y == h - 2)
                assert keys == 'g 核对放行 n 下一件 p 暂停 a 加任务 l 循环 r 刷新 q 退出 ↑↓/jk PgUp/Dn'
            # 真正翻所有页，包含辅助栏溢出。标记不能只存在于未绘制的逻辑行。
            seen = [[], [], []]
            while True:
                # 每栏独立连接实际详情行，跨页时不夹入固定摘要、栏线和页码。
                # T12 理由缩进后，末尾标记可能恰好跨页，仍须逐字可达。
                dividers = sorted({x for _, x, t, _ in screen.rows if t == '│'})
                top = h - (1 if h < 12 else 2) - state['detail_room']
                page = state['detail_room'] - (state['detail_total'] > state['detail_room'])
                for y, x, t, _ in screen.rows:
                    if top <= y < top + page and t != '│':
                        seen[sum(x > divider for divider in dividers)].append(t)
                # 布局遍历也进入正文局部视口；输入分发/步长另由 T8 回归守住。
                if state.get('body_rect') and state['body_offset'] < state['body_total'] - state['body_page']:
                    state['body_offset'] += 1
                    B.draw(screen, vm, state)
                    continue
                if state.get('history_rect') and state['history_offset'] < state['history_total'] - state['history_page']:
                    state['history_offset'] += 1
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
                text = '\n'.join(''.join(column) for column in seen)
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
