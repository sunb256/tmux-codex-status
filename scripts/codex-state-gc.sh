#!/usr/bin/env bash

set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
    exit 0
fi
if ! tmux list-sessions >/dev/null 2>&1; then
    exit 0
fi

declare -A ACTIVE_PANES=()
while IFS= read -r pane_id; do
    [ -n "$pane_id" ] || continue
    ACTIVE_PANES["$pane_id"]=1
done < <(tmux list-panes -a -F '#{pane_id}' 2>/dev/null || true)

while IFS= read -r line; do
    [ -n "$line" ] || continue

    case "$line" in
        -*)
            continue
            ;;
    esac

    key="${line%%=*}"
    pane_id=""

    case "$key" in
        TMUX_CODEX_PANE_*_STATE)
            pane_id="${key#TMUX_CODEX_PANE_}"
            pane_id="${pane_id%_STATE}"
            ;;
        TMUX_CODEX_PANE_*_UPDATED_AT)
            pane_id="${key#TMUX_CODEX_PANE_}"
            pane_id="${pane_id%_UPDATED_AT}"
            ;;
        *)
            continue
            ;;
    esac

    if [ -z "${ACTIVE_PANES[$pane_id]+x}" ]; then
        tmux set-environment -gu "TMUX_CODEX_PANE_${pane_id}_STATE" 2>/dev/null || true
        tmux set-environment -gu "TMUX_CODEX_PANE_${pane_id}_UPDATED_AT" 2>/dev/null || true
    fi
done < <(tmux show-environment -g 2>/dev/null || true)
