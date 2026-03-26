#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="${CODEX_STATUS_PYTHON:-python3}"
EVENT_PAYLOAD="${1-}"

PYTHONPATH="$PLUGIN_DIR/src${PYTHONPATH:+:$PYTHONPATH}" \
  exec "$PYTHON_BIN" -m tmux_codex_status.cli notify "$EVENT_PAYLOAD"
