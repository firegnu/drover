#!/usr/bin/env python3
"""T8：正文局部视口、纯输入和真实 tui 分发（合成边界）。"""
import copy
from contextlib import ExitStack
import curses
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch

D = runpy.run_path(str(Path(__file__).with_name('board-demo.py')))
B = D['load_board']()


class Screen:
    def __init__(self, h=24, w=80):
        self.h, self.w = h, w
        self.erase()

    def getmaxyx(self): return self.h, self.w
    def erase(self): self.rows = [[' '] * self.w for _ in range(self.h)]
    def refresh(self): pass
    def timeout(self, ms): assert ms == 30000

    def addstr(self, y, x, text, attr=0):
        assert 0 <= y < self.h and 0 <= x < self.w
        assert x + B.width(text) <= self.w - (y == self.h - 1)
        for char in text:
            size = B.cell(char)
            if size:
                self.rows[y][x:x + size] = [char] + [''] * (size - 1)
                x += size
            else:
                self.rows[y][x - 1] += char

    def lines(self): return [''.join(row) for row in self.rows]


def fixture(multi=False, count=38):
    vm, _ = D['fixture']('working', multi)
    for pv in vm['projects']:
        pv['queue']['card']['body'] = [f'BODY-{i:02d}' for i in range(1, count + 1)]
    return vm


class BodyScroll(unittest.TestCase):
    def setUp(self):
        self.up, self.down = 1 << 19, 1 << 25
        for name, value in (('BUTTON4_PRESSED', self.up), ('BUTTON5_PRESSED', self.down)):
            patcher = patch.object(B.curses, name, value, create=True)
            patcher.start()
            self.addCleanup(patcher.stop)

    def wheel(self, vm, state, x=None, y=None, buttons=None):
        if x is None:
            x, y = state['body_rect'][:2]
        before, original = copy.deepcopy(state), copy.deepcopy(vm)
        action = B.key_action(curses.KEY_MOUSE, vm['projects'][state.get('sel', 0)], state,
                              (0, x, y, 0, self.down if buttons is None else buttons))
        self.assertEqual(state, before, '每次输入映射都必须保持 state 不变')
        self.assertEqual(vm, original)
        return action

    def test_body_cap_keeps_criteria_on_first_screen(self):
        for h, w, cap in ((24, 80, 6), (32, 120, 8), (32, 160, 8)):
            for multi in (False, True):
                with self.subTest(size=(w, h), multi=multi):
                    vm = fixture(multi)
                    original = copy.deepcopy(vm)
                    screen, state = Screen(h, w), {'sel': 0, 'body_mouse': True}
                    B.draw(screen, vm, state)
                    lines = screen.lines()
                    self.assertTrue(any('Completion checks' in s for s in lines), '长正文把判据挤出了首屏')
                    self.assertTrue(any('Completion marker' in s for s in lines))
                    self.assertEqual(sum('BODY-' in s for s in lines), cap)
                    self.assertTrue(any(f'1–{cap} / 38 lines' in s for s in lines))
                    self.assertEqual(vm, original)

    def test_tui_wheel_only_redraws_body(self):
        vm = fixture()
        original = copy.deepcopy(vm)
        frames = []

        class Input(Screen):
            def getch(self):
                frames.append(self.lines())
                return (curses.KEY_MOUSE, curses.KEY_MOUSE, ord('q'))[len(frames) - 1]

        screen = Input()
        # 边界给出一上一下两种事件；不要求测试宿主有 BUTTON5 常量。
        up, down = 1 << 19, 1 << 25
        with ExitStack() as stack:
            stack.enter_context(patch.object(B.curses, 'BUTTON4_PRESSED', up))
            stack.enter_context(patch.object(B.curses, 'BUTTON5_PRESSED', down, create=True))
            stack.enter_context(patch.object(B.curses, 'mousemask', return_value=(up | down, 0)))
            stack.enter_context(patch.object(B.curses, 'mouseinterval'))
            stack.enter_context(patch.object(B.curses, 'curs_set'))
            stack.enter_context(patch.object(B.curses, 'start_color', side_effect=curses.error))
            stack.enter_context(patch.object(B.curses, 'getmouse', side_effect=[
                (0, 3, 5, 0, down), (0, 3, 5, 0, up)]))
            collect = stack.enter_context(patch.object(B, 'collect', return_value=['synthetic']))
            view_model = stack.enter_context(patch.object(B, 'view_model', return_value=vm))
            for name in ('run_drover', 'edit_queue', 'git', 'corral'):
                stack.enter_context(patch.object(B, name, side_effect=AssertionError(name)))
            stack.enter_context(patch.object(B.subprocess, 'run', side_effect=AssertionError('滚轮启动命令')))
            for name in ('builtins.open', 'io.open', 'os.open'):
                stack.enter_context(patch(name, side_effect=AssertionError('滚轮写文件')))
            B.tui(screen, 'unused')
            self.assertEqual(collect.call_count, 1, '滚轮不得重跑采集')
            self.assertEqual(view_model.call_count, 1, '滚轮不得重建 VM')
        self.assertIn('BODY-04', frames[1][5], '下滚三行必须改变正文视口')
        self.assertEqual(frames[0], frames[2], '上滚回到原正文')
        # body y=5..10 + 提示 y=11，其余每个最终字符/坐标都不变。
        self.assertEqual(frames[0][:5] + frames[0][12:], frames[1][:5] + frames[1][12:])
        self.assertEqual(vm, original)

    def test_hit_bounds_and_paging_use_current_visible_rows(self):
        for h, w in ((24, 80), (32, 120), (32, 160), (10, 40), (6, 20)):
            for multi in (False, True):
                vm, screen = fixture(multi), Screen(h, w)
                state = {'sel': 0, 'body_mouse': True}
                seen_rect, seen_absent, seen_partial = False, False, False
                B.draw(screen, vm, state)
                total = state['detail_total']
                capacity = state['body_page']
                # 逐行外层偏移检查裁切坐标，包含正文完全不在屏幕上的帧。
                for offset in range(total + 1):
                    state['detail_offset'] = offset
                    B.draw(screen, vm, state)
                    rect = state['body_rect']
                    rows = [y for y, line in enumerate(screen.lines()) if 'BODY-' in line]
                    if not rect:
                        seen_absent = True
                        self.assertEqual(rows, [])
                        action = self.wheel(vm, state, 3, min(5, h - 1))
                        history = state.get('history_rect')
                        if history and history[0] <= 3 < history[2] and history[1] <= min(5, h - 1) < history[3]:
                            self.assertEqual(action, ('history_scroll', min(3, history[3] - history[1],
                                                                           state['history_total'] - state['history_page'])))
                        else:
                            self.assertIsNone(action)
                        continue
                    seen_rect = True
                    x0, y0, x1, y1 = rect
                    self.assertEqual(rows, list(range(y0, y1)))
                    seen_partial |= y1 - y0 < capacity
                    for x, y in ((x0, y0), (x1 - 1, y0), (x0, y1 - 1), (x1 - 1, y1 - 1)):
                        self.assertEqual(self.wheel(vm, state, x, y), ('body_scroll', min(3, y1 - y0)))
                    for x, y in ((x0 - 1, y0), (x1, y0), (x0, y0 - 1), (x0, y1), (0, 0)):
                        self.assertIsNone(self.wheel(vm, state, x, y))
                    for buttons in (0, curses.BUTTON1_CLICKED, curses.BUTTON1_PRESSED,
                                    curses.REPORT_MOUSE_POSITION, self.up | self.down,
                                    self.down | curses.BUTTON1_PRESSED):
                        self.assertIsNone(self.wheel(vm, state, buttons=buttons))
                self.assertTrue(seen_rect, (h, w, multi))
                if w == 80 or h < 12:
                    self.assertTrue(seen_absent)
                if h < 12:
                    # 只有一行的局部视口只能整行出现/消失。
                    self.assertEqual(state['body_page'], 1)
                elif w == 80:
                    self.assertTrue(seen_partial)

    def test_tiny_body_scroll_does_not_skip_lines(self):
        vm, screen = fixture(), Screen(6, 20)
        state = {'sel': 0, 'body_mouse': True}
        B.draw(screen, vm, state)
        while not state['body_rect']:
            offset = B.key_action(curses.KEY_NPAGE, vm['projects'][0], state)[1]
            self.assertNotEqual(offset, state['detail_offset'])
            state['detail_offset'] = offset
            B.draw(screen, vm, state)
        seen = set()
        while True:
            seen.update(s.strip() for s in screen.lines() if 'BODY-' in s)
            offset = self.wheel(vm, state)[1]
            if offset == state['body_offset']:
                break
            state['body_offset'] = offset
            B.draw(screen, vm, state)
        self.assertEqual(seen, {f'BODY-{i:02d}' for i in range(1, 39)}, '极小正文视口不能每次跨过未显示的行')

    def test_partially_clipped_body_can_reach_both_ends_by_wheel(self):
        for clipped in ('top', 'bottom'):
            vm, screen = fixture(), Screen()
            state = {'sel': 0, 'body_mouse': True, 'msg': 'm' * 780 if clipped == 'bottom' else ''}
            B.draw(screen, vm, state)
            if clipped == 'top':
                state['detail_offset'] = 3
                B.draw(screen, vm, state)
            rect = state['body_rect']
            self.assertIsNotNone(rect)
            self.assertLess(rect[3] - rect[1], 6)
            self.assertTrue(any('BODY-01' in s for s in screen.lines()), '裁去上部后仍须能从正文开头读起')
            outer = state['detail_offset']
            for _ in range(40):
                state['body_offset'] = self.wheel(vm, state)[1]
                B.draw(screen, vm, state)
            self.assertEqual(state['detail_offset'], outer)
            self.assertTrue(any('BODY-38' in s for s in screen.lines()), '正文只剩部分可见时也能局部滚到末行')

    def test_tui_ignores_nonwheel_errors_and_resize_race(self):
        vm, frames = fixture(True), []

        class Input(Screen):
            def getch(self):
                frames.append(self.lines())
                if len(frames) == 5:
                    self.h, self.w = 32, 120  # 没有先收到 KEY_RESIZE 的坐标竞态
                return curses.KEY_MOUSE if len(frames) <= 5 else ord('q')

        with ExitStack() as stack:
            for name in ('curs_set', 'mouseinterval'):
                stack.enter_context(patch.object(B.curses, name))
            stack.enter_context(patch.object(B.curses, 'start_color', side_effect=curses.error))
            stack.enter_context(patch.object(B.curses, 'mousemask', return_value=(self.up | self.down, 0)))
            stack.enter_context(patch.object(B.curses, 'getmouse', side_effect=[
                (0, 0, 0, 0, self.down), (0, 3, 6, 0, curses.BUTTON1_CLICKED),
                (0, 3, 6, 0, curses.REPORT_MOUSE_POSITION), curses.error(), (0, 3, 6, 0, self.down)]))
            collect = stack.enter_context(patch.object(B, 'collect', return_value=[]))
            model = stack.enter_context(patch.object(B, 'view_model', return_value=vm))
            for name in ('run_drover', 'edit_queue', 'git', 'corral'):
                stack.enter_context(patch.object(B, name, side_effect=AssertionError(name)))
            B.tui(Input(), 'unused')
            self.assertEqual(collect.call_count, 1)
            self.assertEqual(model.call_count, 1)
        self.assertTrue(all(f == frames[0] for f in frames[:5]))
        self.assertTrue(any('BODY-01' in s for s in frames[-1]), '旧坐标事件必须丢弃，不能滚动新尺寸正文')

    def test_scroll_bounds_last_line_and_nonbody_pixels_stay_fixed(self):
        for h, w in ((24, 80), (32, 120), (32, 160)):
            for multi in (False, True):
                vm, screen = fixture(multi), Screen(h, w)
                state = {'sel': 0, 'body_mouse': True}
                B.draw(screen, vm, state)
                rect = state['body_rect']
                x0, y0, x1, y1 = rect
                before = copy.deepcopy(screen.rows)
                outer = {k: state[k] for k in ('detail_offset', 'detail_total', 'detail_room', 'sel')}
                self.assertEqual(self.wheel(vm, state, buttons=self.up), ('body_scroll', 0))
                seen = set()
                for _ in range(20):
                    seen.update(''.join(screen.rows[y][x0:x1]).strip() for y in range(y0, y1))
                    state['body_offset'] = self.wheel(vm, state)[1]
                    B.draw(screen, vm, state)
                    self.assertEqual(state['body_rect'], rect)
                    self.assertEqual({k: state[k] for k in outer}, outer)
                    # 指示行也属正文；其它位置每一格均不得随局部滚动改变。
                    for y in range(h):
                        for x in range(w):
                            if not (x0 <= x < x1 and y0 <= y <= y1):
                                self.assertEqual(screen.rows[y][x], before[y][x], (w, h, multi, x, y))
                self.assertIn('BODY-38', screen.lines()[y1 - 1])
                self.assertEqual(state['body_offset'], 38 - state['body_page'])
                self.assertEqual(self.wheel(vm, state), ('body_scroll', state['body_offset']))
                self.assertEqual(len(seen), 38)

    def test_short_empty_and_body_words_are_not_section_markers(self):
        for count in (0, 1, 3, 6, 38):
            vm, screen = fixture(count=count), Screen()
            if count:
                vm['projects'][0]['queue']['card']['body'][0] = '完成依据和判据 · 用户正文'
            state = {'sel': 0, 'body_mouse': True}
            B.draw(screen, vm, state)
            if not count:
                self.assertIsNone(state['body_rect'])
                self.assertNotIn('body_task', state)
            else:
                self.assertEqual(state['body_page'], min(count, 6))
                self.assertIn('完成依据和判据 · 用户正文', screen.lines()[5])
                self.assertEqual(self.wheel(vm, state), ('body_scroll', 3 if count > 6 else 0))
            # 短正文后只有原有的区间空行，不填六行空白。
            expected_y = 6 + min(count, 6) + int(count > 6)
            self.assertIn('Completion checks · 0/3', screen.lines()[expected_y])

    def test_identity_refresh_shrink_and_resize(self):
        vm, screen = fixture(True), Screen()
        state = {'sel': 0, 'body_mouse': True}
        B.draw(screen, vm, state)
        state['body_offset'] = 30
        B.draw(screen, copy.deepcopy(vm), state)
        self.assertEqual(state['body_offset'], 30, '同任务刷新保留位置')
        for old, expected in ((30, 6), (3, 3)):
            B.draw(screen, vm, state)
            state['body_offset'] = old
            shorter = copy.deepcopy(vm)
            shorter['projects'][0]['queue']['card']['body'] = shorter['projects'][0]['queue']['card']['body'][:12]
            B.draw(screen, shorter, state)
            self.assertEqual(state['body_offset'], expected, '仍溢出时夹到非零末页，合法偏移保留')
        for change in ('task', 'project', 'reorder'):
            state = {'sel': 0, 'body_mouse': True}
            B.draw(screen, vm, state)
            state['body_offset'] = 15
            changed = copy.deepcopy(vm)
            if change == 'task':
                changed['projects'][0]['queue']['card']['id'] = 'T99'
            elif change == 'project':
                state['sel'] = 2
            else:
                changed['projects'][0], changed['projects'][2] = changed['projects'][2], changed['projects'][0]
            B.draw(screen, changed, state)
            self.assertEqual(state['body_offset'], 0, change + ' 等长正文必须归零')
        # 文本从宽屏末页缩窄再放宽，偏移合法且最后一行可见。
        vm = fixture()
        vm['projects'][0]['queue']['card']['body'] = ['中文宽度' * 30] * 12 + ['BODY-END']
        state = {'sel': 0, 'body_mouse': True}
        B.draw(screen, vm, state)
        for h, w in ((32, 120), (24, 80), (10, 40), (32, 120)):
            screen.h, screen.w = h, w
            state['body_offset'] = 9999
            B.draw(screen, vm, state)
            self.assertEqual(state['body_offset'], state['body_total'] - state['body_page'])
            while not state['body_rect']:
                action = B.key_action(curses.KEY_NPAGE, vm['projects'][0], state)
                self.assertNotEqual(action[1], state['detail_offset'])
                state['detail_offset'] = action[1]
                B.draw(screen, vm, state)
            self.assertTrue(any('BODY-END' in s for s in screen.lines()))
            self.assertEqual(state['screen_size'], (h, w))
        for no_card in (None, {}):
            changed = copy.deepcopy(vm)
            changed['projects'][0]['queue']['card'] = no_card
            B.draw(screen, changed, state)
            self.assertIsNone(state['body_rect'])
            self.assertNotIn('body_offset', state)
        B.draw(screen, {**vm, 'projects': []}, state)
        self.assertIsNone(state['body_rect'])

    def test_missing_mouse_capability_preserves_full_paging(self):
        for mask in (0, self.up, self.up | self.down):
            with patch.object(B.curses, 'mousemask', return_value=(mask, 0)), \
                 patch.object(B.curses, 'mouseinterval'):
                self.assertEqual(B.init_mouse(), mask == self.up | self.down)
        with patch.object(B.curses, 'BUTTON5_PRESSED', 0), patch.object(B.curses, 'mousemask') as mask:
            self.assertFalse(B.init_mouse())
            mask.assert_not_called()
        with patch.object(B.curses, 'mousemask', side_effect=curses.error):
            self.assertFalse(B.init_mouse())
        vm, screen = fixture(), Screen()
        state = {'sel': 0, 'body_mouse': False}
        B.draw(screen, vm, state)
        self.assertTrue(any('Mouse wheel unavailable' in s for s in screen.lines()), '能力退化必须明确提示')
        seen = []
        while True:
            seen.extend(screen.lines())
            self.assertIsNone(state['body_rect'])
            action = B.key_action(curses.KEY_NPAGE, vm['projects'][0], state)
            if action[1] == state['detail_offset']:
                break
            state['detail_offset'] = action[1]
            B.draw(screen, vm, state)
        self.assertTrue(any('BODY-38' in s for s in seen), '无双向滚轮也不能丢失正文')
        self.assertEqual(B.key_action(ord('q'), vm['projects'][0], state), ('quit',))


if __name__ == '__main__':
    unittest.main()
