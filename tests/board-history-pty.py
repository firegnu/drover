#!/usr/bin/env python3
"""T13: reuse body PTY transport; real events/Git/VM/curses and synthetic SGR."""
import argparse
from pathlib import Path
import runpy
import tempfile


def check(current, frame, wheel, resize, multi):
    def find_history(current):
        for _ in range(100):
            if current['viewport']['history_rect']:
                return current
            before = current
            current = frame(b'\x1b[6~')
            assert current['counts'] == before['counts'], '外层翻页重新采集'
            assert current != before, '外层翻页无法到达历史'
        raise AssertionError('历史入口不可达')

    def scroll(current, down=True):
        x, y = current['viewport']['history_rect'][:2]
        after = frame(wheel(x, y, down))
        assert after['counts'] == current['counts'], '历史滚轮重新采集'
        assert after['viewport']['detail_offset'] == current['viewport']['detail_offset']
        assert after['viewport'].get('body_offset') == current['viewport'].get('body_offset')
        before = current['viewport']
        expected = min(max(0, before['history_offset'] + (1 if down else -1) * min(3, before['history_page'])),
                       before['history_total'] - before['history_page'])
        assert after['viewport']['history_offset'] == expected, '实际 curses 滚轮方向/步长错误'
        return after

    def ends(current):
        current = find_history(current)
        for _ in range(current['viewport']['history_total'] + 1):
            if current['viewport']['history_offset'] == 0:
                break
            current = scroll(current, False)
        assert current['viewport']['history_offset'] == 0
        lines = {}
        for _ in range(current['viewport']['history_total'] + 1):
            state = current['viewport']
            assert len(current['history_rows']) == state['history_page']
            for i, text in enumerate(current['history_rows'], state['history_offset']):
                if i in lines:
                    assert lines[i] == text, '相同历史行在滚动时内容改变'
                lines[i] = text
            if state['history_offset'] == state['history_total'] - state['history_page']:
                break
            current = scroll(current)
        assert set(lines) == set(range(current['viewport']['history_total'])), '最终屏幕漏历史显示行'
        rendered = ''.join(lines[i].strip(' ') for i in sorted(lines))
        for text in ('T12 history-012', 'T1 history-001', 'TITLE-END', 'REASON-END', '放弃：'):
            assert text in rendered, (current['size'], text, rendered)
        assert '\t' not in rendered, 'Tab 必须通过展示副本展开'
        assert '\u00a0' in rendered, '合法 Unicode 不得压平'
        return current

    assert current['viewport']['body_mouse'], '此入口要求用户已确认的原生双向 curses'
    if current['viewport'].get('body_rect'):
        x, y = current['viewport']['body_rect'][:2]
        before = current
        current = frame(wheel(x, y))
        assert current['counts'] == before['counts']
        assert current['viewport']['history_offset'] == before['viewport']['history_offset']
        assert current['viewport']['body_offset'] > before['viewport']['body_offset']
        current = frame(wheel(x, y, False))
        assert current == before, '正文滚轮未恢复实际画面'
    current = find_history(current)
    before = current
    current = scroll(current)
    current = scroll(current, False)
    assert current == before, '历史双向滚轮未恢复实际画面'
    current = frame(wheel(0, 0))
    assert current == before, '区域外滚轮移动了内容'
    current = ends(current)
    before = current
    current = frame(b'r')
    assert current['lines'] == before['lines'], '刷新改变了历史阅读位置'
    assert current['counts'] == {k: v+1 for k, v in before['counts'].items()}
    for w, h in ((40, 10), (80, 24), (120, 32)):
        current = resize(w, h)
        assert current['size'] == [w, h]
        current = ends(current)
    if multi:
        before = current
        current = frame(b'j')
        assert current['counts'] == before['counts']
        assert current['viewport']['history_offset'] == 0, '等长项目切换未归零'
        current = find_history(current)
        assert any('T12 history-012' in line for line in current['history_rows'])


def run(root):
    root.mkdir(parents=True, exist_ok=True)
    transport = runpy.run_path(str(Path(__file__).with_name('board-body-pty.py')))
    for w, h in ((120, 32), (80, 24), (40, 10), (160, 32)):
        for multi in (False, True):
            for active in (False, True):
                transport['session'](root, w, h, multi, history=True, active=active)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record', type=Path)
    args = parser.parse_args()
    if args.record:
        run(args.record)
    else:
        with tempfile.TemporaryDirectory(prefix='drover-history-pty-') as directory:
            run(Path(directory))
