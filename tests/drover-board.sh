#!/usr/bin/env bash
# Retained pure-screen regressions. No PTY, recording or real agent calls.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for suite in board-history board-body-scroll board-scrollbars board-layout board-help board-pending; do
    python3 "$ROOT/tests/$suite.py"
done
