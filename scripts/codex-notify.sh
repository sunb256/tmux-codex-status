#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/codex-state.sh
source "$SCRIPT_DIR/lib/codex-state.sh"

if ! command -v tmux >/dev/null 2>&1; then
    exit 0
fi
if [ -z "${TMUX_PANE:-}" ]; then
    exit 0
fi
if ! tmux display-message -p '#{session_name}' >/dev/null 2>&1; then
    exit 0
fi

EVENT_TYPE="$(codex_extract_event_from_notify_arg "${1:-}")"
STATE="$(codex_map_event_to_state "$EVENT_TYPE")"
PANE_ID="$TMUX_PANE"

tmux_pane_value() {
    local pane_id="$1"
    local format="$2"

    tmux display-message -p -t "$pane_id" "$format" 2>/dev/null || true
}

remember_cwd_window_ref() {
    local pane_id="$1"
    local state="$2"
    local pane_path window_ref cwd_suffix
    local window_ref_key updated_key current_window_ref

    pane_path="$(tmux_pane_value "$pane_id" '#{pane_current_path}')"
    window_ref="$(tmux_pane_value "$pane_id" '#{session_name}:#{window_index}')"
    [ -n "$pane_path" ] || return 0
    [ -n "$window_ref" ] || return 0

    cwd_suffix="$(printf '%s' "$pane_path" | cksum | awk '{print $1}')"
    window_ref_key="TMUX_CODEX_CWD_${cwd_suffix}_WINDOW_REF"
    updated_key="TMUX_CODEX_CWD_${cwd_suffix}_WINDOW_UPDATED_AT"
    current_window_ref="$(tmux show-environment -g "$window_ref_key" 2>/dev/null || true)"
    case "$current_window_ref" in
        "$window_ref_key="*)
            current_window_ref="${current_window_ref#*=}"
            ;;
        *)
            current_window_ref=""
            ;;
    esac

    if [ "$state" = "R" ] || [ -z "$current_window_ref" ] || [ "$current_window_ref" = "$window_ref" ]; then
        tmux set-environment -g "$window_ref_key" "$window_ref"
        tmux set-environment -g "$updated_key" "$(date +%s)"
    fi
}

# Keep only per-pane state in tmux global environment so window rendering can aggregate.
tmux set-environment -g "TMUX_CODEX_PANE_${PANE_ID}_STATE" "$STATE"
tmux set-environment -g "TMUX_CODEX_PANE_${PANE_ID}_UPDATED_AT" "$(date +%s)"
remember_cwd_window_ref "$PANE_ID" "$STATE"

# Best-effort stale cleanup. Rendering is still correct even if cleanup fails.
"$SCRIPT_DIR/codex-state-gc.sh" >/dev/null 2>&1 || true

tmux refresh-client -S 2>/dev/null || true
