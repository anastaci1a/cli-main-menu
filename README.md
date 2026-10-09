# SATELLITE CLI

A Bash menu for Codex tmux sessions, stopped shell jobs, and the Codex Switcher
dashboard. Its animated star field adapts to your terminal size.

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
`date`, `stty`, and `clear` are required. Codex sessions need `tmux` and `codex`.
The dashboard needs `codex-switcher`; `jq` enables its account nicknames in the
Sessions list.

## Use the menu

Use Up/Down to choose an option and Enter or Space to select it. Esc goes back;
in a submenu, Left focuses `◀— Back` and Right returns to the options. Text
fields use Left/Right to move the cursor. The on-screen hints show the controls
available on each screen.

- **New Terminal** returns to your shell. **Exit** exits that shell.
- **Codex: New Session** appears when no sessions exist and asks for a unique
  name and starting directory. The directory picker starts at your current
  directory, lets you browse or type a path, and can create a new directory.
  Session names may contain letters, digits, spaces, and `_+-=~()[]`.
- **Codex: Sessions** appears when sessions exist. It lists `[new session]` and
  lets you resume, rename, or terminate each session. The selected session has a
  live uptime; its bracketed account label comes from Codex Switcher when
  available. **Codex: Resume** opens the most recently used session.
- **Codex Switcher: Dashboard** opens account monitoring and manual moves. Its
  automatic switching indicator remains unavailable until the switcher supports
  managed launches. New sessions here run Codex directly using your current
  configuration; the dashboard does not choose their account.
- **Jobs** manages stopped jobs from this shell. It is unavailable when none
  exist.

Detach from a Codex or dashboard tmux session with Ctrl+B, then D. The menu
returns; the Sessions list keeps the same session selected. If Codex fails
during startup, its pane keeps the error visible until you terminate it.

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
bash tests/switcher.bash
bash tests/session_focus.bash
bash tests/launch.bash
bash tests/stars.bash
perl tests/terminal.pl
```

Tests use fake or isolated sessions and do not operate on your live Codex
sessions. The terminal suite needs Perl `IO::Pty`. Contributor rules and renderer
benchmark commands are in [AGENTS.md](AGENTS.md).
