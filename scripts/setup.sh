#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="${CODEX_STATUS_PYTHON:-python3}"

PYTHONPATH="$PLUGIN_DIR/src${PYTHONPATH:+:$PYTHONPATH}" \
  exec "$PYTHON_BIN" -m tmux_codex_status.cli setup --apply --plugin-dir "$PLUGIN_DIR" "$@"
