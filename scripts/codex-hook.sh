#!/usr/bin/env bash
# Codex lifecycle-hook dispatcher for tmux-claude-codex-session-manager.
#
# Codex has no `claude agents --json` analogue, so status is reconstructed from
# its lifecycle hooks: the user wires this one script into all six events in
# ~/.codex/hooks.json (see --print-config), and each firing rewrites that
# session's state file with the status the event implies. providers/codex.sh
# reads those files to build picker rows.
#
#   SessionStart / Stop                        -> idle
#   UserPromptSubmit / PreToolUse / PostToolUse -> busy
#   PermissionRequest                          -> waiting
#
# The hook is a no-op decision: it always exits 0 with no stdout, so it can
# never block, deny, or alter a Codex tool call — including on malformed
# payloads, an unwritable state dir, or missing jq/tmux.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh" 2>/dev/null || true

# Print the ready-to-paste ~/.codex/hooks.json snippet: all six events pointing
# at this script's resolved absolute path with an identical command string.
# Read-only — never touches any config file.
print_config() {
  local self="$DIR/codex-hook.sh" ev first=1
  printf '{\n  "hooks": {\n'
  for ev in SessionStart UserPromptSubmit PreToolUse PostToolUse PermissionRequest Stop; do
    [ -n "$first" ] || printf ',\n'
    first=''
    printf '    "%s": [{ "hooks": [{ "type": "command", "command": "%s" }] }]' "$ev" "$self"
  done
  printf '\n  }\n}\n'
}

if [ "${1:-}" = '--print-config' ]; then
  print_config
  exit 0
fi

main() {
  # Codex outside tmux can never appear in the picker; don't churn the sweep.
  [ -n "${TMUX_PANE:-}" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local payload event session_id cwd transcript_path turn_id status
  payload="$(cat)" || return 0

  IFS=$'\t' read -r event session_id cwd transcript_path turn_id < <(
    printf '%s' "$payload" | jq -r '[
      .hook_event_name // "", .session_id // "", .cwd // "",
      .transcript_path // "", .turn_id // ""
    ] | @tsv' 2>/dev/null
  ) || true

  # session_id becomes a filename; refuse anything that could escape the dir.
  case "${session_id:-}" in '' | . | .. | */* | .*) return 0 ;; esac

  case "${event:-}" in
  SessionStart | Stop) status=idle ;;
  UserPromptSubmit | PreToolUse | PostToolUse) status=busy ;;
  PermissionRequest) status=waiting ;;
  *) return 0 ;;
  esac

  local state_dir tmp
  state_dir="$(codex_state_dir)" || return 0
  [ -n "$state_dir" ] || return 0
  mkdir -p "$state_dir" 2>/dev/null || return 0

  # Atomic write: readers see the complete old file or the complete new one.
  # The dot prefix keeps half-written temp files out of the provider's glob.
  tmp="$(mktemp "$state_dir/.$session_id.XXXXXX" 2>/dev/null)" || return 0
  {
    printf 'status=%s\n' "$status"
    printf 'cwd=%s\n' "${cwd:-}"
    printf 'transcript_path=%s\n' "${transcript_path:-}"
    printf 'tmux_pane=%s\n' "$TMUX_PANE"
    printf 'turn_id=%s\n' "${turn_id:-}"
    printf 'updated_at=%s\n' "$(date +%s)"
  } >"$tmp" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null
    return 0
  }
  mv -f "$tmp" "$state_dir/$session_id" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}

main >/dev/null 2>&1
exit 0
