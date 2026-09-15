# Working on SATELLITE CLI

## Scope and loading

- This directory is the Git repository. The integrating `.bashrc` is two
  directories above it; preserve unrelated aliases, prompt settings, and edits.
- Use `apply_patch` for edits. Keep the module split described in `README.md`.
- `.bashrc` must remain the only file the user needs to source. Resolve module
  paths from `BASH_SOURCE`, quote paths, and support working directories and
  installation paths containing spaces.
- Source modules in the current shell. Do not make loading open a UI, launch
  Codex, change directory, or alter shell options. Reloading must work repeatedly.
- Keep `startup`, `ez_select`, and existing `ez_menu_*` functions available.
- Keep personal settings in ignored `config.bash`; never stage it. Load tracked
  `config.example.bash` first, with `MAIN MENU` as the portable title default.
- Derive title dimensions from `font.bash`; do not assume a particular title.

## Behavior to preserve

- Define entries in `menu.bash`; do not hard-code option counts elsewhere.
- Keep number columns and labels aligned as counts cross 9 and 99. Center the
  whole left-aligned block, reserving space for the selection arrow.
- Keep full-width status/stars, centered title/hints, responsive hint grouping,
  disabled styling, and all-or-nothing disabled explanations.
- Preserve star animation state across navigation, focus, and Ctrl-L. Recompute
  geometry on resize; preserve the text mask and downward fade even at peak white.
- Twinkles permanently replace their base stars, finish before sweeps, and fade
  out more slowly than they brighten. Animation updates must not launch processes
  per star/frame, alter job control, or leave a background worker after exit.
- Spawn twinkles individually. Keep each star's randomized saturation stable.
- Keep star hue offsets stable and bounded around one center, concentrated with
  a Gaussian-like distribution rather than independently cycling palette hues.
- Sweep title/number/hint accents using the shared spatial phase and complementary
  palette; preserve bold/disabled styles. Accent cells must never be spawn targets.
- Status backgrounds interpolate to the settled hint color during each sweep.
- Compose foreground repairs from final animated cells. Do not paint original
  title colors underneath an overlay or clear/repaint everything on every tick.
  Retain focus/resize/Ctrl-L repairs and the occasional missing-focus fallback.
- Preserve alternate-screen and cursor/focus cleanup on normal exit and signals.
- Disabled options must be skipped in both directions and refused by the numeric
  fallback. A fully disabled list must terminate without looping forever.
- Job availability means stopped jobs in the calling shell. Run actions there,
  not in a command substitution; only the selector owns an isolated subshell.
- Keep directory validation and exact tmux session name `codex`. Preserve the
  user's explicit Codex launch flag and `cxr` resume behavior.

## Verification

- Run `bash tests/smoke.bash` after structural/loading changes.
- Run `perl tests/terminal.pl` when changing rendering, navigation, or actions.
  If extending behavior, add focused coverage for the relevant failure mode.
- Run `bash tests/stars.bash` for animation changes; use explicit simulated times
  to check effects without flaky random timing or sleeps.
- Stub tmux/Codex and create isolated temporary jobs for checks. Do not attach,
  resume, or terminate the user's real sessions/jobs while testing.
- Check `git diff --check` and inspect the staged changes before committing.

## Commit identity

- All commits must have author and committer
  `Ana Jahnel <48846277+anastaci1a@users.noreply.github.com>` (GitHub `anastaci1a`).
- Set/check repository-local `user.name` and `user.email`; do not change global
  Git configuration or add another author/co-author without the user's request.
- Keep commits focused. Creating a GitHub remote or publishing this repository
  requires a user request; local commits are part of the authorized workflow.
