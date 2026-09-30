#!/usr/bin/env python3
"""UTF-8 text output remains safe and read-only; public CLI with legacy records."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[1] / 'bin/drover'

class ListOutput(unittest.TestCase):
    def test_surrogates_are_escaped_without_rewriting_history(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(['git','init','-q','-b','main',tmp], check=True)
            (root / '.drover.conf').write_text(f'HANDOFF_DIR={root}/data\n')
            data = root / 'data'
            data.mkdir()
            title = '中文🙂异常\ud800尾'
            events = [dict(ev='start',id='T1',title=title,sha='a',t=1),
                      dict(ev='done',id='T1',sha='b',gate=False,t=2),
                      dict(ev='start',id='T2',title=title,sha='b',t=3)]
            state = data / 'tasks.state'
            state.write_text(''.join(json.dumps(e)+'\n' for e in events))
            (data / 'queue.md').write_text('## T3 后续待办\n')
            before = state.read_bytes()
            env = {**os.environ,'HOME':tmp, 'PYTHONIOENCODING':'utf-8:strict'}
            p = subprocess.run([sys.executable,str(CLI),'list'],cwd=tmp,env=env,capture_output=True)
            self.assertEqual(p.returncode,0,p.stderr)
            self.assertEqual(p.stderr,b'')
            self.assertEqual(p.stdout.decode().count('中文🙂异常\\ud800尾'),2)
            self.assertIn('T3 后续待办',p.stdout.decode())
            self.assertEqual(state.read_bytes(),before)

if __name__ == '__main__': unittest.main()
