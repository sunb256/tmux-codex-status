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

tmux_option_is_set() {
    local option="$1"
    local raw
    raw="$(tmux show-option -gq "$option" 2>/dev/null || true)"
    [ -n "$raw" ]
}

tmux_get_option_or_default() {
    local option="$1"
    local default_value="$2"

    if tmux_option_is_set "$option"; then
        tmux show-option -gqv "$option"
    else
        printf '%s\n' "$default_value"
    fi
}

tmux_get_env() {
    local key="$1"
    local line

    line="$(tmux show-environment -g "$key" 2>/dev/null || true)"
    case "$line" in
        "$key="*)
            printf '%s\n' "${line#*=}"
            ;;
        "-$key"|"")
            printf '\n'
            ;;
        *)
            printf '\n'
            ;;
    esac
}

tmux_pane_value() {
    local pane_id="$1"
    local format="$2"

    tmux display-message -p -t "$pane_id" "$format" 2>/dev/null || true
}

is_non_negative_integer() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

session_meta_cwd_from_file() {
    local file="$1"
    local first_line

    first_line="$(sed -n '1p' "$file" 2>/dev/null || true)"
    case "$first_line" in
        *'"type":"session_meta"'*)
            printf '%s' "$first_line" | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p'
            ;;
        *)
            printf '\n'
            ;;
    esac
}

find_recent_session_file_for_cwd() {
    local pane_path="$1"
    local session_file session_cwd

    [ -n "$pane_path" ] || return 1
    [ -d "$SESSIONS_DIR" ] || return 1
    [ "$SESSION_SCAN_LIMIT" -gt 0 ] || return 1
    [ "$SESSION_LOOKBACK_MINUTES" -gt 0 ] || return 1

    while IFS= read -r session_file; do
        [ -n "$session_file" ] || continue
        session_cwd="$(session_meta_cwd_from_file "$session_file")"
        [ -n "$session_cwd" ] || continue
        [ "$session_cwd" = "$pane_path" ] || continue

        printf '%s\n' "$session_file"
        return 0
    done < <(find "$SESSIONS_DIR" -type f -name '*.jsonl' -mmin "-$SESSION_LOOKBACK_MINUTES" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n "$SESSION_SCAN_LIMIT" | cut -d' ' -f2-)

    return 1
}

SESSIONS_DIR="$(tmux_get_option_or_default "@codex-status-sessions-dir" "${CODEX_HOME:-$HOME/.codex}/sessions")"
SESSION_LOOKBACK_MINUTES="$(tmux_get_option_or_default "@codex-status-session-lookback-minutes" "240")"
SESSION_SCAN_LIMIT="$(tmux_get_option_or_default "@codex-status-session-scan-limit" "40")"

if ! is_non_negative_integer "$SESSION_LOOKBACK_MINUTES"; then
    SESSION_LOOKBACK_MINUTES="240"
fi
if ! is_non_negative_integer "$SESSION_SCAN_LIMIT"; then
    SESSION_SCAN_LIMIT="40"
fi

if [ "$STATE" = "K" ]; then
    STATE="$(tmux_get_env "TMUX_CODEX_PANE_${PANE_ID}_STATE")"
    if [ -z "$STATE" ]; then
        STATE="W"
    fi
fi

remember_cwd_window_ref() {
    local pane_id="$1"
    local state="$2"
    local pane_path window_ref cwd_suffix
    local window_ref_key updated_key current_window_ref
    local window_suffix session_file session_file_key session_file_updated_key

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

    session_file="$(find_recent_session_file_for_cwd "$pane_path" || true)"
    if [ -n "$session_file" ]; then
        window_suffix="$(printf '%s\t%s' "$pane_path" "$window_ref" | cksum | awk '{print $1}')"
        session_file_key="TMUX_CODEX_CWD_${window_suffix}_SESSION_FILE"
        session_file_updated_key="TMUX_CODEX_CWD_${window_suffix}_SESSION_FILE_UPDATED_AT"
        tmux set-environment -g "$session_file_key" "$session_file"
        tmux set-environment -g "$session_file_updated_key" "$(date +%s)"
    fi
}

# Keep only per-pane state in tmux global environment so window rendering can aggregate.
tmux set-environment -g "TMUX_CODEX_PANE_${PANE_ID}_STATE" "$STATE"
tmux set-environment -g "TMUX_CODEX_PANE_${PANE_ID}_UPDATED_AT" "$(date +%s)"
remember_cwd_window_ref "$PANE_ID" "$STATE"

# Best-effort stale cleanup. Rendering is still correct even if cleanup fails.
"$SCRIPT_DIR/codex-state-gc.sh" >/dev/null 2>&1 || true

tmux refresh-client -S 2>/dev/null || true
