#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"

codex_python() {
    local py_bin
    py_bin="${CODEX_STATUS_PYTHON_BIN:-python3}"
    if ! command -v "$py_bin" >/dev/null 2>&1; then
        py_bin="python"
    fi
    if ! command -v "$py_bin" >/dev/null 2>&1; then
        return 1
    fi

    local current_pythonpath
    current_pythonpath="${PYTHONPATH:-}"
    if [ -n "$current_pythonpath" ]; then
        PYTHONPATH="$ROOT_DIR/src:$current_pythonpath" CODEX_STATUS_SCRIPT_DIR="$ROOT_DIR/scripts" "$py_bin" -m tmux_codex_status.cli "$@"
    else
        PYTHONPATH="$ROOT_DIR/src" CODEX_STATUS_SCRIPT_DIR="$ROOT_DIR/scripts" "$py_bin" -m tmux_codex_status.cli "$@"
    fi
}
