#!/usr/bin/env bash
# Codex provider adapter: emit one normalized row per live Codex session.
#
#   Row: provider \t id \t status \t cwd \t transcript_path \t locator
#
# Codex has no status-pull API, so rows come from the state files codex-hook.sh
# writes (one per session). Those files are claims, not truth: there is no
# SessionEnd hook, so a crashed or exited codex leaves its file behind. A claim
# is kept only when a live process whose command basename matches the first word
# of @codex_command still runs on the recorded pane; dead claims are swept
# (best-effort unlink). When several files claim one pane (quit codex, restart
# it in the same pane; recycled pane ids), only the newest updated_at survives.
#
# The locator is the recorded pane id (what the hook knows natively, via
# $TMUX_PANE); render.sh resolves the pid from it. transcript_path is recorded
# by the hook, so the age column needs no glob.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
. "$DIR/../helpers.sh"

state_dir="$(codex_state_dir)"
[ -d "$state_dir" ] || exit 0

cmd="$(get_tmux_option @codex_command 'codex')"
expected="${cmd%% *}"
expected="${expected##*/}"

# Panes that host a live codex right now. ps comm can be a bare name, a full
# path, or a retitled string with spaces ("claude bg-pty-host"), so it is taken
# as everything after the tty field and compared by basename, strictly — helper
# processes that retitle themselves must not count as the agent.
alive_panes="$({
  ps -Ao tty=,comm= 2>/dev/null | awk '{
    tty = $1
    sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+/, "")
    print "P\t" tty "\t" $0
  }'
  tmux list-panes -a -F $'T\t#{pane_tty}\t#{pane_id}' 2>/dev/null
} | awk -F'\t' -v cmd="$expected" '
  $1 == "P" { base = $3; sub(/.*\//, "", base); if (base == cmd) live["/dev/" $2] = 1; next }
  $1 == "T" { if ($2 in live) print $3 }
')"

# Pass 1: parse every claim, sweep the dead ones.
claims=''
for f in "$state_dir"/*; do
  [ -f "$f" ] || continue
  codex_state_load "$f" || continue
  if [ -z "$cs_tmux_pane" ] ||
    ! printf '%s\n' "$alive_panes" | grep -qxF "$cs_tmux_pane"; then
    rm -f "$f" 2>/dev/null
    continue
  fi
  # shellcheck disable=SC2154  # cs_* are set by codex_state_load via printf -v
  claims="${claims}${cs_tmux_pane}	${cs_updated_at:-0}	${f}	${cs_status}	${cs_cwd}	${cs_transcript_path}
"
done
[ -n "$claims" ] || exit 0

# Pass 2: one claim per pane — newest updated_at wins, older ones are swept.
sorted="$(printf '%s' "$claims" | sort -t$'\t' -k1,1 -k2,2nr)"

printf '%s\n' "$sorted" | awk -F'\t' 'seen[$1]++ { print $3 }' |
  while IFS= read -r f; do
    [ -n "$f" ] && rm -f "$f" 2>/dev/null
  done

# awk rather than a read loop: read with IFS=$'\t' collapses the consecutive
# tabs around an empty field, silently shifting every field after it.
printf '%s\n' "$sorted" | awk -F'\t' '!seen[$1]++ {
  id = $3; sub(/.*\//, "", id)
  print "codex\t" id "\t" $4 "\t" $5 "\t" $6 "\t" $1
}'
exit 0
