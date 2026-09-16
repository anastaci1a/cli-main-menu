#!/usr/bin/env bash
# Deterministic rendering/output benchmark. No TTY, sleeps, jobs, or external commands
# in the timed loop. Optional fourth argument loads a reference stars.bash.
set -eo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source -- "$cli_dir/init.bash"
[[ -z ${4:-} ]] || source -- "$4"
EZ_MENU_TITLE=SATELLITE
COLUMNS=${1:-80} LINES=${2:-24} visible=${3:-4} ez_stars_animated=1
EZ_MENU_TWINKLE_RATE_PERCENT=250 EZ_MENU_HORIZON_DENSITY_PERCENT=600
EZ_MENU_SWEEP_DURATION_MS=1467 EZ_MENU_SWEEP_INTERVAL_MS=4000
RANDOM=1967
mapfile -t title_rows < <(ez_menu_title_rows)
mapfile -t fitted_rows <<< "$(ez_menu_banner 0 2)"
mapfile -t hint_rows < <(ez_menu_hint_lines)
labels=() menu_enabled=() menu_disabled_notes=()
total=$visible
[[ ${BENCH_SCENARIO:-0} != 1 ]] || total=$((visible + 4))
for ((index = 0; index < total; index++)); do labels+=("Option $index"); menu_enabled+=(1); done
if [[ ${BENCH_SCENARIO:-0} == 1 ]]; then menu_enabled[2]=0; menu_disabled_notes[2]='(unavailable)'; fi
read -r marker_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "${labels[@]}")
declare -a stars_cells stars_fade stars_density stars_hue stars_sat stars_value stars_sweep_arrival
declare -A stars_char stars_palette stars_saturation stars_birth stars_seen stars_rgb_cache
declare -A stars_text_char stars_text_style stars_text_fade stars_text_seen stars_text_flash stars_occluded
declare -A stars_hue_offset stars_cell_render stars_text_palette
ez_stars_init
ez_stars_layout "${#fitted_rows[@]}" 5 "${#title_rows[0]}" 2 "$total" 0 "${labels[@]}"
ez_stars_text_layout "${#fitted_rows[@]}" "${#title_rows[0]}" 2 0 0 1 "${labels[@]}"
[[ -n ${4:-} && ${BENCH_REFERENCE_CACHE:-0} != 1 ]] || ez_stars_build_work
[[ -z ${BENCH_CAPTURE:-} ]] || exec 3>"$BENCH_CAPTURE"
printf 'elapsed_ms,render_us,bytes\n'
first=0 selected=1
for ((elapsed = 0; elapsed < 12000; elapsed += 50)); do
  if [[ ${BENCH_SCENARIO:-0} == 1 ]]; then
    case $elapsed in
      2450|5700|7700)
        (( elapsed == 2450 )) && selected=3
        (( elapsed == 5700 )) && first=1
        if (( elapsed == 7700 )); then
          COLUMNS=$((COLUMNS + 10))
          read -r marker_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "${labels[@]}")
          ez_stars_layout "${#fitted_rows[@]}" 5 "${#title_rows[0]}" 2 "$total" "$first" "${labels[@]}"
        fi
        if [[ -z ${4:-} || ${BENCH_REFERENCE_CACHE:-0} == 1 ]] && (( elapsed == 2450 )); then
          ez_stars_select "$first" "$selected" "${#fitted_rows[@]}"
        else
          ez_stars_text_layout "${#fitted_rows[@]}" "${#title_rows[0]}" 2 0 "$first" "$selected" "${labels[@]}"
          [[ -n ${4:-} && ${BENCH_REFERENCE_CACHE:-0} != 1 ]] || ez_stars_build_work
        fi
        ;;
    esac
  fi
  instant=$elapsed
  [[ ${BENCH_JITTER:-0} != 1 ]] || instant=$((instant + (elapsed / 50 % 4) * 7))
  [[ ${BENCH_SCENARIO:-0} != 1 ]] || (( elapsed < 9000 )) || instant=$((instant + 9000))
  started=${EPOCHREALTIME/./}
  ez_stars_tick "$instant"
  ez_stars_bar_color "$instant"
  finished=${EPOCHREALTIME/./}
  printf '%d,%d,%d\n' "$instant" "$((10#$finished - 10#$started))" "${#stars_output}"
  if [[ -n ${BENCH_CAPTURE:-} ]]; then
    printf '%s\0%s\0%s\0' "$instant" "$stars_output" "$stars_bar_bg" >&3
    for ((row = stars_top; row <= stars_bottom; row++)); do
      printf '\033[%d;1H' "$row" >&3
      ez_stars_render_span "$row" 0 "$COLUMNS" >&3
    done
    printf '\0' >&3
  fi
done
