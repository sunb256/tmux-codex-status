#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REFRESH_SCRIPT="$SCRIPT_DIR/codex-refresh-pane-badges.sh"
SELECT_SCRIPT="$SCRIPT_DIR/codex-select-pane.sh"

if ! command -v tmux >/dev/null 2>&1; then
    exit 0
fi
if ! tmux list-sessions >/dev/null 2>&1; then
    exit 0
fi

tmux_option_is_set() {
    local option="$1"
    local raw
    raw="$(tmux show-option -gq "$option" 2>/dev/null || true)"
    [ -n "$raw" ]
}

tmux_get_option_or_default() {
    local option="$1"
    local default_value="$2"

    if tmux_option_is_set "$option"; then
        tmux show-option -gqv "$option"
    else
        printf '%s\n' "$default_value"
    fi
}

state_bg_color() {
    local state="$1"

    case "$state" in
        R)
            tmux_get_option_or_default "@codex-status-bg-r" "$(tmux_get_option_or_default "@codex-status-color-r" "colour208")"
            ;;
        W)
            tmux_get_option_or_default "@codex-status-bg-w" "$(tmux_get_option_or_default "@codex-status-color-w" "colour240")"
            ;;
        I)
            tmux_get_option_or_default "@codex-status-bg-i" "$(tmux_get_option_or_default "@codex-status-color-i" "colour226")"
            ;;
        E)
            tmux_get_option_or_default "@codex-status-bg-e" "$(tmux_get_option_or_default "@codex-status-color-e" "colour196")"
            ;;
        *)
            tmux_get_option_or_default "@codex-status-bg-w" "$(tmux_get_option_or_default "@codex-status-color-w" "colour240")"
            ;;
    esac
}

state_fg_color() {
    local state="$1"

    case "$state" in
        R)
            tmux_get_option_or_default "@codex-status-fg-r" "colour16"
            ;;
        W)
            tmux_get_option_or_default "@codex-status-fg-w" "colour16"
            ;;
        I)
            tmux_get_option_or_default "@codex-status-fg-i" "colour16"
            ;;
        E)
            tmux_get_option_or_default "@codex-status-fg-e" "colour255"
            ;;
        *)
            tmux_get_option_or_default "@codex-status-fg-w" "colour255"
            ;;
    esac
}

styled_pane_badge() {
    local pane_badge="${1:-}"
    local state=""
    local bg_color fg_color

    case "$pane_badge" in
        *R) state="R" ;;
        *W) state="W" ;;
        *I) state="I" ;;
        *E) state="E" ;;
        *)
            printf '%s\n' "$pane_badge"
            return 0
            ;;
    esac

    bg_color="$(state_bg_color "$state")"
    fg_color="$(state_fg_color "$state")"
    if [ "$fg_color" = "$bg_color" ]; then
        if [ "$bg_color" = "colour16" ]; then
            fg_color="colour255"
        else
            fg_color="colour16"
        fi
    fi

    printf '#[fg=%s,bg=%s]%s #[default]\n' "$fg_color" "$bg_color" "$pane_badge"
}

menu_key_for_index() {
    local i="$1"

    if [ "$i" -lt 9 ]; then
        printf '%s' "$((i + 1))"
        return 0
    fi
    if [ "$i" -lt 35 ]; then
        printf "\\$(printf '%03o' "$((97 + i - 9))")"
        return 0
    fi
    printf ''
}

bash "$REFRESH_SCRIPT" >/dev/null 2>&1 || true

TITLE="$(tmux show-option -gqv @codex-status-menu-title 2>/dev/null || true)"
if [ -z "$TITLE" ]; then
    TITLE="Codex Panes"
fi
ICON="$(tmux_get_option_or_default "@codex-status-icon" "🤖")"
SEPARATOR="$(tmux_get_option_or_default "@codex-status-separator" " ")"

if [ -n "$ICON" ]; then
    BADGE_TEMPLATE="${ICON}${SEPARATOR}W "
else
    BADGE_TEMPLATE="W "
fi
BADGE_PLACEHOLDER_WIDTH="${#BADGE_TEMPLATE}"
# Emoji/non-ASCII icons are commonly rendered double-width in terminals.
if [ -n "$ICON" ] && [[ "$ICON" =~ [^[:ascii:]] ]]; then
    BADGE_PLACEHOLDER_WIDTH="$((BADGE_PLACEHOLDER_WIDTH + 1))"
fi
# Add one more blank for non-badge rows to keep visual alignment in display-menu.
BADGE_PLACEHOLDER_WIDTH="$((BADGE_PLACEHOLDER_WIDTH + 1))"
BADGE_PLACEHOLDER="$(printf '%*s' "$BADGE_PLACEHOLDER_WIDTH" '')"

declare -a MENU_CMD=()
MENU_CMD=(tmux display-menu -T "$TITLE" -x C -y C)

index=0
while IFS=$'\t' read -r session_name window_index pane_index pane_id pane_label pane_badge; do
    [ -n "$pane_id" ] || continue

    if [ -n "$pane_badge" ]; then
        badge_prefix="$(styled_pane_badge "$pane_badge")"
        label="${badge_prefix} S${session_name}:W${window_index}:P${pane_index} ${pane_label}"
    else
        label="${BADGE_PLACEHOLDER} S${session_name}:W${window_index}:P${pane_index} ${pane_label}"
    fi

    label="${label//$'\t'/ }"
    label="${label//$'\n'/ }"

    key="$(menu_key_for_index "$index")"
    index="$((index + 1))"
    action="run-shell \"bash $SELECT_SCRIPT $session_name $window_index $pane_index\""

    MENU_CMD+=("$label" "$key" "$action")
done < <(tmux list-panes -a -F '#{session_name}	#{window_index}	#{pane_index}	#{pane_id}	[#{pane_current_command}]#{b:pane_current_path}	#{@codex-status-pane-badge}' 2>/dev/null || true)

if [ "$index" -eq 0 ]; then
    MENU_CMD+=("No panes" "" "")
fi

if [ "${CODEX_STATUS_MENU_DRY_RUN:-}" = "1" ]; then
    printf '%q ' "${MENU_CMD[@]}"
    printf '\n'
    exit 0
fi

"${MENU_CMD[@]}"
