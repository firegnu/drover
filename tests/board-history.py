#!/usr/bin/env python3
"""T13: real tasks.state/Git → task_view/VM, then history interaction."""
import copy
from contextlib import ExitStack
import curses
import json
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

D = runpy.run_path(str(Path(__file__).with_name('board-demo.py')))
B = D['load_board']()


class HistoryFixture:
    def __init__(self, root, count=16):
        self.repo = Path(root)
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Synthetic history')
        self.git('config', 'user.email', 'history@example.invalid')
        self.tree = self.git('mktree', input='')
        self.shas = [self.commit('root')]
        for i in range(count):
            self.shas.append(self.commit(f'linear-{i}', self.shas[-1]))
        self.git('update-ref', 'refs/heads/main', self.shas[-1])
        self.handoff = self.repo / 'handoff'
        self.handoff.mkdir()
        self.files = self.repo / 'task-files'
        self.files.mkdir()
        for i in range(1, count + 1):
            (self.files / f'history-{i:03d}.md').write_text('路由：常规 / 交叉审查不要\n')
        self.conf = {'HANDOFF_DIR': str(self.handoff), 'TASK_FILE_DIR': 'task-files'}
        self.p = {'repo': str(self.repo), 'dir': str(self.handoff), 'head': self.shas[-1]}

    def git(self, *args, input=None):
        return subprocess.run(['git', '-C', str(self.repo), *args], input=input, text=True,
                              capture_output=True, check=True).stdout.strip()

    def commit(self, name, *parents):
        return self.git('commit-tree', self.tree, *[s for p in parents for s in ('-p', p)], '-m', name)

    def write(self, count=12, mixed=True, active=None, ranges=None):
        events = []
        ranges = ranges if ranges is not None else list(zip(self.shas, self.shas[1:]))[:count]
        for i, (a, b) in enumerate(ranges, 1):
            title = f'history-{i:03d}'
            body = f'任务文件：task-files/{title}.md'
            if mixed and i == 1:
                title += ' 中文\t长标题\u00a0' * 24 + 'TITLE-END'
            events.append(dict(ev='start', id=f'T{i}', key=f'T{i}', title=title, body=body, sha=a, t=1000+i*100))
            if mixed and i in (2, 6, 10):
                events.append(dict(ev='drop', id=f'T{i}', reason='中文\t完整放弃原因' * 35 + 'REASON-END', t=1040+i*100))
            else:
                events.extend([dict(ev='done', id=f'T{i}', sha=b, gate=True, t=1040+i*100),
                               dict(ev='go', id=f'T{i}', t=1060+i*100)])
        if active:
            events.append(dict(ev='start', id='T999', title='当前任务', body='\n'.join(
                f'BODY-{i:02d}' for i in range(1, 39)), sha=self.shas[0], t=99999))
            if active == 'awaiting':
                events.append(dict(ev='done', id='T999', sha=self.shas[1], gate=True, t=100000))
        (self.handoff / 'tasks.state').write_text(''.join(json.dumps(e, ensure_ascii=False)+'\n' for e in events))
        (self.handoff / 'queue.md').write_text('## T1000 pending\n\n合成待办\n')

    def view(self):
        return B.task_view(str(self.repo), self.conf, self.p)

    def vm(self, multi=False):
        vm, _ = D['fixture']('idle', multi)
        queue = B.queue_vm(self.p, self.view())
        for pv in vm['projects']:
            pv['queue'] = copy.deepcopy(queue)
            pv['waits'] = []
        return vm


class HistoryData(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='drover-history-data-')
        cls.fixture = HistoryFixture(cls.temp.name)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_full_history_from_events_and_vm(self):
        f = self.fixture
        for active in (None, 'doing', 'awaiting'):
            with self.subTest(active=active):
                f.write(active=active)
                original = [(f.handoff / n).read_bytes() for n in ('tasks.state', 'queue.md')]
                tv = f.view()
                before = copy.deepcopy(tv)
                q = B.queue_vm(f.p, tv)
                self.assertEqual(q['counts'], dict(todo=1, doing=int(active == 'doing'),
                                                  done=9+int(active == 'awaiting'), dropped=3))
                self.assertEqual([x['id'] for x in q['finished']],
                                 ['T12', 'T11', 'T10', 'T9', 'T8', 'T7', 'T6', 'T5', 'T4', 'T3', 'T2', 'T1'])
                self.assertEqual(tv, before)
                self.assertEqual([(f.handoff / n).read_bytes() for n in ('tasks.state', 'queue.md')], original)
                self.assertTrue(q['finished'][-1]['title'].endswith('TITLE-END'))
                self.assertTrue(q['finished'][-2]['reason'].endswith('REASON-END'))

    def test_five_valid_ranges_use_one_git_query(self):
        self.fixture.write(count=5, mixed=False)
        with patch.object(B.subprocess, 'run', wraps=B.subprocess.run) as queries:
            tv = self.fixture.view()
        self.assertEqual([r['commits'] for r in tv['finished']], [1] * 5)
        self.assertEqual(queries.call_count, 1, '一次历史刷新不得逐条启动 Git')

    def test_event_order_is_not_numeric_id_order(self):
        f = self.fixture
        f.write()
        ids = ['T80', 'T2', 'T90', 'T17', 'T5', 'T44', 'T3', 'T60', 'T9', 'T1', 'T31', 'T12']
        events = B.task_events((f.handoff / 'tasks.state').read_text())
        for e in events:
            e['id'] = ids[int(e['id'][1:]) - 1]
        (f.handoff / 'tasks.state').write_text(''.join(json.dumps(e)+'\n' for e in events))
        self.assertEqual([r['id'] for r in f.view()['finished']],
                         ['T12', 'T31', 'T1', 'T9', 'T60', 'T3', 'T44', 'T5', 'T17', 'T90', 'T2', 'T80'])

    def test_failed_batch_with_partial_output_uses_original_counts(self):
        f = self.fixture
        f.write(mixed=False, ranges=[(f.shas[0], sha) for sha in f.shas[1:6]])
        original = B.subprocess.run

        def run(args, **kwargs):
            if '--parents' in args:
                return subprocess.CompletedProcess(args, 128, '\n'.join(f.shas[:6]), 'fatal: broken object')
            return original(args, **kwargs)

        with patch.object(B.subprocess, 'run', side_effect=run):
            self.assertEqual([r['commits'] for r in f.view()['finished']], [5, 4, 3, 2, 1],
                             '批量失败即使有部分 stdout，也必须保持原逐条结果')

    def test_counts_match_original_ranges_and_rewritten_history(self):
        f = self.fixture
        root, left = f.shas[:2]
        right = f.commit('right', root)
        merge = f.commit('merge', left, right)
        tip = f.commit('tip', merge)
        orphan = f.commit('unrelated')
        ranges = [(root, merge), (left, right), (right, tip), (tip, left), (orphan, tip),
                  ('', tip), (tip, ''), (tip, tip), ('f' * 40, tip),
                  (root, 'e' * 40), (root, 'main'), (root, tip)]

        def compare():
            f.write(mixed=False, ranges=ranges)
            expected = {f'T{i}': len(B.task_commits(str(f.repo), a, b)) for i, (a, b) in enumerate(ranges, 1)}
            self.assertEqual({r['id']: r['commits'] for r in f.view()['finished']}, expected)

        compare()
        # Replacing a recorded SHA must affect the next refresh; no stale graph/count cache.
        f.git('replace', tip, right)
        try:
            compare()
            f.git('update-ref', 'refs/heads/main', orphan)
            compare()
        finally:
            f.git('replace', '-d', tip)
            f.git('update-ref', 'refs/heads/main', f.shas[-1])
        # Exercise the fast path with a branching graph, independently of fallback-only endpoints.
        ranges = [(root, merge), (left, right), (right, tip), (tip, left), (orphan, tip)]
        compare()
        valid = ranges[:]
        ranges += [(root, 'e' * 40)]
        compare()  # A bad full SHA must not poison otherwise valid records in the same batch.
        ranges = valid
        original = B.subprocess.run
        def unavailable(args, **kwargs):
            if '--parents' in args:
                raise subprocess.TimeoutExpired(args, 30)
            return original(args, **kwargs)
        with patch.object(B.subprocess, 'run', side_effect=unavailable):
            compare()  # Batch failure falls back to the existing results, not zero for every record.
        f.git('replace', tip, right)
        try:
            compare()
        finally:
            f.git('replace', '-d', tip)


S = runpy.run_path(str(Path(__file__).with_name('board-body-scroll.py')))
Screen = S['Screen']


class HistoryScroll(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='drover-history-scroll-')
        cls.fixture = HistoryFixture(cls.temp.name)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.fixture.write()
        self.vm = self.fixture.vm()
        self.screen = Screen(32, 120)
        self.state = {'sel': 0, 'n': 1, 'body_mouse': True}
        self.up, self.down = 1 << 19, 1 << 25
        for name, value in (('BUTTON4_PRESSED', self.up), ('BUTTON5_PRESSED', self.down)):
            p = patch.object(B.curses, name, value, create=True)
            p.start()
            self.addCleanup(p.stop)

    def test_wheel_over_real_history_moves_only_history(self):
        B.draw(self.screen, self.vm, self.state)
        y = next(y for y, line in enumerate(self.screen.lines()) if 'T12 history-012' in line)
        action = B.key_action(curses.KEY_MOUSE, self.vm['projects'][0], self.state, (0, 3, y, 0, self.down))
        self.assertEqual(action, ('history_scroll', 3), '历史行滚轮必须只移动历史')

    def test_new_history_preserves_record_and_local_row(self):
        B.draw(self.screen, self.vm, self.state)
        self.state['history_offset'] = 8
        B.draw(self.screen, self.vm, self.state)
        old = self.screen.lines()[self.state['history_rect'][1]]
        self.fixture.write(count=13)
        fresh = self.fixture.vm()
        B.draw(self.screen, fresh, self.state)
        self.assertEqual(self.state['history_offset'], 10, '新增两行后应保住旧任务内的阅读位置')
        self.assertEqual(self.screen.lines()[self.state['history_rect'][1]], old)

    def wheel(self, region='history', down=True, point=None, buttons=None):
        rect = self.state[region + '_rect']
        x, y = point if point is not None else rect[:2]
        state, vm = copy.deepcopy(self.state), copy.deepcopy(self.vm)
        action = B.key_action(curses.KEY_MOUSE, self.vm['projects'][self.state['sel']], self.state,
                              (0, x, y, 0, buttons if buttons is not None else self.down if down else self.up))
        self.assertEqual(self.state, state, '输入映射必须保持纯函数')
        self.assertEqual(self.vm, vm)
        return action

    def draw(self):
        B.draw(self.screen, self.vm, self.state)

    def find_history(self):
        self.draw()
        for _ in range(100):
            if self.state['history_rect']:
                return
            action = B.key_action(curses.KEY_NPAGE, self.vm['projects'][self.state['sel']], self.state)
            self.assertNotEqual(action[1], self.state['detail_offset'], '外层翻页必须能到达历史入口')
            self.state['detail_offset'] = action[1]
            self.draw()
        self.fail('历史入口不可达')

    def history_rows(self):
        rect = self.state['history_rect']
        width = rect[2] - rect[0]
        return B.wrap_lines([line for f in self.vm['projects'][self.state['sel']]['queue']['finished']
                             for line in B.history_lines(f, True)], width)

    def test_all_wrapped_rows_reachable_without_moving_other_pixels(self):
        for w, h in ((120, 32), (80, 24), (40, 10), (160, 32)):
            for multi in (False, True):
                for active in (None, 'doing'):
                    with self.subTest(size=(w, h), multi=multi, active=active):
                        self.fixture.write(active=active)
                        self.vm = self.fixture.vm(multi)
                        original = copy.deepcopy(self.vm)
                        self.screen = Screen(h, w)
                        self.state = {'sel': 0, 'n': len(self.vm['projects']), 'body_mouse': True}
                        self.find_history()
                        rows = self.history_rows()
                        self.assertEqual(self.state['history_total'], len(rows))
                        x0, y0, x1, y1 = self.state['history_rect']
                        outside = copy.deepcopy(self.screen.rows)
                        outer = self.state['detail_offset']
                        seen = set()
                        for _ in range(len(rows) + 1):
                            off, page = self.state['history_offset'], self.state['history_page']
                            for y, (_, indent, text) in enumerate(rows[off:off + page], y0):
                                self.assertEqual(''.join(self.screen.rows[y][x0:x1]).rstrip(),
                                                 (' ' * indent + text).rstrip(), (w, h, multi, y, off))
                            seen.update(range(off, off + page))
                            action = self.wheel()
                            if action[1] == off:
                                break
                            self.state['history_offset'] = action[1]
                            self.draw()
                            self.assertEqual(self.state['detail_offset'], outer)
                            for y in range(h):
                                if y0 <= y <= y1:  # 内容及位置提示允许改变，本栏以外保持原像素。
                                    self.assertEqual(self.screen.rows[y][:x0], outside[y][:x0])
                                    self.assertEqual(self.screen.rows[y][x1:], outside[y][x1:])
                                else:
                                    self.assertEqual(self.screen.rows[y], outside[y])
                        self.assertEqual(seen, set(range(len(rows))), '最早记录、长标题及完整原因每一显示行均可达')
                        self.assertEqual(self.state['history_offset'], len(rows) - self.state['history_page'])
                        for _ in range(len(rows) + 1):
                            action = self.wheel(down=False)
                            self.state['history_offset'] = action[1]
                            self.draw()
                            if action[1] == 0:
                                break
                        self.assertEqual(self.state['history_offset'], 0)
                        self.assertEqual(self.vm, original)

    def test_visible_hit_rect_clipping_offscreen_and_nonwheel(self):
        for w, h in ((80, 24), (120, 32), (40, 10), (20, 6)):
            self.fixture.write(active='doing')
            self.vm, self.screen = self.fixture.vm(), Screen(h, w)
            self.vm['projects'][0]['queue']['todo'][0]['title'] = '待办长标题' * 120
            self.state = {'sel': 0, 'body_mouse': True, 'msg': '长警告原因' * 30}
            self.draw()
            visible, absent, pages = False, False, set()
            for outer in range(self.state['detail_total'] + 1):
                self.state['detail_offset'] = outer
                self.state['history_offset'] = 0
                self.state.pop('history_anchor', None)
                self.draw()
                rect = self.state['history_rect']
                if not rect:
                    absent = True
                    self.assertIsNone(self.wheel(point=(0, 0)))
                    continue
                visible = True
                x0, y0, x1, y1 = rect
                pages.add(y1 - y0)
                for x, y in ((x0, y0), (x1 - 1, y0), (x0, y1 - 1), (x1 - 1, y1 - 1)):
                    self.assertEqual(self.wheel(point=(x, y)), ('history_scroll', min(3, y1-y0)))
                for point in ((x0-1, y0), (x1, y0), (x0, y0-1), (x0, y1), (0, 0)):
                    action = self.wheel(point=point)
                    self.assertTrue(action is None or action[0] == 'body_scroll', (point, rect, action))
                for buttons in (0, curses.BUTTON1_CLICKED, curses.REPORT_MOUSE_POSITION,
                                self.up | self.down, self.down | curses.BUTTON1_PRESSED):
                    self.assertIsNone(self.wheel(buttons=buttons))
                self.assertLessEqual(y1, h-2)
            self.assertTrue(visible)
            self.assertTrue(absent)
            if max(pages) > 1:
                self.assertGreater(len(pages), 1, '进入历史时应覆盖当帧部分裁切')

    def test_top_refresh_identity_shrink_delete_and_resize(self):
        self.draw()
        self.fixture.write(count=13)
        self.vm = self.fixture.vm(True)
        self.draw()
        self.assertEqual(self.state['history_offset'], 0, '顶部跟随新增记录')
        self.assertIn('T13', self.screen.lines()[self.state['history_rect'][1]])
        self.state['history_offset'] = 8
        self.draw()
        before = copy.deepcopy(self.state)
        self.vm = copy.deepcopy(self.vm)
        self.draw()
        self.assertEqual(self.state, before, '同项目刷新保留阅读位置')
        for identity in ('select', 'reorder'):
            self.state['history_offset'] = 8
            self.draw()
            if identity == 'select':
                self.state['sel'] = 2
            else:
                self.vm['projects'][2], self.vm['projects'][0] = self.vm['projects'][0], self.vm['projects'][2]
            self.draw()
            self.assertEqual(self.state['history_offset'], 0, '等长历史切项目也必须归零')
        self.fixture.write(count=16, mixed=False)
        self.vm, self.screen = self.fixture.vm(), Screen(24, 80)
        for old in (3, 18):
            self.state = {'sel': 0, 'body_mouse': True}
            self.draw()
            self.state['history_offset'] = old
            self.draw()
            shorter = copy.deepcopy(self.vm)
            shorter['projects'][0]['queue']['finished'] = shorter['projects'][0]['queue']['finished'][:12]
            B.draw(self.screen, shorter, self.state)
            expected = min(old, self.state['history_total'] - self.state['history_page'])
            self.assertGreater(expected, 0)
            self.assertEqual(self.state['history_offset'], expected, '仍溢出的短列表保留合法偏移或夹到非零末页')
        self.fixture.write()
        self.vm = self.fixture.vm()
        self.state = {'sel': 0, 'body_mouse': True}
        self.draw()
        self.state['history_offset'] = 8
        self.draw()
        tid, local, _ = self.state['history_anchor']
        for w, h in ((120, 32), (40, 10), (80, 24)):
            self.screen.w, self.screen.h = w, h
            self.find_history()
            self.assertEqual(self.state['history_anchor'][:2], (tid, local), '重排保住记录及合法局部行')
            self.assertLessEqual(self.state['history_offset'], self.state['history_total'] - self.state['history_page'])
        old = self.state['history_offset']
        q = self.vm['projects'][0]['queue']
        q['finished'] = [f for f in q['finished'] if f['id'] != tid]
        self.draw()
        self.assertEqual(self.state['history_offset'], min(old, self.state['history_total'] - self.state['history_page']))

    def test_empty_short_and_no_mouse_use_complete_outer_paging(self):
        for count in (0, 1, 3):
            self.fixture.write(count=count, mixed=False)
            self.vm = self.fixture.vm()
            self.state = {'sel': 0, 'body_mouse': True}
            self.draw()
            if not count:
                self.assertIsNone(self.state['history_rect'])
                self.assertNotIn('history_anchor', self.state)
                self.assertTrue(any('还没有' in line for line in self.screen.lines()))
            else:
                self.assertEqual(self.state['history_total'], 2 * count)
                self.assertEqual(self.state['history_page'], 2 * count)
                self.assertEqual(self.wheel(), ('history_scroll', 0))
        self.fixture.write()
        self.vm, self.screen = self.fixture.vm(), Screen(24, 80)
        self.state = {'sel': 0, 'body_mouse': False}
        seen = []
        for _ in range(200):
            self.draw()
            self.assertIsNone(self.state['history_rect'])
            seen.extend(line.strip() for line in self.screen.lines()[4:21])
            act = B.key_action(curses.KEY_NPAGE, self.vm['projects'][0], self.state)
            if act[1] == self.state['detail_offset']:
                break
            self.state['detail_offset'] = act[1]
        self.assertIn('TITLE-END', ''.join(seen))
        self.assertIn('REASON-END', ''.join(seen))
        self.assertEqual(B.key_action(ord('q'), self.vm['projects'][0], self.state), ('quit',))

    def test_real_tui_alternates_regions_without_collection_commands_or_writes(self):
        self.fixture.write(active='doing')
        vm = self.fixture.vm()
        frames, states = [], []
        original = B.draw

        def draw(screen, model, state):
            original(screen, model, state)
            states.append(copy.deepcopy(state))

        class Input(Screen):
            def getch(inner):
                frames.append(copy.deepcopy(inner.rows))
                return curses.KEY_MOUSE if len(frames) <= 4 else ord('q')

        def mouse():
            region = 'history' if len(frames) % 2 else 'body'
            x, y = states[-1][region + '_rect'][:2]
            return (0, x, y, 0, self.down if len(frames) <= 2 else self.up)

        with ExitStack() as stack:
            for name in ('curs_set', 'mouseinterval'):
                stack.enter_context(patch.object(B.curses, name))
            stack.enter_context(patch.object(B, 'init_colors'))
            stack.enter_context(patch.object(B, 'init_mouse', return_value=True))
            stack.enter_context(patch.object(B.curses, 'getmouse', side_effect=mouse))
            stack.enter_context(patch.object(B, 'draw', side_effect=draw))
            collect = stack.enter_context(patch.object(B, 'collect', return_value=[]))
            model = stack.enter_context(patch.object(B, 'view_model', return_value=vm))
            for name in ('run_drover', 'edit_queue', 'git', 'corral'):
                stack.enter_context(patch.object(B, name, side_effect=AssertionError(name)))
            stack.enter_context(patch.object(B.subprocess, 'run', side_effect=AssertionError('滚轮启动命令')))
            for name in ('builtins.open', 'io.open', 'os.open'):
                stack.enter_context(patch(name, side_effect=AssertionError('滚轮文件IO')))
            before = copy.deepcopy(vm)
            B.tui(Input(32, 120), 'unused')
            self.assertEqual(vm, before)
            self.assertEqual(collect.call_count, 1)
            self.assertEqual(model.call_count, 1)
        self.assertEqual([s['history_offset'] for s in states], [0, 3, 3, 0, 0])
        self.assertEqual([s['body_offset'] for s in states], [0, 0, 3, 3, 0])
        self.assertEqual(frames[0], frames[-1])
        for i, region in enumerate(('history', 'body', 'history', 'body')):
            x0, y0, x1, y1 = states[i][region + '_rect']
            for y in range(32):
                for x in range(120):
                    if not (x0 <= x < x1 and y0 <= y <= y1):
                        self.assertEqual(frames[i][y][x], frames[i+1][y][x])

    def test_resize_between_draw_and_history_input_discards_old_coordinates(self):
        states = []
        original = B.draw

        def draw(screen, vm, state):
            original(screen, vm, state)
            states.append(copy.deepcopy(state))

        class Input(Screen):
            def getch(inner):
                if len(states) == 1:
                    inner.w, inner.h = 80, 24
                    return curses.KEY_MOUSE
                return ord('q')

        with ExitStack() as stack:
            stack.enter_context(patch.object(B.curses, 'curs_set'))
            stack.enter_context(patch.object(B, 'init_colors'))
            stack.enter_context(patch.object(B, 'init_mouse', return_value=True))
            stack.enter_context(patch.object(B, 'draw', side_effect=draw))
            stack.enter_context(patch.object(B.curses, 'getmouse', side_effect=lambda:
                (0, *states[0]['history_rect'][:2], 0, self.down)))
            collect = stack.enter_context(patch.object(B, 'collect', return_value=[]))
            model = stack.enter_context(patch.object(B, 'view_model', return_value=self.vm))
            B.tui(Input(32, 120), 'unused')
            self.assertEqual(collect.call_count, 1)
            self.assertEqual(model.call_count, 1)
        self.assertEqual(states[-1]['screen_size'], (24, 80))
        self.assertEqual(states[-1]['history_offset'], 0, '旧坐标不能滚动缩放后的历史')


if __name__ == '__main__':
    unittest.main()
