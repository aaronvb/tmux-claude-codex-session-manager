#!/usr/bin/env bash
# Agents session manager for Claude Code and Codex
#
# List, monitor status, and jump across nested Claude Code and Codex sessions
# from a single popup. tpm runs this file as an executable on tmux startup; it
# reads user options (with sensible defaults) and installs the key bindings.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh"

launch_key="$(get_tmux_option @claude_launch_key 'y')"
codex_launch_key="$(get_tmux_option @codex_launch_key 'o')"
picker_key="$(get_tmux_option_compat @agents_picker_key @claude_list_key 'u')"
codex_enabled="$(get_tmux_option @codex_enabled 'auto')"

# Launch (or re-attach to) a provider session for the current pane's directory.
# #{pane_current_path} / #{window_id} are expanded by run-shell before the args
# reach the script.
tmux bind-key "$launch_key" \
  run-shell "$CURRENT_DIR/scripts/launch.sh claude '#{q:pane_current_path}' '#{q:window_id}'"

# 'off' skips the binding entirely; 'auto' binds it even without codex on PATH,
# so the key explains itself (launch.sh shows the missing-command message)
# instead of silently doing nothing.
if [ "$codex_enabled" != 'off' ]; then
  tmux bind-key "$codex_launch_key" \
    run-shell "$CURRENT_DIR/scripts/launch.sh codex '#{q:pane_current_path}' '#{q:window_id}'"
fi

# Open the unified picker. When pressed from inside a session popup, list.sh
# closes that popup first so the picker opens full-size on the outer client.
tmux bind-key "$picker_key" \
  run-shell "$CURRENT_DIR/scripts/list.sh '#{q:client_name}'"
