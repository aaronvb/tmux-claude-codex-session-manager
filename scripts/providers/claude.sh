#!/usr/bin/env bash
# Claude provider adapter: emit one normalized row per running Claude agent.
#
#   Row: provider \t id \t status \t cwd \t transcript_path \t locator
#
# Claude self-reports its status: each session writes its own state to disk and a
# supervisor daemon aggregates it, which `claude agents --json` publishes. So this
# needs no hooks, and no `pane_current_command` scan — on macOS a pane reports its
# parent shell there, never the `claude` child running inside it.
#
# The locator is the agent's pid (what Claude knows natively); render.sh joins it
# to a tmux pane. transcript_path is left empty — render.sh resolves the age via
# the claude_transcript_mtime glob instead.
set -uo pipefail

command -v claude >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

agents="$(claude agents --json 2>/dev/null)" || exit 0
printf '%s' "$agents" |
  jq -r '.[] | select(.kind == "interactive") |
    ["claude", .sessionId, .status, .cwd, "", .pid] | @tsv' 2>/dev/null
exit 0
