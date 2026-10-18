#!/usr/bin/env bash
# Compare final terminal cells after partial selection repairs with full repairs.
set -eo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$cli_dir/init.bash"
capture_dir=$(mktemp -d)
trap 'rm -rf -- "$capture_dir"' EXIT
capture() (
  local mode=$1 COLUMNS=$2 LINES=24 visible=4 ez_stars_animated=1 ez_menu_draw_cached=1
  local selected=0 previous=0 step elapsed row frame repair
  local -a title_rows=(TITLE) hint_rows=(Controls) fitted_rows=('' '' '' '' '' '')
  local -a original_labels=('One [work]' 'Two [personal]' Disabled Four)
  local -a menu_enabled=(1 1 0 1) menu_disabled_notes=([2]='(unavailable)')
  local -a menu_accent_suffix=([0]=' [work]' [1]=' [personal]') menu_gray_suffix=() menu_spacers=()
  local -a menu_layout_labels=("${original_labels[@]}") ez_menu_damage_rows=() stars_text_option_cells
  local -A stars_char stars_palette stars_saturation stars_birth stars_seen stars_rgb_cache
  local -A stars_text_char stars_text_style stars_text_fade stars_text_seen stars_text_flash stars_occluded
  local -A stars_hue_offset stars_cell_render stars_text_palette
  read -r marker_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "${original_labels[@]}")
  RANDOM=7291
  ez_stars_init
  ez_stars_layout 6 1 5 2 4 0 "${original_labels[@]}"
  ez_stars_text_layout 6 5 2 0 0 0 "${original_labels[@]}"
  ez_stars_build_work
  full_frame() {
    ez_stars_prepare_repair
    printf '\033[H'
    for ((row=1;row<=8;row++)); do ez_stars_render_span "$row" 0 "$COLUMNS"; printf '\r\n'; done
    ez_menu_draw "$selected" 0 "$visible" "${original_labels[@]}"
  }
  step=0
  for elapsed in 3900 4000 4200 4400 4750 5000 5600; do
    previous=$selected
    (( step == 0 )) || selected=$(((selected+1)%4))
    (( selected != 2 )) || selected=3
    if [[ $mode == partial ]]; then ez_stars_select 0 "$selected" 6
    else
      ez_stars_text_layout 6 5 2 0 0 "$selected" "${original_labels[@]}"
      ez_stars_build_work
    fi
    ez_stars_tick "$elapsed"
    repair=$(full_frame)
    if [[ $mode == partial ]] && (( step )); then
      frame=$(
        ez_menu_damage_rows=("$previous" "$selected")
        ez_stars_prepare_repair
        ez_menu_draw "$selected" 0 "$visible" "${original_labels[@]}"
        printf '%s' "$stars_output"
      )
    else frame=$repair; fi
    printf '%s\0%s\0%s\0%s\0' "$elapsed" "$frame" '' "$repair"
    step=$((step+1))
  done
)
for width in 36 80 160; do
  capture full "$width" > "$capture_dir/full"
  capture partial "$width" > "$capture_dir/partial"
  node "$cli_dir/tools/compare-frames.cjs" "$capture_dir/full" "$capture_dir/partial"
done
