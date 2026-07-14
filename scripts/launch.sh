#!/usr/bin/env bash
# Launch (or re-attach to) a provider session for a directory, shown in a popup.
# Args: <provider> <dir> [origin-window-id]
# (dir/window are expanded by run-shell in the binding)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

provider="${1:-claude}"
path="${2:-$PWD}"
window="${3:-}"

case "$provider" in
claude)
  def_cmd='claude'
  def_prefix='claude-'
  ;;
codex)
  def_cmd='codex'
  def_prefix='codex-'
  ;;
*)
  tmux display-message "tmux-claude-codex-session-manager: unknown provider '$provider'"
  exit 0
  ;;
esac

prefix="$(get_tmux_option "@${provider}_session_prefix" "$def_prefix")"
cmd="$(get_tmux_option "@${provider}_command" "$def_cmd")"
args="$(get_tmux_option "@${provider}_args" '')"
[ -n "$args" ] && cmd="$cmd $args"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

# Refuse before creating anything: a popup attached to an instantly-dead
# session is just a flicker with no explanation.
first="${cmd%% *}"
if ! command -v "$first" >/dev/null 2>&1; then
  tmux display-message "tmux-claude-codex-session-manager: '$first' not found on PATH"
  exit 0
fi

session="${prefix}$(session_hash "$path")"

# Already inside any provider's session popup (not just this provider's):
# opening another popup here would nest them.
current="$(tmux display-message -p '#S')"
claude_prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
codex_prefix="$(get_tmux_option @codex_session_prefix 'codex-')"
case "$current" in
"$claude_prefix"* | "$codex_prefix"*)
  tmux display-message '🫪 Popup window already open'
  exit 0
  ;;
esac

tmux has-session -t "$session" 2>/dev/null ||
  tmux new-session -d -s "$session" -c "$path" "$cmd"

# Record which window launched it, so the picker can jump back here later.
# Kept as @claude_origin for every provider — the picker reads one name.
[ -n "$window" ] && tmux set-option -t "$session" @claude_origin "$window"

tmux display-popup -w "$w" -h "$h" -E "tmux attach-session -t $session"
