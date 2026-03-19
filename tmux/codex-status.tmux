# tmux-codex-status integration
# Set @codex-status-dir in ~/.tmux.conf before sourcing this file when using a custom path.

if -F '#{==:#{@codex-status-dir},}' 'set -g @codex-status-dir "$HOME/.tmux/plugins/tmux-codex-status"'
if -F '#{==:#{@codex-status-icon},}' 'set -g @codex-status-icon "🤖"'
if -F '#{==:#{@codex-status-process-name},}' 'set -g @codex-status-process-name "codex"'
if -F '#{==:#{@codex-status-separator},}' 'set -g @codex-status-separator " "'
if -F '#{==:#{@codex-status-sessions-dir},}' 'set -g @codex-status-sessions-dir "$HOME/.codex/sessions"'
if -F '#{==:#{@codex-status-session-lookback-minutes},}' 'set -g @codex-status-session-lookback-minutes "240"'
if -F '#{==:#{@codex-status-session-scan-limit},}' 'set -g @codex-status-session-scan-limit "40"'
if -F '#{==:#{@codex-status-session-cache-seconds},}' 'set -g @codex-status-session-cache-seconds "2"'
if -F '#{==:#{@codex-status-stale-r-grace-seconds},}' 'set -g @codex-status-stale-r-grace-seconds "5"'

if -F '#{==:#{@codex-status-color-r},}' 'set -g @codex-status-color-r "colour208"'
if -F '#{==:#{@codex-status-color-w},}' 'set -g @codex-status-color-w "colour255"'
if -F '#{==:#{@codex-status-color-i},}' 'set -g @codex-status-color-i "colour226"'
if -F '#{==:#{@codex-status-color-e},}' 'set -g @codex-status-color-e "colour196"'

if -F '#{==:#{@codex-status-bg-r},}' 'set -g @codex-status-bg-r "colour88"'
if -F '#{==:#{@codex-status-bg-w},}' 'set -g @codex-status-bg-w "colour15"'
if -F '#{==:#{@codex-status-bg-i},}' 'set -g @codex-status-bg-i "colour15"'
if -F '#{==:#{@codex-status-bg-e},}' 'set -g @codex-status-bg-e "colour196"'

if -F '#{==:#{@codex-status-fg-r},}' 'set -g @codex-status-fg-r "colour255"'
if -F '#{==:#{@codex-status-fg-w},}' 'set -g @codex-status-fg-w "colour16"'
if -F '#{==:#{@codex-status-fg-i},}' 'set -g @codex-status-fg-i "colour16"'
if -F '#{==:#{@codex-status-fg-e},}' 'set -g @codex-status-fg-e "colour255"'

set -g status-interval 1
set -g window-status-format '#(bash "#{@codex-status-dir}/scripts/codex-window-badge.sh" "#{window_id}")#I:#W'
set -g window-status-current-format '#(bash "#{@codex-status-dir}/scripts/codex-window-badge.sh" "#{window_id}")#[fg=colour255,bg=colour27,bold]#I:#W#[default]'
unbind-key -T prefix w
bind-key -T prefix w run-shell "bash \"#{@codex-status-dir}/scripts/codex-pane-menu.sh\""
