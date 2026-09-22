#!/usr/bin/env python3
"""合成视觉演示，直接调用生产 draw/key_action；从不采集或运行写操作。

交互：python3 tests/board-demo.py --scene working [--multi]
录制：python3 tests/board-demo.py --record /tmp/m16-visual
录制在真实 PTY 内运行 curses，保存 ANSI 输出、curses 屏幕文本与尺寸/视口。
"""
import argparse
import copy
import curses
import fcntl
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import termios
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SCENES = ("working", "sent", "failed", "waiting", "idle", "empty", "warning", "long", "body")


def load_board():
    loader = importlib.machinery.SourceFileLoader("board", os.environ.get("DROVER_BOARD_BIN", str(ROOT / "bin/drover-board")))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    return module


def fixture(scene="working", multi=False):
    route = {"tier": "常规", "cross": True, "overridden": False}
    card = {"id": "T42", "title": "为结算页增加优惠券校验与失败提示", "body": [
        "结算页目前不校验优惠券是否过期或已用尽。请在提交订单前调用 coupon.validate，失败时在优惠券输入框下方显示原因，并保留用户已填写的其他字段。",
        "", "仅修改结算页和对应测试，保留原有接口。"],
        "waiting": False, "held": False, "span": "1h12m", "commits": 3,
        "on_main": 0, "route": route, "progress": "main 上 0 个提交，还没有提交落地", "met": "0/3",
        "criteria": [
            {"name": "收尾记号", "ok": False, "why": "a1f3c2..main 里没有「收尾: 」开头的空提交"},
            {"name": "main 前进了", "ok": False, "why": "送任务之后没有前进（基线 a1f3c2）"},
            {"name": "这次建的分支都合进去了", "ok": False, "why": "还没合进 main: feat/coupon-check"},
            {"name": "验收命令过了", "ok": None, "why": "没跑过（无有效核对记录）；按 g / drover go 核对并放行"}]}
    todo = [{"id": f"T{i}", "title": title, "next": i == 43, "held": i == 45} for i, title in enumerate(
        ("订单列表支持按状态筛选", "导出 CSV 时包含退款记录", "清理旧的支付回调"), 43)]
    history = [{"id": f"T{i}", "title": title, "dropped": i == 39,
                "reason": "供应商 API 需要企业账号，暂无法申请，改为手动录入。" if i == 39 else "",
                "span": "48m", "range": "a1f3c2..b3c4d5", "commits": 2, "wait": "5m", "route": route}
               for i, title in ((41, "修复购物车数量为 0 时的崩溃"), (40, "统一金额格式化"), (39, "接入第三方地址补全"))]
    q = {"mode": "放行模式", "loop": False, "paused": False, "gate": True, "awaiting": False,
         "counts": {"todo": 3, "doing": 1, "done": 2, "dropped": 1}, "card": card,
         "crew": [{"name": "demo/dev-1", "state": "working", "since": 0, "where": "wt/coupon"}],
         "todo": todo, "finished": history}
    pv = {"name": "demo-shop", "repo": "/synthetic/demo-shop", "dir": "/synthetic/handoff",
          "head": "a1f3c2", "state": "进行中", "waiting": False, "needs_me": False,
          "badge": "none", "age": "", "waits": [], "queue": q}
    msg = ""
    if scene == "sent":
        msg = f'已送给 demo/main：{card["id"]} {card["title"]}'
    if scene == "failed":
        card["criteria"][3].update(ok=False, why="pytest tests/checkout：退出码 1；优惠券已过期的提示与预期不符")
        card["met"] = "0/4"
        msg = "未放行 · - 判据 3：退出码 1，优惠券已过期的提示与预期不符 · 完整输出：expected 已过期, got 无效优惠券"
    if scene == "waiting":
        card.update(waiting=True, on_main=4, progress="main 上 4 个提交，最后一次 6m 前", met="4/4")
        for row, why in zip(card["criteria"], ("b3c4d5 收尾: 优惠券完成", "a1f3c2 → b3c4d5", "没有未合并的分支", "pytest tests/checkout 过了")):
            row.update(ok=True, why=why)
        pv.update(state="等你放行", waiting=True, needs_me=True, badge="me", waits=["T42 做完了，核对已通过，等你按 g 放行"])
        q.update(awaiting=True)
    if scene in ("idle", "empty", "warning"):
        q["card"] = None
        pv["state"] = "空闲"
    if scene == "empty":
        q["todo"] = []
        q["counts"]["todo"] = 0
    if scene in ("failed", "waiting", "idle", "empty", "warning"):
        q["crew"][0].update(state="idle", since=360)
    if scene == "warning":
        msg = "已放行 · ↑ 没看到收尾记号，这次算你自己判断的 · 核对通过，已记完成并放行；请自行确认工作已收尾"
    if scene == "long":
        card["title"] += "，兼容中文、组合字符 e\u0301 与超长路径" * 5 + "【标题末尾】"
        card["body"] += [f"正文{i:02d}：" + "保持两个空格  与 Unicode 分支 feature/a\u00a0b\u2028c；" * 3 for i in range(16)] + ["【正文末尾】"]
        card["criteria"][2]["why"] = "未合入：" + "feature/a\u00a0b\u2028c/" * 20 + "【判据末尾】"
        q["crew"][0]["where"] = "/synthetic/" + "中文目录/" * 15 + "【路径末尾】"
        q["todo"] += [{"id": f"T{i}", "title": f"待办{i}完整条目", "next": False, "held": False} for i in range(46, 60)]
        q["finished"][-1]["reason"] += "保留完整失败理由。" * 40 + "【历史末尾】"
        q["counts"]["todo"] = len(q["todo"])
        msg = "未放行 · - 判据未满足：" + "很长的拒绝原因必须完整可读；" * 20 + "【消息末尾】"
    if scene == "body":
        card["body"] = [f"正文{i:02d}：鼠标移到这里，上下滚动；判据和其它区域保持位置。" for i in range(1, 38)] + ["【正文末尾】"]
    q["counts"]["doing"] = int(bool(q["card"] and not q["card"]["waiting"]))
    projects = [pv]
    if multi:
        other = copy.deepcopy(pv)
        other.update(name="billing-api", repo="/synthetic/billing-api", needs_me=True, badge="me", waits=["主控空闲着，但判据还没满足"])
        third = copy.deepcopy(pv)
        third.update(name="docs-site", repo="/synthetic/docs-site")
        third["queue"]["paused"] = True
        projects += [other, third]
    return {"health": {"ok": True, "text": "corral 正常（合成）"}, "waits": [
        {"project": p["name"], "text": t, "age": "6m"} for p in projects for t in p["waits"]], "projects": projects}, msg


def demo(screen, args):
    B = load_board()
    curses.curs_set(0)
    B.init_colors()
    vm, msg = fixture(args.scene, args.multi)
    state = {"sel": 0, "n": len(vm["projects"]), "msg": msg, "body_mouse": B.init_mouse()}
    count = 0

    def frame(label):
        nonlocal count
        B.draw(screen, vm, state)
        screen.refresh()
        if args.capture:
            h, w = screen.getmaxyx()
            path = Path(args.capture) / f"{count:02d}-{label}-{w}x{h}"
            path.with_suffix(".txt").write_text("\n".join(screen.instr(y, 0).decode("utf-8") for y in range(h)) + "\n")
            path.with_suffix(".json").write_text(json.dumps({"size": [w, h], "scene": args.scene, "multi": args.multi, "state": state}, ensure_ascii=False, indent=2))
            count += 1

    if args.capture:
        frame("top")
        while True:
            for region in ("body", "history"):
                while state.get(region + "_rect"):
                    x, y = state[region + "_rect"][:2]
                    action = B.key_action(curses.KEY_MOUSE, vm["projects"][state["sel"]], state,
                                          (0, x, y, 0, curses.BUTTON5_PRESSED))
                    if action[1] == state[region + "_offset"]:
                        break
                    state[region + "_offset"] = action[1]
                    frame(region)
            offset = B.key_action(curses.KEY_NPAGE, vm["projects"][state["sel"]], state)[1]
            if offset == state["detail_offset"]:
                break
            state["detail_offset"] = offset
            frame("page")
        for h, w in ((24, 80), (10, 40), (32, 120)):
            fcntl.ioctl(sys.stdout.fileno(), termios.TIOCSWINSZ, struct.pack("HHHH", h, w, 0, 0))
            curses.resizeterm(h, w)
            frame("resize")
        if args.multi:
            state["sel"] = B.key_action(ord("j"), vm["projects"][0], state)[1]
            frame("project")
        return
    screen.timeout(B.REFRESH_MS)
    while True:
        frame("interactive")
        key, mouse = screen.getch(), None
        if key == curses.KEY_MOUSE:
            try:
                mouse = curses.getmouse()
            except curses.error:
                continue
            if screen.getmaxyx() != state["screen_size"]:
                continue
        act = B.key_action(key, vm["projects"][state["sel"]], state, mouse)
        if not act:
            continue
        if act[0] == "quit":
            return
        if act[0] == "scroll":
            state["detail_offset"] = act[1]
        elif act[0] in ("body_scroll", "history_scroll"):
            state[act[0].replace("_scroll", "_offset")] = act[1]
        elif act[0] == "sel":
            state["sel"] = act[1]
        elif act[0] in ("run", "edit"):
            state["msg"] = "合成演示：不执行命令、不打开编辑器"


def record(destination):
    root = Path(destination).resolve()
    root.mkdir(parents=True, exist_ok=True)
    for scene in SCENES:
        for multi in (False, True):
            for w, h in ((120, 32), (80, 24)):
                target = root / f'{scene}-{"multi" if multi else "single"}-{w}x{h}'
                target.mkdir(exist_ok=True)
                master, slave = os.openpty()
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", h, w, 0, 0))
                command = [sys.executable, "-B", __file__, "--scene", scene, "--capture", str(target)] + (["--multi"] if multi else [])
                with (target / "terminal.ansi").open("wb") as output, (target / "stderr.txt").open("wb") as errors:
                    proc = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=errors, env={**os.environ, "TERM": "xterm-256color", "LC_ALL": "en_US.UTF-8"})
                    os.close(slave)
                    deadline = time.monotonic() + 30
                    try:
                        while True:
                            ready, _, _ = select.select([master], [], [], 0.1)
                            if ready:
                                try:
                                    data = os.read(master, 65536)
                                except OSError:
                                    break
                                if not data:
                                    break
                                output.write(data)
                            elif proc.poll() is not None:
                                break
                            if time.monotonic() > deadline:
                                raise TimeoutError(command)
                        assert proc.wait(timeout=5) == 0, (target / "stderr.txt").read_text()
                    finally:
                        if proc.poll() is None:
                            proc.kill()
                            proc.wait()
                        os.close(master)
                print(target.name, "PASS", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene", choices=SCENES, default="working")
    parser.add_argument("--multi", action="store_true")
    parser.add_argument("--record")
    parser.add_argument("--capture", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.record:
        record(args.record)
    else:
        curses.wrapper(demo, args)
