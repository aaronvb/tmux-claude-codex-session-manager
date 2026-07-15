#!/usr/bin/env bash
# Emit one picker row per running agent, across every enabled provider.
#
# A provider is an adapter under providers/ that enumerates its running agents
# as normalized rows (see render.sh for both row formats); this orchestrator
# concatenates their output and pipes it through the shared render pipeline.
# A provider whose tool is missing is skipped silently, and one provider
# failing or emitting nothing never suppresses the other's rows.
#
# Codex additionally honors @codex_enabled: 'auto' (default) participates only
# when the codex command is installed; 'off' skips the provider entirely.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

{
  claude_cmd="$(get_tmux_option @claude_command 'claude')"
  if command -v "${claude_cmd%% *}" >/dev/null 2>&1; then
    "$DIR/providers/claude.sh" || true
  fi

  codex_cmd="$(get_tmux_option @codex_command 'codex')"
  if [ "$(get_tmux_option @codex_enabled 'auto')" != 'off' ] &&
    command -v "${codex_cmd%% *}" >/dev/null 2>&1; then
    "$DIR/providers/codex.sh" || true
  fi
} | "$DIR/render.sh"
