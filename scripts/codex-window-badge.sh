#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/codex-state.sh
source "$SCRIPT_DIR/lib/codex-state.sh"

WINDOW_ID="${1:-}"
OUTPUT_MODE="${2:-styled}"

if [ -z "$WINDOW_ID" ]; then
    exit 0
fi
case "$OUTPUT_MODE" in
    styled|plain)
        ;;
    *)
        OUTPUT_MODE="styled"
        ;;
esac
if ! command -v tmux >/dev/null 2>&1; then
    exit 0
fi
if ! tmux list-sessions >/dev/null 2>&1; then
    exit 0
fi

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

pane_has_process() {
    local tty="$1"
    local process_name="$2"

    [ -n "$tty" ] || return 1

    ps -t "$(basename "$tty")" -o command= 2>/dev/null | grep -qw "$process_name"
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

session_latest_task_event() {
    local file="$1"
    local line

    if command -v rg >/dev/null 2>&1; then
        line="$(rg -n '"type":"event_msg","payload":\{"type":"(task_started|task_complete|turn_aborted)"' "$file" -S 2>/dev/null | tail -n 1)"
    else
        line="$(grep -nE '"type":"event_msg","payload":\{"type":"(task_started|task_complete|turn_aborted)"' "$file" 2>/dev/null | tail -n 1)"
    fi

    if [ -z "$line" ]; then
        printf '\n'
        return 0
    fi

    printf '%s' "$line" | sed -n 's/.*"payload":{"type":"\([^"]*\)".*/\1/p'
}

codex_cwd_running_state_from_sessions() {
    local pane_path="$1"
    local pane_window_ref="${2:-}"
    local now cwd_suffix window_ref_key cached_window_ref
    local cache_suffix cache_state_key cache_updated_key cached_state cached_updated_at inferred_state
    local session_file session_cwd latest_event
    local session_file_key session_file_updated_key mapped_session_file
    local matched_file match_count use_fallback_scan has_valid_mapped_file

    [ -n "$pane_path" ] || return 1
    [ -n "$pane_window_ref" ] || return 1
    [ -d "$SESSIONS_DIR" ] || return 1
    [ "$SESSION_SCAN_LIMIT" -gt 0 ] || return 1
    [ "$SESSION_LOOKBACK_MINUTES" -gt 0 ] || return 1

    now="$(date +%s)"

    cache_suffix="$(printf '%s\t%s' "$pane_path" "$pane_window_ref" | cksum | awk '{print $1}')"
    cache_state_key="TMUX_CODEX_CWD_${cache_suffix}_INFERRED_STATE"
    cache_updated_key="TMUX_CODEX_CWD_${cache_suffix}_INFERRED_UPDATED_AT"
    session_file_key="TMUX_CODEX_CWD_${cache_suffix}_SESSION_FILE"
    session_file_updated_key="TMUX_CODEX_CWD_${cache_suffix}_SESSION_FILE_UPDATED_AT"
    mapped_session_file="$(tmux_get_env "$session_file_key")"

    has_valid_mapped_file=0
    if [ -n "$mapped_session_file" ] && [ -f "$mapped_session_file" ]; then
        session_cwd="$(session_meta_cwd_from_file "$mapped_session_file")"
        if [ -n "$session_cwd" ] && [ "$session_cwd" = "$pane_path" ]; then
            has_valid_mapped_file=1
        fi
    fi

    if [ "$has_valid_mapped_file" -eq 0 ]; then
        cwd_suffix="$(printf '%s' "$pane_path" | cksum | awk '{print $1}')"
        window_ref_key="TMUX_CODEX_CWD_${cwd_suffix}_WINDOW_REF"
        cached_window_ref="$(tmux_get_env "$window_ref_key")"
        [ -n "$cached_window_ref" ] || return 1
        [ "$cached_window_ref" = "$pane_window_ref" ] || return 1
    fi

    cached_state="$(tmux_get_env "$cache_state_key")"
    cached_updated_at="$(tmux_get_env "$cache_updated_key")"

    if [ "$SESSION_CACHE_SECONDS" -gt 0 ] && is_non_negative_integer "$cached_updated_at"; then
        if [ $((now - cached_updated_at)) -le "$SESSION_CACHE_SECONDS" ]; then
            case "$cached_state" in
                R|W)
                    printf '%s\n' "$cached_state"
                    return 0
                    ;;
            esac
            return 1
        fi
    fi

    inferred_state=""
    latest_event=""
    use_fallback_scan=1

    if [ "$has_valid_mapped_file" -eq 1 ]; then
        latest_event="$(session_latest_task_event "$mapped_session_file")"
        use_fallback_scan=0
    fi

    if [ "$use_fallback_scan" -eq 1 ]; then
        matched_file=""
        match_count=0
        while IFS= read -r session_file; do
            [ -n "$session_file" ] || continue

            session_cwd="$(session_meta_cwd_from_file "$session_file")"
            [ -n "$session_cwd" ] || continue
            [ "$session_cwd" = "$pane_path" ] || continue

            match_count=$((match_count + 1))
            if [ "$match_count" -eq 1 ]; then
                matched_file="$session_file"
            else
                break
            fi
        done < <(find "$SESSIONS_DIR" -type f -name '*.jsonl' -mmin "-$SESSION_LOOKBACK_MINUTES" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n "$SESSION_SCAN_LIMIT" | cut -d' ' -f2-)

        if [ "$match_count" -eq 1 ] && [ -n "$matched_file" ]; then
            latest_event="$(session_latest_task_event "$matched_file")"
            tmux set-environment -g "$session_file_key" "$matched_file" 2>/dev/null || true
            tmux set-environment -g "$session_file_updated_key" "$now" 2>/dev/null || true
        fi
    fi

    case "$latest_event" in
        task_started)
            inferred_state="R"
            ;;
        task_complete|turn_aborted)
            inferred_state="W"
            ;;
    esac

    if [ -n "$inferred_state" ] && [ "$SESSION_CACHE_SECONDS" -gt 0 ]; then
        tmux set-environment -g "$cache_state_key" "$inferred_state" 2>/dev/null || true
        tmux set-environment -g "$cache_updated_key" "$now" 2>/dev/null || true
    fi

    if [ -n "$inferred_state" ]; then
        printf '%s\n' "$inferred_state"
        return 0
    fi
    return 1
}

state_bg_color() {
    local state="$1"

    case "$state" in
        R)
            tmux_get_option_or_default "@codex-status-bg-r" "$(tmux_get_option_or_default "@codex-status-color-r" "colour208")"
            ;;
        W)
            tmux_get_option_or_default "@codex-status-bg-w" "$(tmux_get_option_or_default "@codex-status-color-w" "colour240")"
            ;;
        I)
            tmux_get_option_or_default "@codex-status-bg-i" "$(tmux_get_option_or_default "@codex-status-color-i" "colour226")"
            ;;
        E)
            tmux_get_option_or_default "@codex-status-bg-e" "$(tmux_get_option_or_default "@codex-status-color-e" "colour196")"
            ;;
        *)
            tmux_get_option_or_default "@codex-status-bg-w" "$(tmux_get_option_or_default "@codex-status-color-w" "colour240")"
            ;;
    esac
}

state_fg_color() {
    local state="$1"

    case "$state" in
        R)
            tmux_get_option_or_default "@codex-status-fg-r" "colour16"
            ;;
        W)
            tmux_get_option_or_default "@codex-status-fg-w" "colour16"
            ;;
        I)
            tmux_get_option_or_default "@codex-status-fg-i" "colour16"
            ;;
        E)
            tmux_get_option_or_default "@codex-status-fg-e" "colour255"
            ;;
        *)
            tmux_get_option_or_default "@codex-status-fg-w" "colour255"
            ;;
    esac
}

ICON="$(tmux_get_option_or_default "@codex-status-icon" "🤖")"
PROCESS_NAME="$(tmux_get_option_or_default "@codex-status-process-name" "codex")"
SESSIONS_DIR="$(tmux_get_option_or_default "@codex-status-sessions-dir" "${CODEX_HOME:-$HOME/.codex}/sessions")"
SESSION_LOOKBACK_MINUTES="$(tmux_get_option_or_default "@codex-status-session-lookback-minutes" "240")"
SESSION_SCAN_LIMIT="$(tmux_get_option_or_default "@codex-status-session-scan-limit" "40")"
SESSION_CACHE_SECONDS="$(tmux_get_option_or_default "@codex-status-session-cache-seconds" "2")"
STALE_R_GRACE_SECONDS="$(tmux_get_option_or_default "@codex-status-stale-r-grace-seconds" "5")"

if ! is_non_negative_integer "$SESSION_LOOKBACK_MINUTES"; then
    SESSION_LOOKBACK_MINUTES="240"
fi
if ! is_non_negative_integer "$SESSION_SCAN_LIMIT"; then
    SESSION_SCAN_LIMIT="40"
fi
if ! is_non_negative_integer "$SESSION_CACHE_SECONDS"; then
    SESSION_CACHE_SECONDS="2"
fi
if ! is_non_negative_integer "$STALE_R_GRACE_SECONDS"; then
    STALE_R_GRACE_SECONDS="5"
fi

set_window_plain_badge() {
    local value="${1:-}"
    tmux set-window-option -q -t "$WINDOW_ID" "@codex-status-window-badge" "$value" 2>/dev/null || true
}

declare -a CODEX_PANES=()
declare -A PANE_PATHS=()
declare -A PANE_WINDOW_REFS=()
while IFS=$'\t' read -r pane_id pane_tty pane_path pane_window_ref; do
    [ -n "$pane_id" ] || continue

    if pane_has_process "$pane_tty" "$PROCESS_NAME"; then
        CODEX_PANES+=("$pane_id")
        PANE_PATHS["$pane_id"]="$pane_path"
        PANE_WINDOW_REFS["$pane_id"]="$pane_window_ref"
    fi
done < <(tmux list-panes -t "$WINDOW_ID" -F '#{pane_id}	#{pane_tty}	#{pane_current_path}	#{session_name}:#{window_index}' 2>/dev/null || true)

if [ "${#CODEX_PANES[@]}" -eq 0 ]; then
    set_window_plain_badge ""
    printf '\n'
    exit 0
fi

WINNER_STATE="W"
WINNER_RANK=0
NOW_EPOCH="$(date +%s)"

for pane_id in "${CODEX_PANES[@]}"; do
    pane_state="$(tmux_get_env "TMUX_CODEX_PANE_${pane_id}_STATE")"
    pane_updated_at="$(tmux_get_env "TMUX_CODEX_PANE_${pane_id}_UPDATED_AT")"
    pane_path="${PANE_PATHS[$pane_id]:-}"
    pane_window_ref="${PANE_WINDOW_REFS[$pane_id]:-}"

    if [ -z "$pane_state" ]; then
        pane_state="W"
    fi

    pane_state="$(codex_normalize_state "$pane_state")"
    if [ "$pane_state" = "W" ]; then
        inferred_state="$(codex_cwd_running_state_from_sessions "$pane_path" "$pane_window_ref" || true)"
        if [ "$inferred_state" = "R" ]; then
            pane_state="R"
        fi
    elif [ "$pane_state" = "R" ]; then
        if [ "$STALE_R_GRACE_SECONDS" -eq 0 ] || { is_non_negative_integer "$pane_updated_at" && [ $((NOW_EPOCH - pane_updated_at)) -ge "$STALE_R_GRACE_SECONDS" ]; }; then
            inferred_state="$(codex_cwd_running_state_from_sessions "$pane_path" "$pane_window_ref" || true)"
            if [ "$inferred_state" = "W" ]; then
                pane_state="W"
            fi
        fi
    fi

    pane_rank="$(codex_state_rank "$pane_state")"

    if [ "$pane_rank" -gt "$WINNER_RANK" ]; then
        WINNER_RANK="$pane_rank"
        WINNER_STATE="$pane_state"
    fi
done

BG_COLOR="$(state_bg_color "$WINNER_STATE")"
FG_COLOR="$(state_fg_color "$WINNER_STATE")"
if [ "$FG_COLOR" = "$BG_COLOR" ]; then
    if [ "$BG_COLOR" = "colour16" ]; then
        FG_COLOR="colour255"
    else
        FG_COLOR="colour16"
    fi
fi

if [ -n "$ICON" ]; then
    PLAIN_BADGE="${ICON}"
else
    PLAIN_BADGE=""
fi
set_window_plain_badge "$PLAIN_BADGE"

if [ "$OUTPUT_MODE" = "plain" ]; then
    printf '%s\n' "$PLAIN_BADGE"
else
    if [ -n "$PLAIN_BADGE" ]; then
        printf '#[fg=%s,bg=%s]%s#[default]\n' "$FG_COLOR" "$BG_COLOR" "$PLAIN_BADGE"
    else
        printf '\n'
    fi
fi
