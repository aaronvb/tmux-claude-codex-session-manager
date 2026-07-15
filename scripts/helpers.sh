#!/usr/bin/env bash
# Shared helpers for tmux-claude-codex-session-manager.

# get_tmux_option <option-name> <default>
# Echoes the global tmux option value, or the default when unset/empty.
get_tmux_option() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$2"
  fi
}

# get_tmux_option_compat <new-option-name> <legacy-option-name> <default>
# The new-name argument maps an @agents_* option to the legacy @claude_* name
# passed by each caller, so existing configurations continue to work unchanged.
get_tmux_option_compat() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return
  fi

  value="$(tmux show-option -gqv "$2" 2>/dev/null)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$3"
  fi
}

# session_hash <string>
# Short, stable, portable 8-char hash for deriving a session name from a path.
# Prefers md5sum (Linux), falls back to md5 (macOS) then shasum. The trailing
# newline matches the conventional `echo "$path" | md5sum` scheme, so it stays
# compatible with sessions created that way.
session_hash() {
  local out
  if command -v md5sum >/dev/null 2>&1; then
    out="$(printf '%s\n' "$1" | md5sum)"
  elif command -v md5 >/dev/null 2>&1; then
    out="$(printf '%s\n' "$1" | md5 -q)"
  else
    out="$(printf '%s\n' "$1" | shasum)"
  fi
  printf '%s' "${out%% *}" | cut -c1-8
}

# file_mtime <path>
# Epoch seconds of a file's last modification. GNU stat (Linux) is tried first,
# then BSD (macOS); each rejects the other's flag, so the fallback is unambiguous.
file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# codex_state_dir
# Directory where the Codex hook writes one state file per session. Overridable
# via @codex_state_dir. get_tmux_option already swallows a missing/unreachable
# tmux and echoes the default, so the hook can resolve this with no server up.
codex_state_dir() {
  get_tmux_option @codex_state_dir \
    "${XDG_STATE_HOME:-$HOME/.local/state}/tmux-claude-codex-session-manager/codex"
}

# codex_state_load <file>
# Parses a state file's key=value lines into cs_* variables (cs_status, cs_cwd,
# cs_transcript_path, cs_tmux_pane, cs_turn_id, cs_updated_at). Keys are
# whitelisted rather than eval'd, so a corrupt file can set nothing else.
# Returns non-zero when the file is unreadable.
codex_state_load() {
  # shellcheck disable=SC2034  # consumed by the sourcing script, not here
  cs_status='' cs_cwd='' cs_transcript_path='' cs_tmux_pane='' cs_turn_id='' cs_updated_at=''
  [ -r "$1" ] || return 1
  local line key
  while IFS= read -r line || [ -n "$line" ]; do
    key="${line%%=*}"
    case "$key" in
    status | cwd | transcript_path | tmux_pane | turn_id | updated_at)
      printf -v "cs_$key" '%s' "${line#*=}"
      ;;
    esac
  done <"$1"
}

# claude_transcript_mtime <session-id>
# Epoch seconds of the last write to that Claude session's transcript — i.e. when
# the agent last did anything. `claude agents --json` reports only `startedAt`,
# never a last-activity time, so the transcript's mtime stands in for it.
#
# Found by glob so we never have to reproduce Claude's cwd -> project-slug
# encoding. The path is an internal Claude Code detail and may move; an empty
# result just renders the age column as '-'.
claude_transcript_mtime() {
  local base f
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  for f in "$base"/projects/*/"$1".jsonl; do
    [ -f "$f" ] && {
      file_mtime "$f"
      return
    }
  done
}
