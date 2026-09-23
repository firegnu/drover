#!/usr/bin/env python3
"""R1：用真实 curses 最终屏幕守住 Tab 正文，不能只检查 addstr 的入参。"""
import copy
import curses
import fcntl
import json
import os
from pathlib import Path
import runpy
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time

sys.dont_write_bytecode = True
DEMO = Path(__file__).with_name('board-demo.py')
COMMAND = 'python3 -m pytest tests/checkout/test_coupon_validation.py --verbose'
UNICODE = 'feature/a\u00a0b\u2028c  Cafe\u0301'


def capture(screen, output):
    demo = runpy.run_path(str(DEMO))
    board = demo['load_board']()
    board.init_colors()
    results = []
    for h, w in ((32, 120), (24, 80)):
        for tabs in (False, True):
            for padding in (0, 36):
                vm, _ = demo['fixture']('working')
                body = ('\t' if tabs else '') + COMMAND
                vm['projects'][0]['queue']['card']['body'] = ['正文占位'] * padding + [body, UNICODE]
                original = copy.deepcopy(vm)
                state = {'sel': 0, 'n': 1, 'msg': '', 'body_mouse': board.init_mouse()}
                win = curses.newwin(h, w, 0, 0)
                frames = []
                while True:
                    board.draw(win, vm, state)
                    win.refresh()
                    # draw 全部画完以后再读取：辅栏/分隔线后写造成的覆盖也在这里。
                    frames.append([win.instr(y, 0).decode('utf-8') for y in range(h)])
                    if state.get('body_rect'):
                        x, y = state['body_rect'][:2]
                        action = board.key_action(curses.KEY_MOUSE, vm['projects'][0], state,
                                                  (0, x, y, 0, curses.BUTTON5_PRESSED))
                        if action[1] != state['body_offset']:
                            state['body_offset'] = action[1]
                            continue
                    offset = board.key_action(curses.KEY_NPAGE, vm['projects'][0], state)[1]
                    if offset == state['detail_offset']:
                        break
                    state['detail_offset'] = offset
                assert vm == original, 'draw/翻页不得改写原 VM 或 Tab/Unicode 正文'
                results.append({'size': [w, h], 'tab': tabs, 'padding': padding,
                                'body_mouse': state['body_mouse'], 'frames': frames})
    # T12：同一消息从完整容纳缩到差一列再放大，检查 curses 最终屏幕而非入参。
    for multi in (False, True):
        vm, _ = demo['fixture']('working', multi)
        vm['projects'][0]['queue']['card']['title'] = '中A\t完成'
        msg = '已送给 demo/main：T42 中A\t完成'
        expected = msg.replace('\t', '    ')
        boundary = board.width(expected) + 2  # 一列左边距 + 右下角保留格
        original = copy.deepcopy(vm)
        state = {'sel': 0, 'msg': msg, 'body_mouse': board.init_mouse()}
        for w in (120, boundary, boundary - 1, 80):
            h = 24
            win = curses.newwin(h, w, 0, 0)
            board.draw(win, vm, state)
            win.refresh()
            frame = [win.instr(y, 0).decode('utf-8') for y in range(h)]
            fits = w >= boundary
            assert ('Operation message' in ''.join(frame)) != fits, (w, multi, frame)
            if fits:
                assert frame[-1].strip(' ') == expected, (w, multi, frame[-1])
                assert sum(expected in line for line in frame) == 1
            assert not win.inch(0, 1) & curses.A_REVERSE
            assert win.inch(h - 2, 1) & curses.A_BOLD
            assert not win.inch(h - 2, 3) & (curses.A_BOLD | curses.A_REVERSE)
            assert state['msg'] == msg and vm == original
            results.append({'message': True, 'size': [w, h], 'multi': multi, 'frames': [frame]})
    output.write_text(json.dumps(results, ensure_ascii=False, indent=2))


def check(output):
    failures = []
    for case in json.loads(output.read_text()):
        if case.get('message'):
            print('PASS', case['size'], 'multi=' + str(case['multi']), '短消息/临界列宽/缩放和顶底栏最终属性')
            continue
        # 在实际画面的主栏内连接换行；仅去掉 ASCII 边距，不折叠 Unicode/内部空格。
        pages = [''.join(line.split('│', 1)[0].strip(' ') for line in frame)
                 for frame in case['frames']]
        label = f"{case['size']} Tab={case['tab']} body_offset={case['padding']} mouse={case['body_mouse']}"
        for text in (COMMAND, UNICODE):
            if not any(text in page for page in pages):
                failures.append(f'{label}: 最终屏幕缺少 {text!r}')
        if case['padding']:
            assert len(pages) > 1, '长正文必须真的经过局部滚动或退化后的 PgDn'
        if not any(label in failure for failure in failures):
            print('PASS', label, '完整命令/Unicode 可见，VM 不变')
    assert not failures, 'R1 最终屏幕回归：\n' + '\n'.join(failures)


def run():
    with tempfile.TemporaryDirectory(prefix='drover-tab-pty-') as directory:
        output = Path(directory) / 'frames.json'
        master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 120, 0, 0))
        try:
            with tempfile.TemporaryFile() as errors:
                proc = subprocess.Popen([sys.executable, '-B', __file__, '--child', str(output)],
                                        stdin=slave, stdout=slave, stderr=errors,
                                        env={**os.environ, 'TERM': 'xterm-256color', 'LC_ALL': 'en_US.UTF-8'})
                os.close(slave)
                slave = None
                try:
                    deadline = time.monotonic() + 15
                    while proc.poll() is None and time.monotonic() < deadline:
                        if select.select([master], [], [], 0.1)[0]:
                            try:
                                os.read(master, 65536)
                            except OSError:
                                break
                    proc.wait(timeout=5)
                finally:
                    if proc.poll() is None:
                        proc.kill()
                        proc.wait()
                errors.seek(0)
                assert proc.returncode == 0, errors.read().decode()
            check(output)
        finally:
            os.close(master)
            if slave is not None:
                os.close(slave)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--child':
        curses.wrapper(capture, Path(sys.argv[2]))
    else:
        run()
