#!/usr/bin/env bash
# Shared render pipeline: normalized provider rows in, ranked picker rows out.
#
#   In  (stdin): provider \t id \t status \t cwd \t transcript_path \t locator
#   Out:         rank \t pane_id \t pid \t kind \t tag \t icon \t age \t loc \t path
#
# Output fields are pinned so the picker's indexes cannot drift: 1-4 are hidden
# plumbing (sort rank, jump pane, kill pid, jump kind), 5-9 are displayed
# (provider tag claude/codex, padded and colored, status icon, age, location,
# path). fzf keeps using
# {2} for the preview pane, {3} for the kill pid, --with-nth=5,6,7,8,9.
#
# The locator is polymorphic — a pid (Claude) or a pane id (Codex), whichever
# the tool knows natively — and is resolved against one ps + list-panes
# snapshot: pid -> tty -> pane, or pane -> tty -> pid. A pane locator resolves
# to the pid on that pane's tty whose command basename matches the first word
# of the provider's @<provider>_command — several pids share the tty (the
# shell, MCP-server children), and this pid is also the ctrl-x kill target.
# Rows whose locator does not resolve to a live process in a pane are dropped.
#
# Identity is the agent process, not the tmux session. The pid/tty/pane join is
# what lets several agents in one project (same cwd, different windows) each
# get a row of their own. Total cost is 3 subprocesses however many rows exist.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

rows="$(cat)"
[ -n "$rows" ] || exit 0

# Resolved out here because only `stat`, outside awk, can read an mtime. Codex
# rows carry their transcript path (the hook records it); Claude rows leave the
# field empty and fall back to the claude_transcript_mtime glob. awk extracts
# the two fields first because `read` with IFS=$'\t' collapses the consecutive
# tabs around an empty field; with the possibly-empty field last, read is safe.
mtimes="$(printf '%s\n' "$rows" | awk -F'\t' '$2 != "" { print $2 "\t" $5 }' |
  while IFS=$'\t' read -r id transcript; do
    if [ -n "$transcript" ]; then
      printf 'M\t%s\t%s\n' "$id" "$(file_mtime "$transcript")"
    else
      printf 'M\t%s\t%s\n' "$id" "$(claude_transcript_mtime "$id")"
    fi
  done)"

claude_cmd="$(get_tmux_option @claude_command 'claude')"
codex_cmd="$(get_tmux_option @codex_command 'codex')"
claude_base="${claude_cmd%% *}" claude_base="${claude_base##*/}"
codex_base="${codex_cmd%% *}" codex_base="${codex_base##*/}"

# Four tagged streams into one awk: pid/tty/comm, tty/pane, id/last-activity,
# and the provider rows themselves.
{
  ps -Ao pid=,tty=,comm= 2>/dev/null | awk '{
    pid = $1; tty = $2
    sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "")
    print "P\t" pid "\t" tty "\t" $0
  }'
  tmux list-panes -a -F $'T\t#{pane_tty}\t#{pane_id}\t#{session_name}\t#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null
  printf '%s\n' "$mtimes"
  printf '%s\n' "$rows" | sed $'s/^/A\t/'
} | awk -F'\t' -v now="$(date +%s)" -v home="$HOME" \
  -v prefix_claude="$(get_tmux_option @claude_session_prefix 'claude-')" \
  -v prefix_codex="$(get_tmux_option @codex_session_prefix 'codex-')" \
  -v cmd_claude="$claude_base" -v cmd_codex="$codex_base" '
  $1 == "P" {
    tty_of[$2] = $3
    base = $4; sub(/.*\//, "", base)
    # First (lowest) pid wins: the pane shell spawns the agent before the agent
    # spawns any same-named children, and ps lists pids ascending.
    if (!(($3, base) in pid_on)) pid_on[$3, base] = $2
    next
  }
  $1 == "T" {
    sub(/^\/dev\//, "", $2)
    pane[$2] = $3; sess[$2] = $4; loc[$2] = $5; tty_of_pane[$3] = $2
    next
  }
  $1 == "M" { seen_at[$2] = $3; next }
  $1 == "A" {
    provider = $2; id = $3; status = $4; path = $5; locator = $7

    if (locator ~ /^%/) {                    # pane locator: pane -> tty -> pid
      tty = tty_of_pane[locator]
      if (tty == "") next                    # recorded pane no longer exists
      cb = (provider == "claude") ? cmd_claude : cmd_codex
      pid = pid_on[tty, cb]
      if (pid == "") next                    # no live agent process on the pane
      p = locator
    } else {                                 # pid locator: pid -> tty -> pane
      tty = tty_of[locator]
      if (tty == "" || !(tty in pane)) next  # this agent is not inside tmux
      p = pane[tty]; pid = locator
    }

    if      (status == "waiting") { icon = "\033[33m●\033[0m waiting"; rank = 0 }  # yellow - needs input
    else if (status == "idle")    { icon = "\033[32m●\033[0m idle   "; rank = 1 }  # green  - done, your turn
    else if (status == "busy")    { icon = "\033[31m●\033[0m working"; rank = 3 }  # red    - busy, leave it
    else                          { icon = "\033[90m●\033[0m   ?    "; rank = 2 }  # grey   - unrecognised status

    age = (seen_at[id] != "") ? int((now - seen_at[id]) / 60) "m" : "-"
    prefix = (provider == "claude") ? prefix_claude : prefix_codex
    kind = (index(sess[tty], prefix) == 1) ? "dedicated" : "loose"
    tag = sprintf("%-7s", provider)
    if      (provider == "claude") tag = "\033[38;5;208m" tag "\033[0m"
    else if (provider == "codex")  tag = "\033[36m" tag "\033[0m"

    if (index(path, home) == 1) path = "~" substr(path, length(home) + 1)

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%5s\t%s\t%s\n",
      rank, p, pid, kind, tag, icon, age, loc[tty], path
  }
' | sort -t$'\t' -k1,1n -k7,7n
# rank asc (what needs you floats up), then age asc so whatever just went idle
# sits at the top of its group. -k7,7n reads the leading number of the age field
# ("5m" -> 5; "-" -> 0).
