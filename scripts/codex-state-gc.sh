#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/codex-python.sh
source "$SCRIPT_DIR/lib/codex-python.sh"

codex_python state-gc
