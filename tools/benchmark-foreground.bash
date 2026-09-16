#!/usr/bin/env bash
# Measure actual full-menu repairs, including the command substitution used by
# the chooser. Optional fourth argument supplies a reference render.bash.
set -eo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source -- "$cli_dir/init.bash"
[[ -z ${4:-} ]] || source -- "$4"
[[ -z ${5:-} ]] || source -- "$5"
EZ_MENU_TITLE=SATELLITE
COLUMNS=${1:-80} LINES=${2:-24} visible=${3:-4} ez_stars_animated=1
RANDOM=1967
mapfile -t title_rows < <(ez_menu_title_rows)
mapfile -t fitted_rows <<< "$(ez_menu_banner 0 2)"
mapfile -t hint_rows < <(ez_menu_hint_lines)
labels=() menu_enabled=() menu_disabled_notes=()
for ((index = 0; index < visible + 3; index++)); do
  labels+=("Option $index  more") menu_enabled+=(1)
done
menu_enabled[2]=0 menu_disabled_notes[2]='(not available)'
read -r marker_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "${labels[@]}")
ez_menu_draw_cached=1
declare -A stars_char stars_palette stars_saturation stars_birth stars_seen stars_rgb_cache
declare -A stars_text_char stars_text_style stars_text_fade stars_text_seen stars_text_flash stars_occluded
declare -A stars_hue_offset stars_cell_render stars_text_palette
ez_stars_init
ez_stars_layout "${#fitted_rows[@]}" 5 "${#title_rows[0]}" 2 "${#labels[@]}" 0 "${labels[@]}"
ez_stars_text_layout "${#fitted_rows[@]}" "${#title_rows[0]}" 2 0 0 1 "${labels[@]}"
ez_stars_build_work
[[ -z ${BENCH_CAPTURE:-} ]] || exec 3>"$BENCH_CAPTURE"
printf 'elapsed_ms,render_us,bytes\n'
for ((elapsed = 0; elapsed < 10000; elapsed += 250)); do
  ez_stars_tick "$elapsed" 0
  ez_stars_bar_color "$elapsed"
  started=${EPOCHREALTIME/./}
  frame=$(
    [[ -n ${5:-} ]] || ez_stars_prepare_repair
    printf '\033[H'
    for ((row = 1; row <= ${#fitted_rows[@]} + 2; row++)); do
      ez_stars_render_span "$row" 0 "$COLUMNS"
      printf '\r\n'
    done
    ez_menu_draw 1 0 "$visible" "${labels[@]}"
    printf '\r\033[J'
  )
  finished=${EPOCHREALTIME/./}
  printf '%d,%d,%d\n' "$elapsed" "$((10#$finished - 10#$started))" "${#frame}"
  [[ -z ${BENCH_CAPTURE:-} ]] || printf '%s\0%s\0%s\0%s\0' "$elapsed" "$frame" "$stars_bar_bg" "$frame" >&3
done
