#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOCK="codex-pane-badge-test-$RANDOM-$$"
SESSIONS_DIR="/tmp/codex-pane-badge-sessions-${SOCK}"

cleanup() {
    env -u TMUX tmux -L "$SOCK" kill-server >/dev/null 2>&1 || true
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

pane_badge() {
    local pane_id="$1"
    tmux_cmd show-options -pqv -t "$pane_id" "@codex-status-pane-badge" 2>/dev/null || true
}

run_refresh() {
    tmux_cmd run-shell "bash '$ROOT_DIR/scripts/codex-refresh-pane-badges.sh'"
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

set_cwd_window_session_file() {
    local cwd="$1"
    local window_ref="$2"
    local session_file="$3"
    local window_suffix

    window_suffix="$(printf '%s\t%s' "$cwd" "$window_ref" | cksum | awk '{print $1}')"
    tmux_cmd set-environment -g "TMUX_CODEX_CWD_${window_suffix}_SESSION_FILE" "$session_file"
}

tmux_cmd -f /dev/null new-session -d -s t -n main
tmux_cmd new-window -d -t t -n plain "sleep 120"

tmux_cmd set -g @codex-status-icon '🤖'
tmux_cmd set -g @codex-status-separator ' '
tmux_cmd set -g @codex-status-process-name 'codex'
tmux_cmd set -g @codex-status-sessions-dir "$SESSIONS_DIR"
tmux_cmd set -g @codex-status-session-cache-seconds '0'
tmux_cmd set -g @codex-status-stale-r-grace-seconds '5'
mkdir -p "$SESSIONS_DIR"

PANE_CODEX="$(tmux_cmd display-message -p -t t:main.0 '#{pane_id}')"
PANE_PLAIN="$(tmux_cmd display-message -p -t t:plain.0 '#{pane_id}')"
PANE_CODEX_CWD="$(tmux_cmd display-message -p -t t:main.0 '#{pane_current_path}')"
WIN_MAIN_REF="$(tmux_cmd display-message -p -t t:main.0 '#{session_name}:#{window_index}')"

tmux_cmd send-keys -t t:main.0 "exec -a codex sleep 120" C-m
sleep 0.1

tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE_CODEX}_STATE" 'R'
run_refresh

assert_eq "🤖 R" "$(pane_badge "$PANE_CODEX")" "codex pane should get badge"
assert_eq "" "$(pane_badge "$PANE_PLAIN")" "non-codex pane should stay empty"

tmux_cmd new-window -d -t t -n samecwd -c "$PANE_CODEX_CWD"
PANE_SAME="$(tmux_cmd display-message -p -t t:samecwd.0 '#{pane_id}')"
WIN_SAME_REF="$(tmux_cmd display-message -p -t t:samecwd.0 '#{session_name}:#{window_index}')"
tmux_cmd send-keys -t t:samecwd.0 "exec -a codex sleep 120" C-m
sleep 0.1

SESSION_FILE="$SESSIONS_DIR/test-running.jsonl"
write_fake_session "$SESSION_FILE" "$PANE_CODEX_CWD" "task_started"
set_cwd_window_ref "$PANE_CODEX_CWD" "$WIN_MAIN_REF"
tmux_cmd set-environment -gu "TMUX_CODEX_PANE_${PANE_CODEX}_STATE"
tmux_cmd set-environment -gu "TMUX_CODEX_PANE_${PANE_SAME}_STATE"
run_refresh
assert_eq "🤖 R" "$(pane_badge "$PANE_CODEX")" "matching window should infer R from session log"
assert_eq "🤖 W" "$(pane_badge "$PANE_SAME")" "different window with same cwd should stay W"

SESSION_MAIN_ONLY="$SESSIONS_DIR/test-main-only.jsonl"
write_fake_session "$SESSION_MAIN_ONLY" "$PANE_CODEX_CWD" "task_started"
set_cwd_window_ref "$PANE_CODEX_CWD" "$WIN_SAME_REF"
set_cwd_window_session_file "$PANE_CODEX_CWD" "$WIN_MAIN_REF" "$SESSION_MAIN_ONLY"
tmux_cmd set-environment -gu "TMUX_CODEX_PANE_${PANE_CODEX}_STATE"
run_refresh
assert_eq "🤖 R" "$(pane_badge "$PANE_CODEX")" "window-specific pinned session should infer R even when cwd-window ref points elsewhere"

SESSION_MAIN_PIN="$SESSIONS_DIR/test-main-pinned.jsonl"
SESSION_OTHER_NEW="$SESSIONS_DIR/test-other-newer.jsonl"
write_fake_session "$SESSION_MAIN_PIN" "$PANE_CODEX_CWD" "task_started"
sleep 0.1
write_fake_session "$SESSION_OTHER_NEW" "$PANE_CODEX_CWD" "task_complete"
set_cwd_window_ref "$PANE_CODEX_CWD" "$WIN_MAIN_REF"
set_cwd_window_session_file "$PANE_CODEX_CWD" "$WIN_MAIN_REF" "$SESSION_MAIN_PIN"
run_refresh
assert_eq "🤖 R" "$(pane_badge "$PANE_CODEX")" "pinned session file should win over newer same-cwd session logs"

write_fake_session "$SESSION_MAIN_PIN" "$PANE_CODEX_CWD" "task_complete"
tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE_CODEX}_STATE" 'R'
tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE_CODEX}_UPDATED_AT" "$(( $(date +%s) - 30 ))"
set_cwd_window_session_file "$PANE_CODEX_CWD" "$WIN_MAIN_REF" "$SESSION_MAIN_PIN"
run_refresh
assert_eq "🤖 W" "$(pane_badge "$PANE_CODEX")" "stale R should fall back to W when pinned session is task_complete"

tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE_CODEX}_STATE" 'I'
run_refresh
assert_eq "🤖 I" "$(pane_badge "$PANE_CODEX")" "badge should follow latest pane state"

tmux_cmd send-keys -t "$PANE_CODEX" C-c
sleep 0.1
run_refresh
assert_eq "" "$(pane_badge "$PANE_CODEX")" "badge should clear after codex process exits"

printf 'PASS: pane badge\n'
