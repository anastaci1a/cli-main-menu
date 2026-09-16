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
- Use one marker column: ○ for unselected options, ● for the selected option.
  Center the whole left-aligned block independently of option count. Keep numbers
  in the non-TTY fallback, where users need them to choose an option by typing.
- Keep full-width status/stars, centered title/hints, responsive hint grouping,
  disabled styling, and all-or-nothing disabled explanations.
- Preserve star animation state across navigation, focus, and Ctrl-L. Recompute
  geometry on resize; preserve foreground glyphs and downward fade even at peak white.
- Twinkles remove consumed base stars from their original cells and fade out
  more slowly than they brighten. After expiry, replenish consumed baseline
  stars at different empty cells using the original horizon weights; births on
  empty cells owe no replacement. Keep replacement work bounded and defer when
  space is unavailable. Register replacements with the sweep's arrival buckets.
  Replacement stars ease from black to their chosen color over 500 ms without
  their own white flash. Track active fades in the work list, paint their final
  brightness before settling, and let the normal shimmer cross them.
  Animation updates must not launch processes
  per star/frame, alter job control, or leave a background worker after exit.
- Spawn twinkles individually. Keep each star's randomized saturation stable.
- Keep star hue offsets stable and bounded around one center, concentrated with
  a Gaussian-like distribution rather than independently cycling palette hues.
- Extend the star field past hints when rows permit, and stretch the option-row
  brightness falloff to the field's last row. Stars extend through control-hint
  spaces; foreground glyphs occlude them. Exclude baseline stars from
  option-label spaces (including visible notes) and the circle-to-label gap in
  initial generation and replacement. Relocate newly excluded stars on scroll.
  Preserve other stars beneath text, and never spawn a twinkle on a glyph.
  The footer fades into darkness.
- Weight individual twinkle opportunities smoothly through the sweep. A sweep
  reduces their frequency but must never switch births off abruptly. Existing
  twinkles continue their fade and share the crossing white/hue treatment.
- Sweep title/marker/hint accents using the shared spatial phase and complementary
  palette; preserve bold/disabled styles. Accent cells must never be spawn targets.
- Ease the diagonal's movement in and out while preserving individual flash
  durations. Precompute arrival times instead of solving easing for every cell/frame.
- Keep broad slow edge bands and the existing peak travel speed when adjusting
  default easing. Horizon density rises from the original top density while the
  downward brightness fade and foreground glyphs remain intact. Keep uniform
  twinkle opportunities and give them priority over extra horizon births, so
  denser lower rows never consume the top's baseline opportunities.
- Sample the downward fade with an exclusive bottom endpoint: the last visible
  row uses the color step before the darkest endpoint, never that endpoint itself.
- Default baseline quantity is 50% of the original, independent of the 2.5×
  twinkle rate. Star shimmer peaks are pure white throughout the top 30%;
  the remaining 70% approaches black with an exclusive bottom endpoint. Ordinary
  twinkle brightness and text accent fades remain independent. Default hue
  rotation is 74° per sweep.
- Status backgrounds ease to the settled hint color during each sweep.
- Bold stars and title cells briefly at their own near-white sweep peaks, then
  restore normal weight. Keep selected-option bolding and disabled styling intact.
  Include transient weight in cached cells so redraws match animation frames.
- Compose foreground repairs from final animated cells. Do not paint original
  title colors underneath an overlay or clear/repaint everything on every tick.
  Retain focus/resize/Ctrl-L repairs and the occasional missing-focus fallback.
- Preserve exact rendered cells when optimizing: timing, random draws, hue,
  saturation, fade, glyphs, bold/strike, and density must not change. Compare
  captured frames against the previous renderer using the tools below.
- Rebuild arrival buckets after geometry/text-mask changes. Selection-only
  movement updates dirty markers. Long pauses must settle every affected cell;
  idle ticks visit active twinkles, not the whole field. Bound color prefetch
  work and cache size, and do not add animation processes or runtime dependencies.
- Work buckets may group nearby arrival times, but cell color/timing calculations
  must use exact arrivals. Verify irregular frame intervals with `BENCH_JITTER=1`.
  Use `BENCH_REFERENCE_CACHE=1` when timing an already optimized reference.
- Remove consumed baseline entries from sweep buckets; do not accumulate stale
  cells or whitespace in long sessions. Packed color tags must handle hue-cycle
  wraparound and zero RGB. Check `BENCH_TIME_OFFSET_MS` and custom hue steps.
- Baseline buckets contain only live, visible stars without active twinkle or
  replacement fades. Register replacements when their fade finishes; transient
  and dirty work uses negative cell IDs and the general state checks. Rebuild
  work after manually injecting state in tests. Keep idle color preparation
  bounded (32–128 cells), and preserve the hue sampler's random draw order.
  Use `BENCH_WARMUP_MS` to verify performance after sustained animation.
- Build sparse foreground indexes inside the frozen repair frame, never reuse
  them after animation mutates cells. Preserve arbitrary/overlapping spans,
  UTF-8 markers and strike resets. Cache every changed cell even when suppressing
  deltas that a foreground repair will replace. Benchmark full repairs with
  `tools/benchmark-foreground.bash`, including command-substitution cost.
- Preserve alternate-screen and cursor/focus cleanup on normal exit and signals.
- Keep input echo disabled throughout the selector, including redraws between
  reads. Restore the caller's exact terminal settings before returning or exiting.
- Disabled options must be skipped in both directions and refused by the numeric
  fallback. A fully disabled list must terminate without looping forever.
- Job availability means stopped jobs in the calling shell. Run actions there,
  not in a command substitution; only the selector owns an isolated subshell.
- Keep directory validation and exact tmux session name `codex`. Preserve the
  user's explicit Codex launch flag and `cxr` resume behavior.
- Return to the main menu when the Codex tmux client detaches, keeping the
  Codex option selected and refreshing whether its session still exists.

## Verification

- Run `bash tests/smoke.bash` after structural/loading changes.
- Run `perl tests/terminal.pl` when changing rendering, navigation, or actions.
  If extending behavior, add focused coverage for the relevant failure mode.
- Run `bash tests/stars.bash` for animation changes; use explicit simulated times
  to check effects without flaky random timing or sleeps.
- Stub tmux/Codex and create isolated temporary jobs for checks. Do not attach,
  resume, or terminate the user's real sessions/jobs while testing.
- Check `git diff --check` and inspect the staged changes before committing.
- For performance work, use `tools/benchmark.bash` and `tools/benchmark-summary.cjs`.
  `BENCH_CAPTURE` records actual deltas and repair frames for
  `tools/compare-frames.cjs`; `BENCH_SCENARIO=1` also exercises selection,
  scrolling, resize, and skipped cycles. Node is only a development dependency.

## Commit identity

- All commits must have author and committer
  `Ana Jahnel <48846277+anastaci1a@users.noreply.github.com>` (GitHub `anastaci1a`).
- Set/check repository-local `user.name` and `user.email`; do not change global
  Git configuration or add another author/co-author without the user's request.
- Keep commits focused. Creating a GitHub remote or publishing this repository
  requires a user request; local commits are part of the authorized workflow.
