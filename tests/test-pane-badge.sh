#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOCK="codex-pane-badge-test-$RANDOM-$$"

cleanup() {
    env -u TMUX tmux -L "$SOCK" kill-server >/dev/null 2>&1 || true
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

tmux_cmd -f /dev/null new-session -d -s t -n main
tmux_cmd new-window -d -t t -n plain "sleep 120"

tmux_cmd set -g @codex-status-icon '🤖'
tmux_cmd set -g @codex-status-separator ' '
tmux_cmd set -g @codex-status-process-name 'codex'

PANE_CODEX="$(tmux_cmd display-message -p -t t:main.0 '#{pane_id}')"
PANE_PLAIN="$(tmux_cmd display-message -p -t t:plain.0 '#{pane_id}')"

tmux_cmd send-keys -t t:main.0 "exec -a codex sleep 120" C-m
sleep 0.1

tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE_CODEX}_STATE" 'R'
run_refresh

assert_eq "🤖 R" "$(pane_badge "$PANE_CODEX")" "codex pane should get badge"
assert_eq "" "$(pane_badge "$PANE_PLAIN")" "non-codex pane should stay empty"

tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE_CODEX}_STATE" 'I'
run_refresh
assert_eq "🤖 I" "$(pane_badge "$PANE_CODEX")" "badge should follow latest pane state"

tmux_cmd send-keys -t "$PANE_CODEX" C-c
sleep 0.1
run_refresh
assert_eq "" "$(pane_badge "$PANE_CODEX")" "badge should clear after codex process exits"

printf 'PASS: pane badge\n'
