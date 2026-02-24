#!/usr/bin/env bash

set -euo pipefail

codex_extract_event_from_notify_arg() {
    local raw_arg="${1:-}"
    local event_type=""

    if [ -z "$raw_arg" ]; then
        printf 'agent-turn-complete\n'
        return 0
    fi

    # Codex `notify` currently passes a single JSON payload argument.
    if [[ "$raw_arg" == \{* ]]; then
        if command -v jq >/dev/null 2>&1; then
            event_type="$(printf '%s' "$raw_arg" | jq -r '."type" // empty' 2>/dev/null || true)"
        fi

        if [ -z "$event_type" ]; then
            # Fallback JSON parser for environments without jq.
            event_type="$(printf '%s' "$raw_arg" | sed -n 's/.*"type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
        fi

        if [ -n "$event_type" ]; then
            printf '%s\n' "$event_type"
            return 0
        fi
    fi

    # Backward-compatible path for direct event-name invocation.
    printf '%s\n' "$raw_arg"
}

codex_map_event_to_state() {
    local event="${1:-agent-turn-complete}"
    event="${event,,}"

    case "$event" in
        start|session-start|turn-start|agent-turn-start|working|running)
            printf 'R\n'
            ;;
        permission*|approv*|needs-input|input-required|ask-user|approval-requested)
            printf 'I\n'
            ;;
        error|errored|failed|fail*)
            printf 'E\n'
            ;;
        agent-turn-complete|turn-completed|complete|completed|done|stop|waiting|idle)
            printf 'W\n'
            ;;
        *)
            printf 'W\n'
            ;;
    esac
}

codex_normalize_state() {
    local state="${1:-W}"
    state="${state^^}"

    case "$state" in
        R|W|I|E)
            printf '%s\n' "$state"
            ;;
        *)
            printf 'W\n'
            ;;
    esac
}

codex_state_rank() {
    local state
    state="$(codex_normalize_state "${1:-W}")"

    case "$state" in
        E)
            printf '4\n'
            ;;
        I)
            printf '3\n'
            ;;
        R)
            printf '2\n'
            ;;
        W)
            printf '1\n'
            ;;
        *)
            printf '0\n'
            ;;
    esac
}
