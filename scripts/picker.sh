#!/usr/bin/env bash
# Interactive picker for running agents, across every enabled provider.
#
#   picker.sh           fzf picker; on enter, jumps to the chosen agent.
#   picker.sh --list    print the rows only (used by fzf's ctrl-x reload).
#
# Rows come from agents.sh, which pairs each running agent with the tmux pane it
# occupies and tags it with its provider ([cc] Claude, [cx] Codex). Two kinds of
# row jump differently:
#   dedicated  an agent in a session this plugin launched (claude-*/codex-*) —
#              resumed in the popup, over the window it was launched from.
#   loose      an agent running in any other pane — focused in place.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

[ "${1:-}" = '--list' ] && exec "$DIR/agents.sh"

command -v fzf >/dev/null 2>&1 || {
  tmux display-message 'tmux-claude-codex-session-manager: fzf is required for the picker'
  exit 0
}

# Beyond fzf, require only the tools of enabled providers: jq+claude for
# Claude, jq for Codex. A provider missing its tool is skipped by agents.sh,
# not fatal — the picker must work on a Codex-only machine (and vice versa).
usable=''
if command -v jq >/dev/null 2>&1; then
  claude_cmd="$(get_tmux_option @claude_command 'claude')"
  command -v "${claude_cmd%% *}" >/dev/null 2>&1 && usable=1
  codex_cmd="$(get_tmux_option @codex_command 'codex')"
  [ "$(get_tmux_option @codex_enabled 'auto')" != 'off' ] &&
    command -v "${codex_cmd%% *}" >/dev/null 2>&1 && usable=1
fi
[ -n "$usable" ] || {
  tmux display-message 'tmux-claude-codex-session-manager: the picker needs jq plus claude or codex'
  exit 0
}

self="$DIR/picker.sh"
export FZF_DEFAULT_OPTS=''
export CLAUDE_PICKER="$self"

# Arbitrary user fzf options (e.g. custom --bind or --preview-window)
extra_opts=()
fzf_options="$(get_tmux_option @claude_fzf_options '')"
[ -n "$fzf_options" ] && eval "extra_opts=($fzf_options)"

# ctrl-x kills the agent process itself — the pid on the row is Claude's
# self-reported pid or Codex's pane-resolved pid, so one binding serves both.
# A dedicated session dies with its last window, while a loose pane keeps the
# shell that hosted it. The reload waits a beat so the source has caught up
# (Claude's supervisor drops the agent; Codex's state file is swept).
sel=$("$DIR/agents.sh" | fzf --ansi --delimiter='\t' --with-nth=5,6,7,8,9 \
  --reverse --cycle --header='Agents · enter: jump · ctrl-x: kill' \
  --preview='tmux capture-pane -ept {2}' --preview-window='up,70%,follow' \
  --bind="ctrl-x:execute-silent(kill {3})+reload(sleep 0.3; $self --list)" \
  ${extra_opts[@]+"${extra_opts[@]}"})

[ -z "$sel" ] && exit 0
pane=$(printf '%s' "$sel" | cut -f2)
kind=$(printf '%s' "$sel" | cut -f4)

parent=$(tmux show-options -gqv @claude_parent 2>/dev/null)
session=$(tmux display-message -p -t "$pane" '#{session_name}' 2>/dev/null)

if [ "$kind" = loose ]; then
  # Focus the pane in place on the outer client. This popup closes on its own
  # when the script exits.
  if [ -n "$parent" ]; then
    tmux switch-client -c "$parent" -t "$session" 2>/dev/null
  else
    tmux switch-client -t "$session" 2>/dev/null
  fi
  tmux select-window -t "$pane" 2>/dev/null
  tmux select-pane -t "$pane" 2>/dev/null
  exit 0
fi

# Move the parent client to the window the session was launched from (best-effort),
# focus the chosen agent's own window inside that session, then resume it in THIS
# popup over the top. Falls back to resuming over the current window when
# origin/parent are unknown.
origin=$(tmux show-options -qv -t "$session" @claude_origin 2>/dev/null)
[ -n "$origin" ] && [ -n "$parent" ] &&
  tmux switch-client -c "$parent" -t "$origin" 2>/dev/null

tmux select-window -t "$pane" 2>/dev/null
tmux select-pane -t "$pane" 2>/dev/null
tmux attach-session -t "$session"
