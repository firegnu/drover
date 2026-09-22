#!/usr/bin/env python3
"""R1 隔离诊断：原始鼠标字节 → 真实 curses 解码；不加载任何 board/agent。

python3 -B tests/board-mouse-decode.py --record /tmp/m17-r1-mouse.json
同一探针可用另一现有解释器作对照。这里只生成测试输入，不实现鼠标协议解析器。
"""
import argparse
import curses
import fcntl
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import termios
import time

EVENTS = {'up': 64, 'down': 65, 'button6': 66, 'button7': 67,
          'left': 0, 'middle': 1, 'move': 35, 'drag': 32}


def child(screen, mask_name, channel):
    masks = {
        'reference': curses.BUTTON1_PRESSED | curses.BUTTON1_CLICKED | curses.BUTTON4_PRESSED
                     | getattr(curses, 'BUTTON5_PRESSED', 0),
        'all': curses.ALL_MOUSE_EVENTS,
        'position': curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION,
    }
    requested = masks[mask_name]
    accepted, _ = curses.mousemask(requested)
    curses.mouseinterval(0)
    screen.timeout(1000)
    screen.refresh()
    with os.fdopen(channel, 'w') as output:
        output.write(json.dumps({'python': sys.executable, 'version': sys.version.split()[0],
                                 'ncurses': list(curses.ncurses_version),
                                 'kmous': repr(curses.tigetstr('kmous')),
                                 'requested': hex(requested), 'accepted': hex(accepted),
                                 'constants': {name: hex(getattr(curses, name)) for name in dir(curses)
                                               if name.startswith('BUTTON') or name == 'REPORT_MOUSE_POSITION'}}) + '\n')
        output.flush()
        events = []
        for _ in range(64):
            key = screen.getch()
            if key == 0:
                break
            assert key != -1, 'PTY 测试输入/终止符未送达'
            if key == curses.KEY_MOUSE:
                try:
                    event = curses.getmouse()
                    events.append({'mouse': list(event), 'bstate': hex(event[-1])})
                except curses.error:
                    events.append({'mouse_error': True})
            else:
                events.append({'key': key, 'name': curses.keyname(key).decode('ascii', 'backslashreplace')})
        else:
            raise AssertionError('没有读到测试终止符')
        output.write(json.dumps({'events': events}) + '\n')
        output.flush()


def sample(mask, protocol, button):
    master, slave = os.openpty()
    receive, send = os.pipe()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
    proc = subprocess.Popen([sys.executable, '-B', __file__, '--child', mask, str(send)],
                            stdin=slave, stdout=slave, stderr=subprocess.PIPE, pass_fds=(send,),
                            env={**os.environ, 'TERM': 'xterm-256color', 'LC_ALL': 'en_US.UTF-8'})
    os.close(slave)
    os.close(send)
    pending, terminal = bytearray(), bytearray()

    def packet():
        deadline = time.monotonic() + 5
        while b'\n' not in pending:
            assert time.monotonic() < deadline, '隔离 curses 子进程没有返回'
            for fd in select.select([receive, master], [], [], 0.1)[0]:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    data = b''
                if fd == receive:
                    assert data, proc.stderr.read().decode()
                    pending.extend(data)
                else:
                    terminal.extend(data)
        line, _, rest = pending.partition(b'\n')
        pending[:] = rest
        return json.loads(line)

    try:
        info = packet()
        # 所有事件使用同一点，避免坐标差异掩盖下滚与点击/移动的 bstate 混叠。
        raw = f'\x1b[<{button};10;8M'.encode() if protocol == 'sgr' else b'\x1b[M' + bytes([button + 32, 42, 40])
        os.write(master, raw + b'\0')
        result = packet()
        deadline = time.monotonic() + 5
        while proc.poll() is None and time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    terminal.extend(os.read(master, 65536))
                except OSError:
                    break
        assert proc.wait(timeout=5) == 0, proc.stderr.read().decode()
        return {**info, 'mask': mask, 'protocol': protocol, 'sent': raw.hex(), **result,
                'terminal_setup': bytes(terminal).decode('ascii', 'backslashreplace')}
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        proc.stderr.close()
        os.close(master)
        os.close(receive)


def run(destination, require_dual):
    results = []
    for protocol in ('legacy', 'sgr'):
        for mask in ('reference', 'all', 'position'):
            for name, button in EVENTS.items():
                result = {'input': name, **sample(mask, protocol, button)}
                results.append(result)
                decoded = ', '.join(event['bstate'] if 'bstate' in event else 'ERR' if 'mouse_error' in event else event['name']
                                    for event in result['events']) or '(filtered)'
                print(protocol, mask, name, decoded, flush=True)
    destination.write_text(json.dumps(results, ensure_ascii=False, indent=2))
    if require_dual:
        # 不依赖 BUTTON5 名称：判定下滚是否被完整识别，且与普通点击/移动可区分。
        native = 'sgr' if '<' in results[0]['kmous'] else 'legacy'
        cases = {r['input']: r['events'] for r in results if r['protocol'] == native and r['mask'] == 'position'}
        up, down = cases['up'], cases['down']
        assert all(len(events) == 1 and events[0].get('mouse', [])[:4] == [0, 9, 7, 0]
                   for events in (up, down)) and all(
            down != cases[name] for name in ('up', 'button6', 'button7', 'left', 'middle', 'move', 'drag')
        ), f'R1: 下滚不是独立可辨的 curses 事件：{cases}'
        print('PASS 原生报告格式中上下滚轮、点击与移动可区分')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--child', nargs=2)
    parser.add_argument('--record', type=Path)
    parser.add_argument('--require-dual', action='store_true')
    args = parser.parse_args()
    if args.child:
        curses.wrapper(child, args.child[0], int(args.child[1]))
    else:
        assert args.record, '请指定 --record 输出证据文件'
        run(args.record, args.require_dual)
