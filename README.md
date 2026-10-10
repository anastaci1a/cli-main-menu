# SATELLITE CLI

A Bash launcher for Codex sessions and Codex Switcher's session manager.
Its animated star field adapts to your terminal size.

![SATELLITE menu preview](media/menu-demo.gif)

## Get started

Place this directory at `~/scripts/cli` and add this line to `~/.bashrc`:

```bash
source -- "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/scripts/cli/init.bash" || return
```

Then reload your shell and open the menu:

```bash
source ~/.bashrc
startup
```

Sourcing the file only defines commands; it does not open the menu. Bash 4+,
`date`, `stty`, and `clear` are required. Codex integration needs `tmux`, `jq`,
and a current `codex-switcher` with enrolled accounts. Keep the same
`CODEX_SWITCHER_HOME` in your shell and switcher service.

## Use the menu

Use Up/Down to choose an option and Enter or Space to select it. Left focuses
`◀— Back` in submenus; on the home screen, `◀—` expands to `◀— Exit`.
Right returns to the options. Esc goes back or leaves the home menu for your
shell. Text fields use Left/Right to move the cursor.

- **New Terminal** returns to your shell. Selecting **Exit** closes that shell.
- **Codex: New Session** appears when no sessions exist and asks for a unique
  name, starting directory, and account. The directory picker starts at your current
  directory, lets you browse or type a path, and can create a new directory.
  Session names may contain letters, digits, spaces, and `_+-=~()[]`.
- **Codex: Sessions** lists working sessions, idle sessions,
  and saved conversations marked `(inactive)`, most recently opened
  first within each group when switcher has that timestamp. The list updates live;
  working sessions have an animated indicator and remain selectable. Brackets
  show the enrolled identity nickname. Select any session to open it in its original
  account home. **[new session]** creates another session.
  The menu opens with a complete list and shares live updates with the home screen.
  Discovery failures are shown explicitly, with retained live rows marked unknown.
- **Session Manager**, below the session list, opens Codex Switcher. Manage
  accounts, rename sessions, move projects, and handle operation progress,
  confirmations, cancellation, and recovery there. Automatic account switching
  remains unavailable.

Detach from a Codex or dashboard tmux session with Ctrl+B, then D. The menu
returns; the Sessions list keeps the same session selected. If Codex fails
during startup, its pane keeps the error visible until you terminate it.
Session names, recency, and conversation history are managed by switcher.
The menus hide one leading `codex-` from names without renaming sessions.

## Customize

Create a Git-ignored `config.bash` (copy `config.example.bash` if starting
fresh), change the settings you want, and run `source ~/.bashrc`. The portable
title is `MAIN MENU`; this installation uses `SATELLITE` in its local config.
Set `EZ_MENU_ANIMATE_STARS=0` for stationary stars. Colors can be overridden
with the `C_*` values in `theme.bash`. Edit `menu_items` in `menu.bash` to
change the main menu.

## Check changes

```bash
bash tests/smoke.bash
bash tests/backend.bash
bash tests/watch.bash
bash tests/switcher.bash
bash tests/session_focus.bash
bash tests/launch.bash
bash tests/stars.bash
perl tests/terminal.pl
```

Tests use fake or isolated sessions and do not operate on your live Codex
sessions. The terminal suite needs Perl `IO::Pty`. Contributor rules and renderer
benchmark commands are in [AGENTS.md](AGENTS.md).

The backend contract is documented in Codex Switcher's
`docs/CLI_MAIN_MENU_INTEGRATION.md`. The menu uses `sessions --all` and
`sessions --all --watch` for inventory, `status --json` for account choices,
`run --account` for new launches, `open --session ID` for live or saved
conversations, and `ui` for session management.
