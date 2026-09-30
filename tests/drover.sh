#!/usr/bin/env bash
# Schema 2 CLI, legacy decoding, explicit transitions. Synthetic fixtures only.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 "$ROOT/tests/task-flow.py"
python3 "$ROOT/tests/list-json.py"
python3 "$ROOT/tests/list-output.py"
python3 "$ROOT/tests/notifications.py"
