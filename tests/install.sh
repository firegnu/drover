#!/bin/sh
# 只在临时 HOME 安装；macOS 沙箱禁止子进程写入临时目录以外的位置。
set -eu
exec python3 - "$0" "$@" <<'PY'
import os
import ast
from pathlib import Path
import plistlib
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)).resolve().parent.parent


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="drover-install-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.home = self.base / "home 空格 & 引号'"
        self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=f"{Path(sys.executable).parent}:/usr/bin:/bin:/usr/sbin:/sbin",
                        TMPDIR=str(self.base), PYTHONDONTWRITEBYTECODE="1")
        # 子进程树的写权限只开放给这个临时目录，真实 HOME 不在其中。
        import json
        self.profile = ('(version 1)(allow default)(deny file-write*)'
                        f'(allow file-write* (subpath {json.dumps(str(self.base))}))'
                        '(deny process-exec (literal "/bin/launchctl"))')

    def install(self):
        self.assertTrue((ROOT / "install.sh").is_file(), "安装入口 install.sh 尚未实现")
        return subprocess.run(
            ["/usr/bin/sandbox-exec", "-p", self.profile, "/bin/sh", str(ROOT / "install.sh")],
            cwd=self.base, env=self.env, capture_output=True, text=True)

    def test_install_commands_in_isolated_home(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in ("drover", "drover-board"):
            target = self.home / ".local/bin" / name
            self.assertTrue(target.is_file(), name)
            self.assertTrue(os.access(target, os.X_OK), name)
        self.assertTrue((self.home / ".drover").is_dir())
        self.assertIn("PATH", result.stdout)
        for hint in ("drover init <短名>", "queue.md", "drover loop"):
            self.assertIn(hint, result.stdout)

    def snapshot(self):
        return {
            str(p.relative_to(self.home)): (
                p.lstat().st_mode, p.lstat().st_mtime_ns,
                os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
            for p in self.home.rglob("*")
        }

    def test_reinstall_changes_nothing(self):
        first = self.install()
        self.assertEqual(first.returncode, 0, first.stderr)
        before = self.snapshot()
        second = self.install()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(second.stdout, first.stdout)

    def test_loop_plist_is_rendered_but_not_enabled(self):
        template = ROOT / "launchd/dev.drover.loop.plist"
        self.assertTrue(template.is_file(), "尚未实现 launchd 引擎模板")
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rendered = self.home / ".drover/dev.drover.loop.plist"
        self.assertTrue(rendered.is_file(), "尚未生成路径展开后的 plist")
        for path in (template, rendered):
            lint = subprocess.run(["/usr/bin/plutil", "-lint", str(path)],
                                  capture_output=True, text=True)
            self.assertEqual(lint.returncode, 0, lint.stdout + lint.stderr)
            config = plistlib.loads(path.read_bytes())
            self.assertEqual(config["Label"], "dev.drover.loop")
            self.assertFalse(config["Label"].startswith("dev.herdsman."))
            self.assertIs(config["RunAtLoad"], True)
            self.assertIs(config["KeepAlive"], True)
            self.assertEqual(config["ProgramArguments"][1:], ["loop"])
        config = plistlib.loads(rendered.read_bytes())
        self.assertEqual(config["ProgramArguments"],
                         [str(self.home / ".local/bin/drover"), "loop"])
        self.assertEqual(config["EnvironmentVariables"]["HOME"], str(self.home))
        self.assertEqual(config["EnvironmentVariables"]["PATH"],
                         f"{self.home}/.local/bin:/opt/homebrew/bin:/usr/local/bin:"
                         "/usr/bin:/bin:/usr/sbin:/sbin")
        for key in ("StandardOutPath", "StandardErrorPath"):
            self.assertEqual(Path(config[key]).parent, self.home / ".drover")
        self.assertNotEqual(config["StandardOutPath"], config["StandardErrorPath"])
        self.assertFalse((self.home / "Library/LaunchAgents").exists())
        commands = [shlex.split(line) for line in result.stdout.splitlines()
                    if line.startswith("launchctl ")]
        self.assertEqual(commands, [["launchctl", "bootstrap", f"gui/{os.getuid()}",
                                    str(self.home / "Library/LaunchAgents/dev.drover.loop.plist")]])

    def test_reinstall_after_adding_bin_to_path(self):
        first = self.install()
        self.assertEqual(first.returncode, 0, first.stderr)
        before = self.snapshot()
        self.env["PATH"] = str(self.home / ".local/bin") + os.pathsep + self.env["PATH"]
        second = self.install()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertNotIn("不在 PATH", second.stdout)

    def test_reinstall_after_unrelated_path_changes(self):
        first = self.install()
        self.assertEqual(first.returncode, 0, first.stderr)
        before = self.snapshot()
        original_path = self.env["PATH"]
        extra_a, extra_b = self.base / "unrelated-a", self.base / "unrelated-b"
        extra_a.mkdir()
        extra_b.mkdir()
        for path in (f"{original_path}:{extra_a}",
                     f"{extra_a}:{extra_b}:{original_path}",
                     f"{extra_b}:{extra_a}:{original_path}"):
            with self.subTest(path=path):
                self.env["PATH"] = path
                result = self.install()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.snapshot(), before)

    def test_temporary_python_path_is_not_saved(self):
        venv = self.base / "project/.venv"
        bindir = venv / "bin"
        bindir.mkdir(parents=True)
        python = bindir / "python3"
        python.write_text("#!/bin/sh\nprintf 'temporary-python\\n' >&2\n"
                          f'exec {shlex.quote(sys.executable)} "$@"\n')
        python.chmod(0o755)
        self.env.update(PATH=f"{bindir}:{self.env['PATH']}", VIRTUAL_ENV=str(venv))
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("temporary-python", result.stderr)
        config = plistlib.loads((self.home / ".drover/dev.drover.loop.plist").read_bytes())
        self.assertNotIn(str(bindir), config["EnvironmentVariables"]["PATH"].split(os.pathsep))

    def test_unknown_plist_is_preserved_before_any_install(self):
        for kind in ("file", "directory", "broken-link"):
            with self.subTest(kind=kind):
                self.home = self.base / f"plist-{kind}"
                self.env["HOME"] = str(self.home)
                target = self.home / ".drover/dev.drover.loop.plist"
                target.parent.mkdir(parents=True)
                if kind == "file":
                    target.write_text("someone else's configuration\n")
                elif kind == "directory":
                    target.mkdir()
                else:
                    target.symlink_to(self.base / "missing")
                before = self.snapshot()
                result = self.install()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("拒绝覆盖", result.stdout + result.stderr)
                self.assertEqual(self.snapshot(), before)

    def test_legacy_files_and_shell_config_are_untouched(self):
        paths = [".config/review/config", ".review/board.html", "wt/keep",
                 "Library/LaunchAgents/dev.herdsman.test.plist", ".zshrc", ".bashrc"]
        paths += [f".local/bin/{name}" for name in (
            "herdsman-init", "review-board", "review-map", "review-task",
            "request-review", "review-archive")]
        for name in paths:
            path = self.home / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"leave {name} alone\n")
        before = self.snapshot()
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        after = self.snapshot()
        for name in paths:
            self.assertEqual(after[name], before[name])
        self.assertEqual(set(after) - set(before), {
            ".local/bin/drover", ".local/bin/drover-board", ".drover",
            ".drover/dev.drover.loop.plist"})

    def test_sandbox_rejects_writes_outside_temporary_home_area(self):
        # 用另一个临时目录验沙箱拒写，不拿真实 HOME 做写入探针。
        with tempfile.TemporaryDirectory(prefix="drover-outside-") as outside:
            target = Path(outside) / "must-not-exist"
            probe = subprocess.run(
                ["/usr/bin/sandbox-exec", "-p", self.profile, sys.executable, "-c",
                 "import pathlib, sys; pathlib.Path(sys.argv[1]).write_text('bad')", str(target)],
                cwd=self.base, env=self.env, capture_output=True, text=True)
            self.assertNotEqual(probe.returncode, 0)
            self.assertIn("PermissionError", probe.stderr)
            self.assertFalse(target.exists())

    def test_launchctl_occurs_only_in_printed_instructions(self):
        # 审计入口 shell 只 exec Python；Python 中 launchctl 只能在 print 提示里。
        source = (ROOT / "install.sh").read_text()
        wrapper, body = source.split("<<'PY'\n", 1)
        commands = [line for line in wrapper.splitlines()
                    if line.strip() and not line.startswith("#")]
        self.assertEqual(commands, ["set -eu", 'exec python3 - "$0" '])
        self.assertTrue(body.endswith("\nPY\n"))
        tree = ast.parse(body[:-3])

        class RemovePrints(ast.NodeTransformer):
            def visit_Expr(self, node):
                if (isinstance(node.value, ast.Call)
                        and isinstance(node.value.func, ast.Name)
                        and node.value.func.id == "print"):
                    return None
                return self.generic_visit(node)

        self.assertNotIn("launchctl", ast.dump(RemovePrints().visit(tree)))

    def test_unknown_targets_are_preserved_before_any_install(self):
        for name in ("drover", "drover-board"):
            for kind in ("file", "directory", "broken-link"):
                with self.subTest(name=name, kind=kind):
                    self.home = self.base / f"{name}-{kind}"
                    self.env["HOME"] = str(self.home)
                    bindir = self.home / ".local/bin"
                    bindir.mkdir(parents=True)
                    target = bindir / name
                    if kind == "file":
                        target.write_text("someone else's command\n")
                    elif kind == "directory":
                        target.mkdir()
                    else:
                        target.symlink_to(self.base / "missing")
                    before = self.snapshot()
                    result = self.install()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("拒绝覆盖", result.stdout + result.stderr)
                    self.assertEqual(self.snapshot(), before)


unittest.main()
PY
