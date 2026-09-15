# SATELLITE CLI

Bash startup menu with a live status bar, a stationary fading star field, Codex
session controls, and shell job controls.

## Load and run

Keep this folder at `scripts/cli/` beside `.bashrc`:

```text
.bashrc
scripts/cli/
  init.bash
  config.example.bash
  config.bash          # personal, ignored by Git
  theme.bash
  font.bash
  render.bash
  actions.bash
  select.bash
  menu.bash
```

The installed `.bashrc` sources the entry point with:

```bash
source -- "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/scripts/cli/init.bash" || return
```

This resolves against the location of `.bashrc`, including paths with spaces;
it does not depend on your working directory. Reload and open the menu with:

```bash
source ~/.bashrc
startup
```

Sourcing only defines the functions, colors, and `startup` alias. It does not open
the menu, attach tmux, or start Codex. Reloading `.bashrc` reloads every module.
Personal aliases (including `cxr`) and the shell prompt remain in `.bashrc`.

Requires Bash 4+, `date`, `stty`, and `clear`. Codex actions additionally need
`tmux` and `codex`. Job switching requires an interactive shell with job control.

## Where to customize

| File | Contents |
| --- | --- |
| `init.bash` | Module loading and the `startup` alias |
| `theme.bash` | Shared colors, disabled styles, and status background |
| `config.example.bash` | Tracked defaults; title falls back to `MAIN MENU` |
| `config.bash` | Optional personal title/color overrides; ignored by Git |
| `font.bash` | Block lettering that adapts to the configured title |
| `menu.bash` | Main menu entries and action dispatch |
| `actions.bash` | New Terminal, Codex, Jobs, and placeholder actions |
| `render.bash` | Title, status, stars, geometry, and control hints |
| `select.bash` | Arrow keys, disabled options, scrolling, focus, and resize handling |

### Personal title and colors

Edit `config.bash`, then run `source ~/.bashrc`. This installation keeps
`EZ_MENU_TITLE='SATELLITE'` there. On a fresh checkout, copy
`config.example.bash` to `config.bash` to start customizing; without a local
config, the title is `MAIN MENU`.

Loading resets the theme and example defaults before applying local overrides.
The local config is sourced Bash, so use trusted settings. You can override any
`C_*` color from `theme.bash` there as well. Star colors should use the existing
256-color escape format so the downward brightness fade can derive their RGB.

ASCII letters, digits, spaces, and hyphens become block lettering automatically;
other characters use a plain title. Narrow or short screens use the plain title,
clipped to the available width. Fit calculations follow the configured title's
dimensions, so changing its length does not require editing the renderer.

### Menu entries

Edit `menu_items` in `menu.bash` to add or reorder options. Each entry is:

```text
Label|action_function|close_or_stay|optional_enabled_check|optional_disabled_note
```

For example, define `my_action` in `actions.bash`, then add:

```bash
'My action|my_action|stay'
```

Use `close` to leave the menu after a successful action, or `stay` to return to
it. An enabled check returns zero when available; a nonzero result disables the
option. Disabled notes disappear as a whole when they cannot fit. Use plain text
without `|` in these fields. Numbering, alignment, scrolling, and the star fade
adapt to the option list and terminal size.

Actions execute in the calling shell so `fg` can resume its jobs. The selector
alone uses a subshell to isolate cursor and signal cleanup. Its visible output
goes to stderr; stdout returns the selected zero-based index.

## Current behavior

- Up/Down moves the selection, Enter selects, Escape leaves, and Ctrl-L redraws.
- The status bar fills the screen. Hints use 4, 2+2, or 1+1+1+1 layouts.
- Option rows form a centered, left-aligned block with a fixed arrow slot.
- Stars stay fixed during clock ticks and navigation. Side stars keep a clear
  gutter around the options and fade darker toward the bottom.
- Codex resumes tmux session `codex` through `cxr`, or validates a starting
  directory and creates `codex` running
  `codex --dangerously-bypass-approvals-and-sandbox`.
- Jobs is disabled when this shell has no stopped jobs. When available, it lists
  running and stopped shell jobs and offers foreground/termination actions.
- Disabled Jobs has a dark purple struck number and a dark gray struck label;
  its `(no stopped jobs)` explanation is not struck through.
- The menu uses an alternate screen and repaints on focus/resize and clock ticks.
  It restores terminal modes before launching an action or returning to the shell.

## Validation

```bash
bash tests/smoke.bash
perl tests/terminal.pl
```

The smoke check validates syntax, repeated `.bashrc` loading, the `startup`
alias, and relocation into a path with spaces. An alternate `.bashrc` can be
provided as its first argument. The terminal checks require Perl `IO::Pty` and
exercise navigation, resize/focus, Codex arguments, and temporary test jobs.
They stub tmux and do not launch Codex or operate on your existing shell jobs.
Set `EZ_CLI_BASHRC` to test a different `.bashrc` with the terminal suite.

## Git

This folder is its own local repository. The integrating `.bashrc` is outside
the repository; the source line above documents that connection.

All commits must use the verified GitHub identity:

```text
Ana Jahnel <48846277+anastaci1a@users.noreply.github.com>
```

Repository-local Git configuration sets both author and committer defaults to
this identity. No GitHub remote is required for local version history.
