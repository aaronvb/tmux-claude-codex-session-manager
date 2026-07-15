# tmux-claude-codex-session-manager

[![screenshot](./docs/screenshot.jpg)](https://youtu.be/NnTV6r4l5D0)

Run many [Claude Code](https://claude.com/claude-code) and
[Codex](https://developers.openai.com/codex) sessions across your projects,
each in its own tmux session — then **list them all, see which are done vs.
still working, and jump to one** from a single popup.

If you launch agents per-directory (one nested session per project), you quickly
end up with a dozen of them and no way to tell which are finished without opening
each one. This plugin gives you:

- 🔢 **A central picker** (`prefix` + `u`) listing every running Claude *and*
  Codex agent in one ranked list, tagged `claude` / `codex` — several in one
  project, and any running loose in an ordinary pane.
- 🟢 **Live status** per agent — `working` / `waiting` / `idle` — so you
  instantly see which need you.
- 👁️ **A live preview** of each agent's screen right in the picker.
- 🎯 **Smart jump** — selecting an agent switches your client to the window it
  was launched from, then resumes it in a popup over it.
- 🚀 **Launchers** — `prefix` + `y` opens/attaches a Claude session for the
  current directory, `prefix` + `o` does the same for Codex.
- ❌ **Quick kill** (`ctrl-x`) of a finished agent from the picker.

Claude status needs no configuration — Claude Code publishes each agent's own
state and the picker reads it. Codex has no equivalent API, so its status is
reconstructed from lifecycle hooks: a one-time copy-paste into
`~/.codex/hooks.json` (see [Codex setup](#codex-setup)).

## Prerequisites

- **tmux ≥ 3.2** (for `display-popup`)
- **[fzf](https://github.com/junegunn/fzf)** — the picker UI
- **[jq](https://jqlang.org/)** — parses agent state
- At least one provider:
  - **[Claude Code](https://claude.com/claude-code)** ≥ 2.1.139 — for the
    `claude agents` command (`claude --version` to check)
  - **[Codex](https://developers.openai.com/codex)** ≥ 0.144.1 — for the
    stable `hooks` feature (`codex --version` to check)
- bash; macOS or Linux

Only the tools of the providers you actually use are required — the picker
works fine on a Claude-only or Codex-only machine.

## Install (tpm)

Add to `~/.tmux.conf` (or `~/.config/tmux/tmux.conf`):

```tmux
set -g @plugin 'aaronvb/tmux-claude-codex-session-manager'
```

Then hit `prefix` + <kbd>I</kbd> to install.

> **Keybinding note:** by default the plugin binds `prefix` + `y` (launch
> Claude), `prefix` + `o` (launch Codex), and `prefix` + `u` (picker). If your
> config binds those elsewhere, either change the options below, or make sure
> the plugin loads **after** your own bindings (put
> `run '~/.tmux/plugins/tpm/tpm'` _after_ them) so the one you want wins.

### Manual install

```sh
git clone https://github.com/aaronvb/tmux-claude-codex-session-manager ~/clone/path
```

Add to `~/.tmux.conf`, then reload (`prefix` + <kbd>r</kbd> or `tmux source ~/.tmux.conf`):

```tmux
run-shell ~/clone/path/agents_session_manager.tmux
```

## Codex setup

Claude works out of the box. Codex needs a one-time hook install, because Codex
has no command that reports running sessions with a live status — instead, its
lifecycle hooks push state transitions to this plugin as they happen.

**1. Add the hook entries to `~/.codex/hooks.json`.** Print the ready-to-paste
snippet with the script path already resolved:

```sh
~/.tmux/plugins/tmux-claude-codex-session-manager/scripts/codex-hook.sh --print-config
```

It looks like this (all six events point at the same dispatcher script):

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "/path/to/scripts/codex-hook.sh" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/path/to/scripts/codex-hook.sh" }] }],
    "PreToolUse": [{ "hooks": [{ "type": "command", "command": "/path/to/scripts/codex-hook.sh" }] }],
    "PostToolUse": [{ "hooks": [{ "type": "command", "command": "/path/to/scripts/codex-hook.sh" }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "/path/to/scripts/codex-hook.sh" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "/path/to/scripts/codex-hook.sh" }] }]
  }
}
```

If `~/.codex/hooks.json` doesn't exist yet, paste the snippet as the whole
file. If it does, **merge** the entries into your existing event arrays —
add each `{ "hooks": [...] }` group to the matching event's list (creating the
event key if missing). Never replace the file; your other hooks stay intact.
The plugin never edits this file for you — `--print-config` is read-only.

**2. Trust the hooks once.** The next time you start `codex`, it shows
*"Hooks need review"* — choose **"Trust all and continue"**. Codex requires
this for any new or changed hook; until trusted, the hooks simply don't run.

> Trust is recorded against the `hooks.json` entries, so plugin updates that
> change the script's internals do **not** re-trigger the prompt — only editing
> the entries themselves does. Two quirks to know: hooks trusted during a
> session's startup review start firing from the *next* codex session, and hooks
> report status from a session's first prompt/turn onward, not when its TUI
> starts. Until that first prompt, a dedicated session appears in the picker
> with a grey `?`. Hook delivery can additionally queue behind MCP server
> startup; a slow or failing server can delay it by that server's full timeout.

That's it. Codex sessions started anywhere (the hook is global) now report
`working` / `waiting` / `idle` to the picker. Sessions running outside tmux are
ignored. To uninstall, remove the entries from `~/.codex/hooks.json` — leftover
state files are inert and swept automatically.

### Codex status semantics

`waiting` for Codex is **narrower** than for Claude: it means
*approval-blocked* — Codex asked for permission to run a command and is waiting
for your answer. A conversational question that ends the turn reads as the turn
stopping, i.e. `idle`. (Claude self-reports `waiting` for any kind of "needs
your input".)

A grey `?` means a dedicated Codex session is running but has not reported a
status yet — either it has not received its first prompt or the hooks are not
installed. Its status becomes live once a hook event is delivered.

## Usage

| Key            | Action                                                                          |
| -------------- | ------------------------------------------------------------------------------- |
| `prefix` + `y` | Launch (or re-attach to) a Claude session for the current directory, in a popup |
| `prefix` + `o` | Launch (or re-attach to) a Codex session for the current directory, in a popup  |
| `prefix` + `u` | Open the agent picker                                                           |

Inside the picker:

| Key                       | Action                                                |
| ------------------------- | ----------------------------------------------------- |
| `enter`                   | Jump to the agent (see [How it works](#how-it-works)) |
| `ctrl-x`                  | Kill the highlighted agent                            |
| `↑` / `↓`, type to filter | fzf navigation                                        |

Agents needing your attention (`waiting`, `idle`) sort to the top, whatever
their provider.

Every running agent gets its own row — the picker identifies each by its
process, not by its tmux session. So several agents in one project all show up
separately, as does a Claude or Codex you started by hand in an ordinary pane.

## Options

Set any of these before the plugin loads (defaults shown):

```tmux
set -g @agents_picker_key      'u'        # prefix key: open the picker
set -g @agents_popup_width     '90%'      # shared popup width
set -g @agents_popup_height    '90%'      # shared popup height
set -g @agents_fzf_options     ''         # extra options passed to the shared fzf picker

set -g @claude_launch_key     'y'        # prefix key: launch Claude for current dir
set -g @claude_command        'claude'   # command run in new Claude sessions
set -g @claude_args           ''         # extra args appended to the command
set -g @claude_session_prefix 'claude-'  # tmux session name prefix

set -g @codex_launch_key      'o'        # prefix key: launch Codex for current dir
set -g @codex_command         'codex'    # command run in new Codex sessions
set -g @codex_args            ''         # extra args appended to the command
set -g @codex_session_prefix  'codex-'   # tmux session name prefix
set -g @codex_state_dir       ''         # where the hook writes state files
                                         # (default: $XDG_STATE_HOME/tmux-claude-codex-session-manager/codex)
set -g @codex_enabled         'auto'     # 'auto': participate when codex is installed
                                         # 'off':  skip the provider and its launch key
```

> **Migrating from the `@claude_*` plugin-wide names:** the legacy
> `@claude_list_key`, `@claude_popup_width`, `@claude_popup_height`, and
> `@claude_fzf_options` options remain silent fallbacks. When both names have a
> non-empty value, the new `@agents_*` name wins; an empty new value falls back
> to the legacy value. `$CLAUDE_PICKER` also remains a working alias of
> `$AGENTS_PICKER`. Manual installs must update their `run-shell` path from
> `claude_session_manager.tmux` to `agents_session_manager.tmux`; tpm installs
> need no action.

For example, to skip permission prompts in launched Claude sessions:

```tmux
set -g @claude_args '--dangerously-skip-permissions'
```

> **`@codex_command` caveat:** liveness detection matches the *command
> basename* of the running process against the first word of this option. A
> shell-script wrapper breaks that match (the process shows up as `bash`, not
> `codex`) and its rows are dropped rather than shown stale — point the option
> at the real binary, or at a symlink with the same name.

### Customizing the fzf picker

`@agents_fzf_options` is passed straight to `fzf`, so you can add your own bindings.

Here is a vim keybinding example:

```tmux
set -g @agents_fzf_options "\
  --prompt 'nav> ' \
  --bind 'j:down' \
  --bind 'k:up' \
  --bind 'q:abort' \
  --bind 'x:execute-silent(kill {3})+reload(sleep 0.3; \$AGENTS_PICKER --list)' \
  --bind 'i:unbind(j,k,q,i,a,x)+change-prompt(filter> )' \
  --bind 'a:unbind(j,k,q,i,a,x)+change-prompt(filter> )' \
  --bind 'esc:rebind(j,k,q,i,a,x)+change-prompt(nav> )'"
```

The picker opens in **nav** mode:

| Key       | Action                                                  |
| --------- | ------------------------------------------------------- |
| `j` / `k` | move down / up                                          |
| `i` / `a` | switch to **filter** mode — type to fuzzy-match         |
| `x`       | kill the highlighted agent (like the built-in `ctrl-x`) |
| `q`       | close the picker                                        |
| `enter`   | jump to the agent (both modes)                          |
| `esc`     | filter mode → back to nav                               |

Only the bound keys are special in nav mode; any other key still filters as you
type. `x` reloads the list through `$AGENTS_PICKER`, a path the picker exports for
exactly this — write it as `\$AGENTS_PICKER` inside the double-quoted value above
so tmux stores a literal `$` (in a single-quoted value, use a bare
`$AGENTS_PICKER`).

## How it works

- The plugin is **provider-aware**: each provider is a small adapter
  (`scripts/providers/*.sh`) that enumerates its running agents as normalized
  rows, and a shared render pipeline (`scripts/render.sh`) joins them to tmux
  panes, ranks them, and formats the picker rows.
- The **launcher** creates a detached `claude-<hash-of-dir>` (or
  `codex-<hash-of-dir>`) tmux session running the provider's command, records
  the window it came from in `@agents_origin`, and attaches to it in a popup.
  It refuses with a message when the command isn't installed.
- **Claude status** comes from `claude agents --json`: each Claude session
  self-reports its state (`busy` / `waiting` / `idle`) to a supervisor daemon,
  which that command publishes. Nothing here scans processes for a `claude`
  command name — on macOS a pane reports its parent shell, never the `claude`
  child running inside it.
- **Codex status** comes from `scripts/codex-hook.sh`, which Codex runs on each
  lifecycle event: prompt submitted / tool running → `busy`, permission
  requested → `waiting`, turn ended → `idle`. Each event atomically rewrites a
  per-session state file, which the Codex adapter reads. Dedicated sessions
  with a live `codex` process but no state file are still listed with `?`.
  Since Codex has no session-end hook, state files are treated as *claims*: a
  row is kept only when a live `codex` process still runs on the recorded pane,
  dead claims are swept, and when several claims record the same pane (quit
  codex, restart it in the same pane), only the newest survives.
- The **render pipeline** pairs each agent with the tmux pane it occupies by
  joining `pid` → `tty` → pane (Claude reports a pid) or pane → `tty` → `pid`
  (Codex's hook records a pane). That join is why identity is the agent
  _process_ rather than the tmux session, and therefore why several agents in
  one project each get their own row. It costs three subprocesses per render,
  whatever the number of sessions or panes.
- The **age column** is the mtime of the agent's transcript — its last sign of
  life. Codex hands the hook its transcript path; for Claude it is found by
  glob, since `claude agents --json` reports only `startedAt`. A brand-new
  agent that has yet to take a turn shows `-`.
- The **picker** renders those rows with a live `capture-pane` preview. On `enter`
  a **dedicated** agent (in a `claude-*`/`codex-*` session) resumes in the popup
  over the window it was launched from, while a **loose** one (any other pane) is
  focused in place. `ctrl-x` kills the agent process itself — Claude's
  self-reported pid or Codex's pane-resolved pid: a dedicated session dies with
  its last window, and a loose pane keeps the shell that hosted it.
- Pressing `prefix` + `u` **from inside a session popup** (either provider's)
  detaches that popup first (closing it), then reopens the picker full-size on
  the outer host client — so you never end up with a cramped popup-in-popup.

## License

[MIT](LICENSE) © Takuya Matsuyama · Codex support added in this fork by
[Aaron Van Bokhoven](https://github.com/aaronvb)
