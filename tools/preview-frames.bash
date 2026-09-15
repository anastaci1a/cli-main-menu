#!/usr/bin/env bash
# Feed terminal frames to render-preview.cjs. This uses the real renderer and
# simulated menu state; it never opens tmux, Codex, or the user's job table.
set -eo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source -- "$cli_dir/init.bash"
EZ_MENU_TITLE=SATELLITE
COLUMNS=80 LINES=24 ez_stars_animated=1 visible=4
RANDOM=1967
title_rows=()
mapfile -t title_rows < <(ez_menu_title_rows)
mapfile -t fitted_rows <<< "$(ez_menu_banner 0 2)"
mapfile -t hint_rows < <(ez_menu_hint_lines)
labels=('New Terminal' 'Start Codex' 'Jobs' 'Exit')
menu_enabled=(1 1 0 1)
menu_disabled_notes=([2]='(no stopped jobs)')
read -r number_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "${labels[@]}")

declare -a stars_cells stars_fade stars_hue stars_sat stars_value
declare -A stars_char stars_palette stars_saturation stars_birth stars_seen stars_rgb_cache
declare -A stars_text_char stars_text_style stars_text_fade stars_text_seen
declare -A stars_hue_offset stars_cell_render stars_text_palette
ez_stars_init
ez_stars_layout "${#fitted_rows[@]}" 5 "${#title_rows[0]}" 2 "${#labels[@]}"
ez_stars_text_layout "${#fitted_rows[@]}" "${#title_rows[0]}" 2 0 0 1 "$number_width"
status_date=$(date '+%a %b %d')
for ((elapsed = 0; elapsed <= 10000; elapsed += 200)); do
  ez_stars_tick "$elapsed"
  ez_stars_bar_color "$elapsed"
  printf -v clock '%02d:%02d:%02d' 10 15 "$((elapsed / 1000 % 60))"
  printf -v status_line ' %s  %s | satellite | ~/projects' "$status_date" "$clock"
  printf -v status_line '%-80.80s' "$status_line"
  frame=$(
    printf '\033[H%s%s%s%s\r\n' "$stars_bar_bg" "$C_WHITE" "$status_line" "$C_RESET"
    for ((screen_row = 2; screen_row <= ${#fitted_rows[@]} + 2; screen_row++)); do
      ez_stars_render_span "$screen_row" 0 "$COLUMNS"
      printf '\r\n'
    done
    ez_menu_draw 1 0 4 "${labels[@]}"
    printf '\r\033[J'
  )
  printf '%s\0' "$frame"
done
