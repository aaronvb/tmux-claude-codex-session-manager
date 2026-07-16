#!/usr/bin/env bash
# Open the session picker in a popup.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

claude_prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
codex_prefix="$(get_tmux_option @codex_session_prefix 'codex-')"
w="$(get_tmux_option_compat @agents_popup_width @claude_popup_width '90%')"
h="$(get_tmux_option_compat @agents_popup_height @claude_popup_height '90%')"

# The client that pressed the key, and the session it is currently attached to.
# Looked up by exact client_name match rather than "first client anywhere that
# looks nested" — with more than one client attached (e.g. a stray popup left
# open in another window), a global scan can grab an unrelated client's session
# and detach it instead of the one this invocation actually cares about.
me="${1:-}"
my_session="$(tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
  awk -v me="$me" '$1 == me { print $2; exit }')"

# open_picker <host>  — show the picker popup on <host>, or on the default client
# when <host> is empty. Returns display-popup's own exit status.
open_picker() {
  if [ -n "$1" ]; then
    tmux display-popup -c "$1" -w "$w" -h "$h" -E "$DIR/picker.sh"
  else
    tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
  fi
}

case "$my_session" in
"$claude_prefix"* | "$codex_prefix"*)
  # We are inside a session popup (any provider's): close it, then reopen the
  # picker on the outer client that originally opened it.
  #
  # display-popup returns to its caller *before* tmux finishes destroying the
  # closing overlay, and a popup opened during that window never receives keyboard
  # input (it hangs). So wait for the popup's client to leave, settle past the
  # teardown, then reopen — retrying a reopen that is rejected mid-teardown (it
  # returns almost instantly, whereas a popup that opened blocks while in use).
  tmux detach-client -s "$my_session"
  for _ in $(seq 1 100); do
    tmux list-clients -F '#{session_name}' 2>/dev/null | grep -qx "$my_session" || break
    sleep 0.05
  done
  host="$(get_tmux_option_compat @agents_parent @claude_parent '')"
  # A stale parent would make every retry fail; fall back to the default client.
  if [ -n "$host" ] && ! tmux list-clients -F '#{client_name}' 2>/dev/null | grep -qx "$host"; then
    host=''
  fi

  sleep 0.1
  rc=0
  for _ in $(seq 1 40); do
    before=$SECONDS
    open_picker "$host"
    rc=$?
    { [ "$rc" -eq 0 ] || [ $((SECONDS - before)) -ge 1 ]; } && break
    sleep 0.1
  done
  exit "$rc"
  ;;
*)
  # Normal case: this client is already the host, with no overlay to race.
  host="$me"
  tmux set-option -g @agents_parent "$host"
  ;;
esac

open_picker "$host"
