#!/usr/bin/env bash

set -euo pipefail

session_name="${1:-}"
window_index="${2:-}"
pane_index="${3:-}"

if [ -z "$session_name" ] || [ -z "$window_index" ] || [ -z "$pane_index" ]; then
    exit 0
fi
if ! command -v tmux >/dev/null 2>&1; then
    exit 0
fi
if ! tmux list-sessions >/dev/null 2>&1; then
    exit 0
fi

target_window="${session_name}:${window_index}"
target_pane="${target_window}.${pane_index}"

tmux switch-client -t "$session_name" 2>/dev/null || true
tmux select-window -t "$target_window" 2>/dev/null || true
tmux select-pane -t "$target_pane" 2>/dev/null || true

