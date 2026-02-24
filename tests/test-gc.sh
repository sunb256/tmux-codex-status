#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOCK="codex-status-gc-test-$RANDOM-$$"

cleanup() {
    env -u TMUX tmux -L "$SOCK" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

tmux_cmd() {
    env -u TMUX tmux -L "$SOCK" "$@"
}

assert_empty_env() {
    local key="$1"
    local label="$2"
    local out

    out="$(tmux_cmd show-environment -g "$key" 2>/dev/null || true)"
    case "$out" in
        "-$key"|"")
            ;;
        *)
            printf 'FAIL: %s (actual=%q)\n' "$label" "$out" >&2
            exit 1
            ;;
    esac
}

assert_non_empty_env() {
    local key="$1"
    local label="$2"
    local out

    out="$(tmux_cmd show-environment -g "$key" 2>/dev/null || true)"
    case "$out" in
        "$key="*)
            ;;
        *)
            printf 'FAIL: %s (actual=%q)\n' "$label" "$out" >&2
            exit 1
            ;;
    esac
}

tmux_cmd -f /dev/null new-session -d -s t -n main "sleep 120"
PANE="$(tmux_cmd display-message -p -t t:main.0 '#{pane_id}')"

tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE}_STATE" 'R'
tmux_cmd set-environment -g "TMUX_CODEX_PANE_${PANE}_UPDATED_AT" '1'

tmux_cmd set-environment -g 'TMUX_CODEX_PANE_%999_STATE' 'E'
tmux_cmd set-environment -g 'TMUX_CODEX_PANE_%999_UPDATED_AT' '1'

tmux_cmd run-shell "bash '$ROOT_DIR/scripts/codex-state-gc.sh'"

assert_non_empty_env "TMUX_CODEX_PANE_${PANE}_STATE" 'active pane state should remain'
assert_non_empty_env "TMUX_CODEX_PANE_${PANE}_UPDATED_AT" 'active pane timestamp should remain'
assert_empty_env 'TMUX_CODEX_PANE_%999_STATE' 'stale pane state should be removed'
assert_empty_env 'TMUX_CODEX_PANE_%999_UPDATED_AT' 'stale pane timestamp should be removed'

printf 'PASS: gc\n'
