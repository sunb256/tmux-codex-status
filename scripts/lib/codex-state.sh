#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./codex-python.sh
source "$SCRIPT_DIR/codex-python.sh"

codex_extract_event_from_notify_arg() {
    codex_python extract-event "${1:-}"
}

codex_map_event_to_state() {
    codex_python map-event "${1:-}"
}

codex_normalize_state() {
    codex_python normalize-state "${1:-}"
}

codex_state_rank() {
    codex_python state-rank "${1:-}"
}
