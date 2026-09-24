#!/usr/bin/env python3
"""滚动条的最终画面：位置、首尾、局部独立性和文字不被覆盖。仅合成数据。"""
import copy
import curses
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch

D = runpy.run_path(str(Path(__file__).with_name('board-demo.py')))
S = runpy.run_path(str(Path(__file__).with_name('board-body-scroll.py')))
B, Screen = D['load_board'](), S['Screen']


class PaintedScreen(Screen):
    def erase(self):
        super().erase()
        self.paints = []

    def addstr(self, y, x, text, attr=0):
        self.paints.append((y, x, text, attr))
        super().addstr(y, x, text, attr)


class Scrollbars(unittest.TestCase):
    def test_body_thumb_tracks_position_without_moving_outer_page(self):
        vm, _ = D['fixture']('body')
        vm['projects'][0]['queue']['card']['body'] = [f'BODY-{i:02d}' for i in range(40)]
        original = copy.deepcopy(vm)
        screen, state = Screen(24, 52), {'sel': 0, 'body_mouse': True}
        B.draw(screen, vm, state)
        x0, y0, x1, y1 = state['body_rect']
        track = lambda: ''.join(screen.rows[y][x1 - 2] for y in range(y0, y1))
        self.assertEqual(track(), '┃' + '│' * (y1 - y0 - 1), '正文溢出时应在顶部显示滑块')
        outer = state['detail_offset']
        state['body_offset'] = 17
        B.draw(screen, vm, state)
        self.assertNotEqual(track(), '┃' + '│' * (y1 - y0 - 1))
        self.assertIn('┃', track()[1:-1])
        state['body_offset'] = 999
        B.draw(screen, vm, state)
        self.assertEqual(track(), '│' * (y1 - y0 - 1) + '┃')
        self.assertIn('BODY-39', '\n'.join(screen.lines()))
        self.assertEqual(state['detail_offset'], outer)
        self.assertEqual(vm, original)

    def test_history_thumb_and_complete_rows(self):
        vm, _ = D['fixture']('empty')
        q = vm['projects'][0]['queue']
        q['crew'] = []
        sample = q['finished'][0]
        q['finished'] = [dict(sample, id=f'T{i}', title=f'ROW-{i:02d}', route=None, wait='')
                         for i in range(40)]
        screen, state = Screen(24, 52), {'sel': 0, 'body_mouse': True}
        B.draw(screen, vm, state)
        x0, y0, x1, y1 = state['history_rect']
        track = lambda: ''.join(screen.rows[y][x1 - 2] for y in range(y0, y1))
        self.assertEqual(track(), '┃┃' + '│' * 11, '13 行视口 / 80 行历史应有两格滑块')
        outer = state['detail_offset']
        state['history_offset'] = 999
        B.draw(screen, vm, state)
        self.assertEqual(track(), '│' * 11 + '┃┃')
        self.assertIn('ROW-39', '\n'.join(screen.lines()))
        self.assertEqual(state['detail_offset'], outer)

    def test_outer_scrollbar_tracks_shared_page_and_keeps_header(self):
        for w in (20, 52, 120):
            with self.subTest(width=w):
                vm, _ = D['fixture']('long')
                screen, state = Screen(24, w), {'sel': 0, 'body_mouse': False}
                B.draw(screen, vm, state)
                top = 5 if w >= 100 else 4
                _, page = B.detail_viewport(state['detail_total'], state['detail_room'], 0)
                track = lambda: ''.join(screen.rows[y][w - 1] for y in range(top, top + page))
                header = screen.lines()[:top]
                self.assertTrue(track().startswith('┃'), '整页内容溢出时右侧应有滑块')
                self.assertTrue(track().endswith('│'))
                state['detail_offset'] = 99999
                B.draw(screen, vm, state)
                self.assertTrue(track().startswith('│'))
                self.assertTrue(track().endswith('┃'))
                self.assertEqual(screen.lines()[:top], header)
                self.assertNotIn('┃', ''.join(screen.lines()[-2:]))

    def test_projects_scrollbar_follows_selected_window(self):
        vm, _ = D['fixture']('empty')
        vm['projects'] = [dict(vm['projects'][0], name=f'project-{i}', repo=f'/synthetic/{i}')
                          for i in range(30)]
        screen, state = Screen(24, 120), {'sel': 0, 'n': 30, 'body_mouse': True}
        B.draw(screen, vm, state)
        # 项目栏 19 个可见项 / 30 项，对应 12 格滑块，使用原分隔线位置。
        track = lambda: ''.join(screen.rows[y][21] for y in range(3, 22))
        self.assertEqual(track(), '┃' * 12 + '│' * 7)
        state['sel'] = 29
        B.draw(screen, vm, state)
        self.assertEqual(track(), '│' * 7 + '┃' * 12)
        self.assertIn('▸ project-29', '\n'.join(screen.lines()))
        vm['projects'] = vm['projects'][:3]
        state['sel'] = 0
        B.draw(screen, vm, state)
        self.assertEqual(track(), '│' * 19, '无溢出时还原普通分隔线')

    def test_short_content_has_no_scrollbars(self):
        vm, _ = D['fixture']('working')
        q = vm['projects'][0]['queue']
        q['card'].update(title='Short', body=['short body'], criteria=[])
        q.update(crew=[], todo=[], finished=[])
        screen, state = Screen(32, 120), {'sel': 0, 'body_mouse': True}
        B.draw(screen, vm, state)
        self.assertEqual(state['body_total'], state['body_page'])
        self.assertNotIn('┃', '\n'.join(screen.lines()))
        x0, y0, x1, y1 = state['body_rect']
        self.assertTrue(all(screen.rows[y][x1 - 2] == ' ' for y in range(y0, y1)))

    def test_local_tracks_clip_resize_and_never_cover_text(self):
        vm, _ = D['fixture']('body', True)
        for pv in vm['projects']:
            q = pv['queue']
            q['card']['title'] = 'Short'
            q['card']['body'] = ['正文\tCafé x ' * 8 + '【尾】'] * 12
            q['finished'] = [dict(q['finished'][0], id=f'T{i}', title='历史\tCafé x ' * 8)
                             for i in range(20)]
        original = copy.deepcopy(vm)
        found = set()
        for h, w in ((5, 20), (6, 20), (10, 40), (12, 32), (24, 52), (24, 80), (32, 100), (32, 160)):
            screen, state = PaintedScreen(h, w), {'sel': 0, 'body_mouse': True}
            B.draw(screen, vm, state)
            total = state['detail_total']
            for offset in range(total + 1):
                state['detail_offset'] = offset
                B.draw(screen, vm, state)
                for region in ('body', 'history'):
                    rect = state[region + '_rect']
                    if not rect:
                        continue
                    found.add(region)
                    x0, y0, x1, y1 = rect
                    self.assertNotEqual(x1 - 2, w - 1, '局部条与外层条必须分列')
                    for y, x, text, _ in screen.paints:
                        if y0 <= y < y1 and x0 <= x < x1 - 2:
                            self.assertLessEqual(x + B.width(text), x1 - 2, '位置条覆盖文字')
                    for pos in (0, 99999):
                        state[region + '_offset'] = pos
                        B.draw(screen, vm, state)
                        track = ''.join(screen.rows[y][x1 - 2] for y in range(y0, y1))
                        if state[region + '_total'] > state[region + '_page']:
                            self.assertTrue(set(track) <= {'┃', '│'})
                            self.assertEqual(track[0 if pos == 0 else -1], '┃')
                            found.add('single-row' if y1 - y0 == 1 else 'multi-row')
                    self.assertEqual(state['detail_offset'], min(offset, max(0, total - B.detail_viewport(total, state['detail_room'], 0)[1])))
            self.assertEqual(vm, original)
        self.assertEqual(found, {'body', 'history', 'single-row', 'multi-row'})

    def test_fallback_and_no_color_remain_readable(self):
        vm, _ = D['fixture']('body')
        with patch.dict(B.COLORS, {}, clear=True):
            for mouse in (False, True):
                screen, state = PaintedScreen(24, 52), {'sel': 0, 'body_mouse': mouse}
                B.draw(screen, vm, state)
                self.assertIn('┃', '\n'.join(screen.lines()))
                if not mouse:
                    self.assertIsNone(state['body_rect'])
                    self.assertIsNone(state['history_rect'])
                    self.assertTrue(all(x == 51 for _, x, t, _ in screen.paints if t == '┃'))
                self.assertEqual(B.key_action(ord('q'), vm['projects'][0], state), ('quit',))

    def test_unicode_tab_and_literal_track_characters_remain_complete(self):
        text = '中A\tCafé / feature/a\u00a0b\u2028c │┃  ' * 12 + '【正文末尾】'
        for w in (20, 52, 120):
            vm, _ = D['fixture']('working')
            vm['projects'][0]['queue']['card'].update(title='Short', body=[text])
            original = copy.deepcopy(vm)
            screen, state = PaintedScreen(24, w), {'sel': 0, 'body_mouse': True}
            B.draw(screen, vm, state)
            while not state['body_rect']:
                act = B.key_action(curses.KEY_NPAGE, vm['projects'][0], state)
                self.assertNotEqual(act[1], state['detail_offset'])
                state['detail_offset'] = act[1]
                B.draw(screen, vm, state)
            rows = {}
            while True:
                x0, y0, x1, y1 = state['body_rect']
                for y in range(y0, y1):
                    rows[state['body_offset'] + y - y0] = ''.join(
                        t for py, px, t, _ in sorted(screen.paints)
                        if py == y and x0 <= px < x1 - 2)
                if state['body_offset'] == state['body_total'] - state['body_page']:
                    break
                state['body_offset'] += 1
                B.draw(screen, vm, state)
            self.assertEqual(''.join(rows[i] for i in sorted(rows)), text.replace('\t', '    '))
            self.assertEqual(vm, original)

    def test_track_and_thumb_use_existing_gray_levels(self):
        vm, _ = D['fixture']('body')
        with patch.dict(B.COLORS, {'line': curses.A_DIM, 'dim': curses.A_BOLD}, clear=True):
            screen, state = PaintedScreen(24, 52), {'sel': 0, 'body_mouse': True}
            B.draw(screen, vm, state)
            self.assertTrue(any(t == '┃' and a == curses.A_BOLD for _, _, t, a in screen.paints))
            self.assertTrue(any(t == '│' and a == curses.A_DIM for _, _, t, a in screen.paints))


if __name__ == '__main__':
    unittest.main()
