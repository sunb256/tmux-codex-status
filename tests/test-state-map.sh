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

assert_eq "R" "$(codex_map_event_to_state "start")" "start -> R"
assert_eq "R" "$(codex_map_event_to_state "turn-start")" "turn-start -> R"
assert_eq "R" "$(codex_map_event_to_state "WORKING")" "working(case-insensitive) -> R"
assert_eq "R" "$(codex_map_event_to_state "running")" "running -> R"
assert_eq "R" "$(codex_map_event_to_state "task_started")" "task_started -> R"
assert_eq "K" "$(codex_map_event_to_state "user_message")" "user_message -> keep"
assert_eq "K" "$(codex_map_event_to_state "token_count")" "token_count -> keep"

assert_eq "I" "$(codex_map_event_to_state "permission-request")" "permission* -> I"
assert_eq "I" "$(codex_map_event_to_state "approval-requested")" "approval-requested -> I"
assert_eq "I" "$(codex_map_event_to_state "needs-input")" "needs-input -> I"
assert_eq "I" "$(codex_map_event_to_state "ask-user")" "ask-user -> I"

assert_eq "E" "$(codex_map_event_to_state "error")" "error -> E"
assert_eq "E" "$(codex_map_event_to_state "fail-hard")" "fail* -> E"
assert_eq "E" "$(codex_map_event_to_state "errored")" "errored -> E"

assert_eq "W" "$(codex_map_event_to_state "agent-turn-complete")" "agent-turn-complete -> W"
assert_eq "W" "$(codex_map_event_to_state "turn-completed")" "turn-completed -> W"
assert_eq "W" "$(codex_map_event_to_state "task_complete")" "task_complete -> W"
assert_eq "W" "$(codex_map_event_to_state "turn_aborted")" "turn_aborted -> W"
assert_eq "W" "$(codex_map_event_to_state "done")" "done -> W"
assert_eq "W" "$(codex_map_event_to_state "unknown-event")" "unknown -> W"

assert_eq "agent-turn-complete" "$(codex_extract_event_from_notify_arg '{"type":"agent-turn-complete","message":"done"}')" "extract type from json"
assert_eq "approval-requested" "$(codex_extract_event_from_notify_arg '{"type":"approval-requested"}')" "extract approval-requested from json"
assert_eq "task_started" "$(codex_extract_event_from_notify_arg '{"type":"event_msg","payload":{"type":"task_started"}}')" "extract payload.type from event_msg json"
assert_eq "working" "$(codex_extract_event_from_notify_arg "working")" "extract passthrough plain event"

printf 'PASS: state map\n'
