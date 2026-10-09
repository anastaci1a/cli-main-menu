# SATELLITE CLI contributor rules

This directory is the Git repository; the integrating `.bashrc` is two levels
above it. Use `apply_patch` for edits. Preserve unrelated `.bashrc` content,
existing function names, and the module split (`init`, `menu`, `select`,
`render`, `stars`, `sessions`, `actions`, `font`, `theme`).

## Loading and behavior

- Keep `.bashrc` as the only file users source. Resolve modules from
  `BASH_SOURCE`, quote paths, and support spaces in installation and working
  directories. Sourcing and repeated sourcing must not open a UI, launch
  Codex or tmux, change directory, or alter shell options.
- Load tracked `config.example.bash` before ignored personal `config.bash`;
  never stage the latter. Keep `MAIN MENU` as the portable title default and
  derive title dimensions from `font.bash`.
- Define options in `menu.bash`, without hard-coded counts elsewhere. Keep the
  centered, left-aligned option block; one ○/● marker column; disabled styling
  and indivisible notes; responsive hints; and numbered non-TTY selection.
- Run actions in the calling shell so `fg` sees its jobs. Isolate only the
  selector. Skip disabled choices in both directions and reject them in the
  numeric fallback. Jobs availability means stopped jobs in that shell.
- Keep session names, directory validation, exact `codex` tmux recognition,
  explicit Codex launch options, and `cxr` behavior. Return to the appropriate
  menu after detach with the same session selected. Preserve the switcher's
  account/home distinction; use `display_account` only for display.
- Keep inactive conversations visible across switcher accounts; preserve exact
  thread IDs and homes on Start/Move. Never terminate an unfinished turn or
  delete a conversation through the tmux Terminate action.
- Share switcher discovery only within a menu refresh. Actions must recheck
  current state; a visible Codex prompt does not override an unfinished rollout.
- Keep the alternate screen, cursor, focus, and exact terminal-mode cleanup on
  return and signals. Suppress input echo throughout rendering as well as reads.

## Renderer invariants

- Preserve animated state across selection and focus; rebuild geometry and work
  indexes on resize or text-mask changes. Navigation and clock ticks must not
  rerandomize stars or repaint the whole screen. Full repairs use final animated
  cells, with foreground text and markers taking priority over stars.
- Keep the existing twinkle, replacement, shimmer, hue, density, fade, and
  sweep timing and random draws. Replacements occur at new eligible cells,
  fade in without a separate white flash, and replenish consumed baseline
  stars. Never spawn a twinkle on foreground text. Preserve disabled, selected,
  bold, strike, UTF-8, and transparent-space rendering.
- Keep animation work bounded: no per-frame processes or background worker,
  no unbounded caches or stale bucket entries, and no new animation runtime
  dependencies.
  Sparse repairs must use current cell tokens and exact per-cell arrival times.
  When optimizing, compare captured frames against the previous renderer;
  output and random behavior must remain equivalent.

## Verification

- Run `bash tests/smoke.bash` after loading or structural edits and
  `perl tests/terminal.pl` after rendering, navigation, or action edits. Add a
  focused regression check for new behavior. Run `bash tests/stars.bash` for
  animation changes; use simulated times instead of sleeps. Run the relevant
  `tests/switcher.bash`, `tests/session_focus.bash`, or `tests/launch.bash` for
  session changes; run `tests/move.bash` and `tests/move_tmux.bash` for
  move/inactive changes.
- Stub tmux/Codex or use isolated test sockets. Never attach, resume, or
  terminate the user's live sessions or jobs in tests.
- For performance work, use `tools/benchmark.bash`,
  `tools/benchmark-summary.cjs`, and `tools/compare-frames.cjs` with
  `BENCH_CAPTURE`; use `tools/benchmark-foreground.bash` for full repairs.
  Exercise changing layouts with `BENCH_SCENARIO=1`, irregular frames with
  `BENCH_JITTER=1`, long runs with `BENCH_WARMUP_MS`, and custom cycles with
  `BENCH_TIME_OFFSET_MS`/`BENCH_HUE_STEP`.
- Keep the preview fixture aligned with user-visible menu changes. Regenerate
  and inspect it with:
  `bash tools/preview-frames.bash > /tmp/satellite-frames.ansi` followed by
  `node tools/render-preview.cjs /tmp/satellite-frames.ansi media`. Install the
  optional `tools/package.json` dependencies first if needed. The GitHub Action
  also regenerates and commits changed previews on `main`.
- Check `git diff --check` and inspect staged changes before committing.
  Human-authored commits must use repository-local author and committer
  `Ana Jahnel <48846277+anastaci1a@users.noreply.github.com>`; automated preview
  commits use `github-actions[bot]`. Do not change global Git identity or stage
  private config. The user authorized keeping this repository's `origin/main`
  current: push completed commits after checks, never force-push, and do not
  publish other repositories without their request.
