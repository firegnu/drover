#!/usr/bin/env python3
"""真实 PTY/curses + 合成 SGR 滚轮字节；不代表真实鼠标/触控板验收。"""
import argparse
import copy
import curses
import fcntl
import json
import os
from pathlib import Path
import runpy
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

sys.dont_write_bytecode = True
DEMO = Path(__file__).with_name('board-demo.py')


def child(screen, channel, multi):
    demo = runpy.run_path(str(DEMO))
    board = demo['load_board']()
    vm, _ = demo['fixture']('working', multi)
    for pv in vm['projects']:
        pv['queue']['card']['body'] = [f'BODY-{i:02d}' for i in range(1, 39)]
    original = copy.deepcopy(vm)
    counts = {'collect': 0, 'view_model': 0}

    def collect(_):
        counts['collect'] += 1
        return ['synthetic']

    def model(_):
        counts['view_model'] += 1
        return vm

    def forbidden(*args, **kwargs):
        raise AssertionError('滚轮/翻页不得触发业务命令或真实采集')

    board.collect, board.view_model = collect, model
    board.run_drover = board.edit_queue = board.git = board.corral = forbidden
    with os.fdopen(channel, 'w') as output:
        class Recording:
            def __getattr__(self, name): return getattr(screen, name)

            def getch(self):
                h, w = screen.getmaxyx()
                output.write(json.dumps({'size': [w, h], 'counts': counts,
                                         'lines': [screen.instr(y, 0).decode('utf-8') for y in range(h)]},
                                        ensure_ascii=False) + '\n')
                output.flush()
                return screen.getch()

        board.tui(Recording(), 'unused')
    assert vm == original, '真实 tui 不得修改 VM/正文'


def session(root, w, h, multi):
    label = f'{w}x{h}-{"multi" if multi else "single"}'
    master, slave = os.openpty()
    receive, send = os.pipe()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', h, w, 0, 0))
    command = [sys.executable, '-B', __file__, '--child', str(send)] + (['--multi'] if multi else [])
    frames, ansi, pending = [], bytearray(), bytearray()
    with (root / f'{label}.stderr').open('wb') as errors:
        proc = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=errors, pass_fds=(send,),
                                env={**os.environ, 'TERM': 'xterm-256color', 'LC_ALL': 'en_US.UTF-8'})
        os.close(slave)
        os.close(send)

        def frame(data=None):
            if data:
                os.write(master, data)
            deadline = time.monotonic() + 5
            while b'\n' not in pending:
                assert time.monotonic() < deadline, f'{label}: 未收到下一帧，returncode={proc.poll()}'
                for fd in select.select([receive, master], [], [], 0.1)[0]:
                    try:
                        chunk = os.read(fd, 65536)
                    except OSError:
                        chunk = b''
                    if fd == receive:
                        assert chunk, f'{label}: 子进程提前退出，见 stderr'
                        pending.extend(chunk)
                    else:
                        ansi.extend(chunk)
            line, _, rest = pending.partition(b'\n')
            pending[:] = rest
            result = json.loads(line)
            frames.append(result)
            return result

        def wheel(x, y, down=True):
            return f'\x1b[<{65 if down else 64};{x + 1};{y + 1}M'.encode()

        def body_rows(f):
            return [y for y, text in enumerate(f['lines']) if 'BODY-' in text]

        try:
            first = current = frame()
            capable = not any('滚轮不可用' in text for text in current['lines'])
            if capable:
                if h >= 24:
                    assert len(body_rows(current)) == (6 if h == 24 else 8), label
                    assert any('完成依据和判据' in text for text in current['lines']), label
                    assert any('收尾记号' in text for text in current['lines']), label
                for _ in range(30):
                    if body_rows(current):
                        break
                    current = frame(b'\x1b[6~')
                rows = body_rows(current)
                assert rows, label
                y = rows[0]
                x = current['lines'][y].index('BODY-')
                before = current
                current = frame(wheel(x, y))
                expected = f'BODY-{1 + min(3, len(rows)):02d}'
                assert expected in current['lines'][y], (label, 'SGR 下滚方向/步长', expected, current)
                assert current['counts'] == before['counts'], '真实鼠标输入重新采集'
                current = frame(wheel(x, y, False))
                assert current == before, '真实 SGR 上滚未恢复原最终画面'
                # 区域外滚轮由 curses 解码，但不会切项目、重采集或移动任何区域。
                current = frame(wheel(0, 0))
                assert current == before
                seen = set()
                for _ in range(40):
                    for row in body_rows(current):
                        text = current['lines'][row]
                        at = text.index('BODY-')
                        seen.add(text[at:at + 7])
                    previous = current
                    current = frame(wheel(x, y))
                    assert current['counts'] == before['counts'], '滚到末尾期间重新采集'
                    # 标准双栏：正文以外及辅栏完整保持；空白边距不参与语义查找。
                    for row in range(h):
                        if row < rows[0] or row > rows[-1] + 1:
                            assert current['lines'][row] == before['lines'][row], (label, row)
                        if w == 120 and not multi and '│' in current['lines'][row]:
                            assert current['lines'][row].split('│', 1)[1] == before['lines'][row].split('│', 1)[1]
                    if current == previous:
                        break
                assert seen == {f'BODY-{i:02d}' for i in range(1, 39)}, (label, seen)
                assert any('BODY-38' in text for text in current['lines']), label
                previous = current
                current = frame(b'r')
                assert current['lines'] == previous['lines'], '同任务刷新跳回正文开头'
                assert current['counts'] == {k: v + 1 for k, v in previous['counts'].items()}
                if multi:
                    current = frame(b'jj')
                    current = frame()  # 第二个等长、无 waits 的项目
                    assert any('BODY-01' in text for text in current['lines']), '切等长项目未归零'
                    assert current['counts'] == {k: v + 1 for k, v in before['counts'].items()}
                # 真 SIGWINCH / KEY_RESIZE，再检查新尺寸中的坐标与滚轮仍不采集。
                nh, nw = (24, 80) if h != 24 else (32, 120)
                fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', nh, nw, 0, 0))
                os.kill(proc.pid, signal.SIGWINCH)
                current = frame()
                assert current['size'] == [nw, nh], (label, current['size'])
                if body_rows(current):
                    row = body_rows(current)[0]
                    col = current['lines'][row].index('BODY-')
                    previous = current
                    current = frame(wheel(col, row, False))
                    assert current['counts'] == previous['counts'], '缩放后滚轮重新采集'
            else:
                # 在本机默认 Python 的真实 curses 上验证能力退化也能完整翻到末尾。
                seen = []
                for _ in range(80):
                    seen.extend(current['lines'])
                    previous = current
                    current = frame(b'\x1b[6~')
                    assert current['counts'] == first['counts']
                    if current == previous:
                        break
                assert any('BODY-38' in text for text in seen), label
            os.write(master, b'q')
            # resize 可能排入额外 KEY_RESIZE；退出前持续排空两个管道，不能让录屏阻塞子进程。
            deadline = time.monotonic() + 5
            while proc.poll() is None and time.monotonic() < deadline:
                for fd in select.select([receive, master], [], [], 0.1)[0]:
                    try:
                        data = os.read(fd, 65536)
                    except OSError:
                        data = b''
                    (pending if fd == receive else ansi).extend(data)
            assert proc.wait(timeout=5) == 0, label
            print('PASS', label, '真实 curses + SGR 滚轮' if capable else '滚轮能力不足：真实 curses 完整翻页退化', flush=True)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)
            os.close(receive)
            (root / f'{label}.json').write_text(json.dumps(frames, ensure_ascii=False, indent=2))
            (root / f'{label}.ansi').write_bytes(ansi)


def run(root):
    root.mkdir(parents=True, exist_ok=True)
    for w, h in ((120, 32), (80, 24), (40, 10), (160, 32)):
        for multi in (False, True):
            session(root, w, h, multi)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--child', type=int)
    parser.add_argument('--multi', action='store_true')
    parser.add_argument('--record', type=Path)
    args = parser.parse_args()
    if args.child is not None:
        curses.wrapper(child, args.child, args.multi)
    elif args.record:
        run(args.record)
    else:
        with tempfile.TemporaryDirectory(prefix='drover-body-pty-') as directory:
            run(Path(directory))
