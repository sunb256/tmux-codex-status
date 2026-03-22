# tmux-codex-status

Show Codex CLI state in tmux window list (`window-status-format`) as a colored `🤖` badge.
State (`R/W/I/E`) is encoded by badge color only.

If a window has no Codex process, nothing is shown.
The badge is placed at the beginning of each window item.

## Files

- `tmux/codex-status.tmux`: tmux integration snippet.
- `src/tmux_codex_status/*.py`: Python implementation.

## Setup

1. Point Codex notify to the Python entry in `~/.codex/config.toml`:

```toml
notify = ["python3", "<plugin-path>/tmux-codex-status/src/tmux_codex_status/cli.py", "notify"]
```

Or use the bundled wrapper script:

```toml
notify = ["bash", "<plugin-path>/tmux-codex-status/scripts/codex-notify.sh"]
```

2. Load tmux settings from `~/.tmux.conf`:

```tmux
set -g @codex-status-dir '<plugin-path>/tmux-codex-status'
# optional: override python executable
# set -g @codex-status-python "python3"
source-file '<plugin-path>/tmux-codex-status/tmux/codex-status.tmux' && tmux refresh-client -S
```

3. Reload tmux:

```bash
tmux source-file ~/.tmux.conf
```

## tmux options

User-facing options:

- `@codex-status-python` (default `python3`)
- `@codex-status-icon` (default `🤖`)
- `@codex-status-process-name` (default `codex`)
- `@codex-status-separator` (default single space)
- `@codex-status-color-r` (default `colour208`)
- `@codex-status-color-w` (default `colour255`)
- `@codex-status-color-i` (default `colour226`)
- `@codex-status-color-e` (default `colour196`)
- `@codex-status-bg-r` (default `colour88`)
- `@codex-status-bg-w` (default `colour15`)
- `@codex-status-bg-i` (default `colour15`)
- `@codex-status-bg-e` (default `colour196`)
- `@codex-status-fg-r` (default `colour255`)
- `@codex-status-fg-w` (default `colour16`)
- `@codex-status-fg-i` (default `colour16`)
- `@codex-status-fg-e` (default `colour255`)
- `@codex-status-sessions-dir` (default `$HOME/.codex/sessions`)
- `@codex-status-session-lookback-minutes` (default `240`)
- `@codex-status-session-scan-limit` (default `40`)
- `@codex-status-session-cache-seconds` (default `2`)
- `@codex-status-stale-r-grace-seconds` (default `5`)
- `@codex-status-menu-title` (default `Codex Panes`)

Internal cache/options (normally no need to edit):

- `@codex-status-window-badge` (window-local cached plain badge text)
- `@codex-status-pane-badge` (pane-local cached plain badge text for menu rows)

Rendering note:

- Badge is rendered as a background-colored block for better visibility in `window-status-format`.
- In the status bar, the badge is rendered before `#I:#W` with no extra separator spaces.
- The same state colors are used in `prefix+w` menu badges (`🤖`), while non-badge text remains unchanged.
- Legacy `@codex-status-color-*` values are still read as fallback background colors.
- If foreground and background resolve to the same color, foreground is auto-adjusted for contrast.

Color tuning example:

```tmux
# Run: wine background + white text
set -g @codex-status-bg-r "colour88"
set -g @codex-status-fg-r "colour255"

# Wait: light gray background + black text
set -g @codex-status-bg-w "colour252"
set -g @codex-status-fg-w "colour16"

# Input: white background + black text
set -g @codex-status-bg-i "colour15"
set -g @codex-status-fg-i "colour16"
```

`prefix+w` note:

- The plugin rebinds `prefix+w` to a Python command that opens a `display-menu` pane list.
- Each row starts with a badge column, then `S<session>:W<window>:P<pane> [#{pane_current_command}]#{b:pane_current_path}`.
- Codex panes show a colored `🤖` badge in that leading column.
- There is no separator space between the badge and `S<session>...` on Codex rows.
- Non-Codex panes show no badge and use blank padding in the leading badge column so text stays aligned with Codex rows.
- In this menu, only the badge (`🤖`) is colorized using the same `@codex-status-bg-*` and `@codex-status-fg-*` options.
- If your terminal font renders emoji width differently, adjust `@codex-status-icon` (or use an ASCII icon) for perfect alignment.
- Selecting a row jumps to that pane.
- `R` in this menu is inferred from recent Codex session logs in the same way as the status bar.

## State mapping

Codex event -> state:

- `start|session-start|turn-start|agent-turn-start|task-start|task-started|task_started|working|running` -> `R`
- `user-message|user_message|agent-message|agent_message|token-count|token_count` -> keep previous state
- `permission*|approv*|needs-input|input-required|ask-user|approval-requested` -> `I`
- `error|errored|failed|fail*` -> `E`
- `task-complete|task_complete|turn-aborted|turn_aborted|agent-turn-complete|turn-completed|complete|completed|done|stop|waiting|idle|other` -> `W`

`notify` payload handling:

- The script accepts both plain event strings and Codex JSON payloads.
- For JSON payloads, it reads `.type` and maps that value to a state.

Note on current Codex behavior (as observed with Codex CLI `0.104.0` on February 22, 2026):

- `notify` commonly emits `{"type":"agent-turn-complete", ...}`.
- On `notify`, this plugin remembers a recent session log file per `cwd + session:window`.
- It infers `R` only when both `cwd` and `session:window` match and that remembered file's latest task event is `task_started`.
- If no remembered file exists and multiple recent session logs share the same `cwd`, inference is treated as ambiguous and fallback remains `W`.
- If logs are unavailable or no running task is detected, fallback remains `W`.
- If `R` is stale (no newer pane-state update after the grace period), a decisive session event (`task_complete|turn_aborted`) can downgrade it back to `W`.

Window aggregation priority:

`E > I > R > W`

## Tests

```bash
uv run pytest
```
