#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$ROOT_DIR/tests/test-state-map.sh"
bash "$ROOT_DIR/tests/test-state-rank.sh"
bash "$ROOT_DIR/tests/test-window-badge.sh"
bash "$ROOT_DIR/tests/test-pane-badge.sh"
bash "$ROOT_DIR/tests/test-pane-menu.sh"
bash "$ROOT_DIR/tests/test-gc.sh"

printf 'PASS: all tests\n'
