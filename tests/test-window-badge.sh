#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOCK="codex-status-test-$RANDOM-$$"
OUT_FILE="/tmp/codex-status-window-${SOCK}.out"
SESSIONS_DIR="/tmp/codex-status-sessions-${SOCK}"

cleanup() {
    env -u TMUX tmux -L "$SOCK" kill-server >/dev/null 2>&1 || true
    rm -f "$OUT_FILE"
    rm -rf "$SESSIONS_DIR"
}
trap cleanup EXIT

tmux_cmd() {
    env -u TMUX tmux -L "$SOCK" "$@"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    if [ "$expected" != "$actual" ]; then
        printf 'FAIL: %s (expected=%q actual=%q)\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'FAIL: %s (missing=%q actual=%q)\n' "$label" "$needle" "$haystack" >&2
        exit 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        printf 'FAIL: %s (unexpected=%q actual=%q)\n' "$label" "$needle" "$haystack" >&2
        exit 1
    fi
}

assert_option_eq() {
    local target="$1"
    local option="$2"
    local expected="$3"
    local label="$4"
    local actual

    actual="$(tmux_cmd show-options -wqv -t "$target" "$option" 2>/dev/null || true)"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s (expected=%q actual=%q)\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

run_badge() {
    local win_id="$1"
    local mode="${2:-styled}"

    tmux_cmd run-shell "bash '$ROOT_DIR/scripts/codex-window-badge.sh' '$win_id' '$mode' > '$OUT_FILE'"
    cat "$OUT_FILE" 2>/dev/null || true
}

write_fake_session() {
    local file="$1"
    local cwd="$2"
    local event="$3"

    cat > "$file" <<EOF
{"timestamp":"2026-02-22T00:00:00.000Z","type":"session_meta","payload":{"id":"test","timestamp":"2026-02-22T00:00:00.000Z","cwd":"$cwd"}}
{"timestamp":"2026-02-22T00:00:01.000Z","type":"event_msg","payload":{"type":"$event","turn_id":"turn-1"}}
EOF
}

set_cwd_window_ref() {
    local cwd="$1"
    local window_ref="$2"
    local cwd_suffix

    cwd_suffix="$(printf '%s' "$cwd" | cksum | awk '{print $1}')"
    tmux_cmd set-environment -g "TMUX_CODEX_CWD_${cwd_suffix}_WINDOW_REF" "$window_ref"
}

tmux_cmd -f /dev/null new-session -d -s t -n main

tmux_cmd set -g @codex-status-icon '🤖'
tmux_cmd set -g @codex-status-process-name 'codex'
tmux_cmd set -g @codex-status-sessions-dir "$SESSIONS_DIR"
tmux_cmd set -g @codex-status-session-cache-seconds '0'
tmux_cmd set -g @codex-status-bg-r 'colour1'
tmux_cmd set -g @codex-status-bg-w 'colour2'
tmux_cmd set -g @codex-status-bg-i 'colour3'
tmux_cmd set -g @codex-status-bg-e 'colour4'
mkdir -p "$SESSIONS_DIR"

WIN_MAIN="$(tmux_cmd display-message -p -t t:main.0 '#{window_id}')"
WIN_MAIN_REF="$(tmux_cmd display-message -p -t t:main.0 '#{session_name}:#{window_index}')"
PANE1="$(tmux_cmd display-message -p -t t:main.0 '#{pane_id}')"
PANE1_CWD="$(tmux_cmd display-message -p -t t:main.0 '#{pane_current_path}')"

tmux_cmd send-keys -t t:main.0 "exec -a codex sleep 120" C-m
sleep 0.1

# With Codex process and no explicit state -> W
out="$(run_badge "$WIN_MAIN")"
assert_contains "$out" '🤖' 'icon should be shown for codex window'
assert_contains "$out" 'bg=colour2' 'default state W should use W background color'
assert_not_contains "$out" '🤖 W' 'state letter should not be rendered'
assert_option_eq "$WIN_MAIN" "@codex-status-window-badge" "🤖" "window option badge should store icon only"
out_plain="$(run_badge "$WIN_MAIN" plain)"
assert_eq "🤖" "$out_plain" 'plain mode outputs icon only'
assert_not_contains "$out_plain" '#[' 'plain mode should not include tmux style segments'

SESSION_FILE="$SESSIONS_DIR/test-running.jsonl"
write_fake_session "$SESSION_FILE" "$PANE1_CWD" "task_started"
set_cwd_window_ref "$PANE1_CWD" "$WIN_MAIN_REF"
out="$(run_badge "$WIN_MAIN")"
assert_contains "$out" 'bg=colour1' 'task_started in session log should use R background color'

write_fake_session "$SESSION_FILE" "$PANE1_CWD" "task_complete"
out="$(run_badge "$WIN_MAIN")"
assert_contains "$out" 'bg=colour2' 'task_complete in session log should use W background color'

write_fake_session "$SESSION_FILE" "$PANE1_CWD" "task_started"
set_cwd_window_ref "$PANE1_CWD" "$WIN_MAIN_REF"

tmux_cmd new-window -d -t t -n samecwd -c "$PANE1_CWD"
WIN_SAME="$(tmux_cmd display-message -p -t t:samecwd.0 '#{window_id}')"
tmux_cmd send-keys -t t:samecwd.0 "exec -a codex sleep 120" C-m
sleep 0.1

out_main="$(run_badge "$WIN_MAIN")"
assert_contains "$out_main" 'bg=colour1' 'matching window should infer R from session log'
out_same="$(run_badge "$WIN_SAME")"
assert_contains "$out_same" 'bg=colour2' 'different window with same cwd should stay W'

tmux_cmd send-keys -t t:samecwd.0 "bash '$ROOT_DIR/scripts/codex-notify.sh' 'agent-turn-complete'" C-m
sleep 0.1
out_main="$(run_badge "$WIN_MAIN")"
assert_contains "$out_main" 'bg=colour1' 'W event from another window should not steal cwd-window mapping'

tmux_cmd split-window -d -t t:main.0
PANE2="$(tmux_cmd display-message -p -t t:main.1 '#{pane_id}')"
tmux_cmd send-keys -t t:main.1 "exec -a codex sleep 120" C-m
sleep 0.1

tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE1}_STATE" 'R'
tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE2}_STATE" 'I'
out="$(run_badge "$WIN_MAIN")"
assert_contains "$out" 'bg=colour3' 'I outranks R'

tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE1}_STATE" 'E'
out="$(run_badge "$WIN_MAIN")"
assert_contains "$out" 'bg=colour4' 'E outranks I'

# Window without Codex process should output empty.
tmux_cmd new-window -d -t t -n plain "sleep 120"
WIN_PLAIN="$(tmux_cmd display-message -p -t t:plain.0 '#{window_id}')"
out="$(run_badge "$WIN_PLAIN")"
assert_eq "" "$out" 'no codex in window -> empty output'
assert_option_eq "$WIN_PLAIN" "@codex-status-window-badge" "" "window option badge should be cleared for non-codex window"

printf 'PASS: window badge\n'
