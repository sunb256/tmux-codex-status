#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/codex-state.sh
source "$ROOT_DIR/scripts/lib/codex-state.sh"

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    if [ "$expected" != "$actual" ]; then
        printf 'FAIL: %s (expected=%s actual=%s)\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_eq "R" "$(codex_normalize_state "r")" "normalize r"
assert_eq "I" "$(codex_normalize_state "I")" "normalize I"
assert_eq "W" "$(codex_normalize_state "")" "normalize empty"
assert_eq "W" "$(codex_normalize_state "invalid")" "normalize invalid"

assert_eq "4" "$(codex_state_rank "E")" "rank E"
assert_eq "3" "$(codex_state_rank "I")" "rank I"
assert_eq "2" "$(codex_state_rank "R")" "rank R"
assert_eq "1" "$(codex_state_rank "W")" "rank W"
assert_eq "1" "$(codex_state_rank "x")" "rank invalid -> W"

printf 'PASS: state rank\n'
