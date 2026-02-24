#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOCK="codex-pane-menu-test-$RANDOM-$$"
OUT_FILE="/tmp/codex-pane-menu-${SOCK}.out"

cleanup() {
    env -u TMUX tmux -L "$SOCK" kill-server >/dev/null 2>&1 || true
    rm -f "$OUT_FILE"
}
trap cleanup EXIT

tmux_cmd() {
    env -u TMUX tmux -L "$SOCK" "$@"
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

tmux_cmd -f /dev/null new-session -d -s t -n main
tmux_cmd new-window -d -t t -n plain "sleep 120"

tmux_cmd set -g @codex-status-icon '🤖'
tmux_cmd set -g @codex-status-separator ' '
tmux_cmd set -g @codex-status-process-name 'codex'

PANE_CODEX="$(tmux_cmd display-message -p -t t:main.0 '#{pane_id}')"

tmux_cmd send-keys -t t:main.0 "exec -a codex sleep 120" C-m
sleep 0.1
tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE_CODEX}_STATE" 'R'

tmux_cmd run-shell "CODEX_STATUS_MENU_DRY_RUN=1 bash '$ROOT_DIR/scripts/codex-pane-menu.sh' > '$OUT_FILE'"
OUT="$(cat "$OUT_FILE" 2>/dev/null || true)"

assert_contains "$OUT" "display-menu" "pane menu should build display-menu command"
assert_contains "$OUT" "run-shell" "pane menu rows should execute run-shell jump action"
assert_contains "$OUT" "🤖\\ R\\ #\\[default\\]\\ St:W0:P0\\ \\[codex\\]" "codex pane row should include one plain space before S/W/P prefix"
assert_contains "$OUT" "\\[codex\\]" "codex pane row should use [command] label format"
assert_contains "$OUT" "#\\[fg=" "codex pane badge should include tmux style start"
assert_contains "$OUT" ",bg=" "codex pane badge should include tmux background color"
assert_contains "$OUT" "#\\[default\\]" "codex pane badge should reset style"
assert_contains "$OUT" "🤖\\ R" "codex pane row should include badge"
assert_contains "$OUT" "🤖\\ R\\ #\\[default\\]" "codex pane badge should keep trailing space before style reset"
assert_contains "$OUT" "\\ St:W1:P0\\ \\[sleep\\]" "non-codex pane row should keep a blank badge-width prefix"
assert_contains "$OUT" "\\[sleep\\]" "non-codex pane row should still be listed"

printf 'PASS: pane menu\n'
