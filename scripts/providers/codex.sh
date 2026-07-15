#!/usr/bin/env bash
# Codex provider adapter: emit one normalized row per live Codex session.
#
#   Row: provider \t id \t status \t cwd \t transcript_path \t locator
#
# Codex has no status-pull API, so rows come from the state files codex-hook.sh
# writes (one per session). Those files are claims, not truth: there is no
# SessionEnd hook, so a crashed or exited codex leaves its file behind. A claim
# is kept only when it is not older than the current tmux server and a
# live process whose command basename matches the first word of @codex_command
# still runs on the recorded pane; stale and dead claims are swept (best-effort
# unlink). When several files claim one pane (quit codex, restart it in the same
# pane; recycled pane ids), only the newest updated_at survives. A dedicated
# session with a live codex but no surviving claim gets a status '-' placeholder.
#
# The locator is the recorded pane id (what the hook knows natively, via
# $TMUX_PANE); render.sh resolves the pid from it. transcript_path is recorded
# by the hook, so the age column needs no glob.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
. "$DIR/../helpers.sh"

state_dir="$(codex_state_dir)"

cmd="$(get_tmux_option @codex_command 'codex')"
expected="${cmd%% *}"
expected="${expected##*/}"
codex_prefix="$(get_tmux_option @codex_session_prefix 'codex-')"

# Panes that host a live codex right now. ps comm can be a bare name, a full
# path, or a retitled string with spaces ("claude bg-pty-host"), so it is taken
# as everything after the tty field and compared by basename, strictly — helper
# processes that retitle themselves must not count as the agent.
pane_snapshot="$({
  ps -Ao tty=,comm= 2>/dev/null | awk '{
    tty = $1
    sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+/, "")
    print "P\t" tty "\t" $0
  }'
  tmux list-panes -a -F $'T\t#{pane_tty}\t#{pane_id}\t#{session_name}\t#{pane_current_path}\t#{start_time}' 2>/dev/null
} | awk -F'\t' -v cmd="$expected" '
  $1 == "P" { base = $3; sub(/.*\//, "", base); if (base == cmd) live["/dev/" $2] = 1; next }
  $1 == "T" {
    if (!saw_server++) print "S\t" $6
    if ($2 in live) print $3 "\t" $4 "\t" $5
  }
')"

# #{start_time} is server-scoped, so the first pane supplies it for every claim.
# Pull the leading metadata row off the snapshot without another tmux call.
server_start=''
alive_panes=''
if [ -n "$pane_snapshot" ]; then
  first="${pane_snapshot%%$'\n'*}"
  server_start="${first#*$'\t'}"
  case "$pane_snapshot" in
  *$'\n'*) alive_panes="${pane_snapshot#*$'\n'}" ;;
  esac
fi

# Pass 1: parse every claim, sweep claims from before this tmux server and
# claims whose recorded pane does not host a live codex.
claims=''
for f in "$state_dir"/*; do
  [ -f "$f" ] || continue
  codex_state_load "$f" || continue
  predates_server=''
  case "${cs_updated_at:-}" in
  '' | *[!0-9]*) predates_server=1 ;;
  *)
    if [ -n "$server_start" ] && [ "$cs_updated_at" -lt "$server_start" ]; then
      predates_server=1
    fi
    ;;
  esac
  if [ -n "$predates_server" ]; then
    rm -f "$f" 2>/dev/null
    continue
  fi
  if [ -z "$cs_tmux_pane" ] ||
    ! printf '%s\n' "$alive_panes" |
      awk -F'\t' -v pane="$cs_tmux_pane" '$1 == pane { found = 1 } END { exit !found }'; then
    rm -f "$f" 2>/dev/null
    continue
  fi
  # shellcheck disable=SC2154  # cs_* are set by codex_state_load via printf -v
  claims="${claims}${cs_tmux_pane}	${cs_updated_at:-0}	${f}	${cs_status}	${cs_cwd}	${cs_transcript_path}
"
done

# Pass 2: one claim per pane — newest updated_at wins, older ones are swept.
sorted="$(printf '%s' "$claims" | sort -t$'\t' -k1,1 -k2,2nr)"

printf '%s\n' "$sorted" | awk -F'\t' 'NF && seen[$1]++ { print $3 }' |
  while IFS= read -r f; do
    [ -n "$f" ] && rm -f "$f" 2>/dev/null
  done

# awk rather than a read loop: read with IFS=$'\t' collapses the consecutive
# tabs around an empty field, silently shifting every field after it.
printf '%s\n' "$sorted" | awk -F'\t' 'NF && !seen[$1]++ {
  id = $3; sub(/.*\//, "", id)
  print "codex\t" id "\t" $4 "\t" $5 "\t" $6 "\t" $1
}'

# Dedicated live panes not covered by a surviving claim still belong in the
# picker. Feed tagged streams to awk so pane ids are compared as exact fields.
{
  printf '%s\n' "$sorted" | awk -F'\t' 'NF && !seen[$1]++ { print "C\t" $1 }'
  printf '%s\n' "$alive_panes" | awk -F'\t' 'NF { print "A\t" $0 }'
} | awk -F'\t' -v prefix="$codex_prefix" '
  $1 == "C" { claimed[$2] = 1; next }
  $1 == "A" && index($3, prefix) == 1 && !($2 in claimed) {
    print "codex\t" $3 "\t-\t" $4 "\t\t" $2
  }
'
exit 0
