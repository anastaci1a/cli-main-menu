#!/usr/bin/env bash
# Deterministic animation times; no wall-clock sleeps or user sessions.
set -eo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source -- "$cli_dir/init.bash"
declare -a stars_cells stars_fade stars_hue stars_sat stars_value
declare -A stars_char stars_palette stars_saturation stars_birth stars_seen stars_rgb_cache
declare -A stars_text_char stars_text_style stars_text_fade stars_text_seen
declare -A stars_hue_offset stars_cell_render stars_text_palette
declare -a hint_rows=()
EZ_MENU_SWEEP_INTERVAL_MS=4000 EZ_MENU_SWEEP_DURATION_MS=1000 EZ_MENU_SWEEP_HUE_STEP=70
EZ_MENU_STAR_SATURATION_MAX=800 EZ_MENU_SWEEP_ACCENT_OFFSET=180
EZ_MENU_STAR_HUE_SPREAD=60
ez_stars_init

# A repeatable sample must cluster near its center, not uniformly at the edges.
RANDOM=7129
inner=0 outer=0 total=0
for ((sample = 0; sample < 3000; sample++)); do
  ez_stars_pick_hue 0
  offset=${stars_hue_offset[0]}
  (( offset >= -30 && offset <= 30 ))
  total=$((total + offset))
  if (( offset >= -10 && offset <= 10 )); then inner=$((inner + 1)); fi
  if (( offset <= -20 || offset >= 20 )); then outer=$((outer + 1)); fi
done
(( inner > 4 * outer && total > -6000 && total < 6000 ))
[[ ${stars_hue[0]} == "${stars_hue[1]}" && ${stars_hue[1]} == "${stars_hue[2]}" ]]
printf 'PASS bounded Gaussian-like hue distribution around one palette center\n'

# Masks adapt to title width, option width/count, and the viewport.
for COLUMNS in 5 36 80 160; do
  for visible in 1 4 15; do
    LINES=40 option_left=$((COLUMNS / 3)) option_right=$((COLUMNS / 3))
    mapfile -t hint_rows < <(ez_menu_hint_lines)
    hint_width=0
    for hint in "${hint_rows[@]}"; do (( ${#hint} > hint_width )) && hint_width=${#hint}; done
    hint_left=$(((COLUMNS - hint_width) / 2))
    (( hint_left < 0 )) && hint_left=0
    hint_end=$((13 + visible + ${#hint_rows[@]}))
    title_width=$((COLUMNS / 2)) title_left=$(((COLUMNS - title_width) / 2))
    ez_stars_layout 10 5 "$title_width" 2
    for cell in "${stars_cells[@]}"; do
      row=$((cell / COLUMNS + 1)) col=$((cell % COLUMNS))
      (( row >= 3 && row <= hint_end + 2 && row < LINES && col < COLUMNS ))
      if (( row >= 5 && row < 10 )); then
        (( col < title_left - 2 || col >= title_left + title_width + 2 ))
      elif (( row >= 12 && row <= 13 + visible )); then
        (( col < option_left - 3 || col >= COLUMNS - option_right + 3 ))
      elif (( row >= 14 + visible && row <= hint_end )); then
        (( col < hint_left - 3 || col >= hint_left + hint_width + 3 ))
      fi
    done
    [[ ${stars_fade[13]} == 65 && ${stars_fade[$stars_bottom]} == 5 ]]
    (( stars_fade[12+visible] > 5 ))
    for ((row = 14; row <= stars_bottom; row++)); do (( stars_fade[row] <= stars_fade[row-1] )); done
    for cell in "${!stars_char[@]}"; do
      (( stars_saturation[$cell] >= stars_sat[${stars_palette[$cell]}] && stars_saturation[$cell] <= 800 ))
    done
  done
done
LINES=18 COLUMNS=80 visible=3
mapfile -t hint_rows < <(ez_menu_hint_lines)
ez_stars_layout 10 5 53 2
[[ $stars_bottom == 17 && ${stars_fade[17]} == 5 ]]
hint_rows=()
printf 'PASS extended field, text masks, stretched fade, and saturation bounds\n'

# Three fixed stars span the sweep's diagonal; suppress random births.
COLUMNS=80 stars_top=3 stars_bottom=16 stars_sweep_bottom=16
stars_cells=(160 239 1279) stars_fade=([3]=100 [16]=5)
stars_char=([160]='.' [239]='+' [1279]='*')
stars_palette=([160]=0 [239]=0 [1279]=0) stars_birth=() stars_seen=()
stars_saturation=() stars_hue_offset=()
stars_next=999999
ez_stars_tick 3999
original=${stars_seen[160]}
ez_stars_tick 4060
[[ ${stars_seen[160]} == '255;255;255:.' ]]
[[ ${stars_seen[239]} == "${original%:*}:+" ]]
ez_stars_tick 4410
[[ ${stars_seen[239]} == '255;255;255:+' ]]
ez_stars_tick 4760
[[ ${stars_seen[1279]} == '12;12;12:*' ]]
ez_stars_tick 5000
rotated=${stars_seen[160]}
[[ $rotated != "$original" && $rotated != '255;255;255:.' ]]
ez_stars_tick 5100
[[ -z $stars_output && ${stars_seen[160]} == "$rotated" ]]
ez_stars_tick 9000
[[ ${stars_seen[160]} != "$rotated" ]]
printf 'PASS diagonal timing, white peak, dim lower peak, and persistent hue rotation\n'

# A twinkle replaces an existing star, rises in 120ms, falls over 780ms,
# then disappears permanently, including after a full foreground redraw.
stars_cells=(160) stars_char=([160]='*') stars_palette=([160]=0)
stars_birth=() stars_seen=() stars_next=999999
ez_stars_spawn 160 100
ez_stars_tick 100
[[ ${stars_seen[160]} == '0;0;0:.' ]]
ez_stars_tick 220
[[ ${stars_seen[160]} == '255;255;255:*' ]]
ez_stars_tick 340
[[ $stars_r -gt 200 && $stars_r -lt 255 ]]
ez_stars_tick 800
[[ $stars_r -gt 0 && $stars_r -lt 100 && ${stars_char[160]+present} ]]
ez_stars_tick 1000
[[ ! ${stars_char[160]+present} && ! ${stars_birth[160]+present} ]]
[[ $stars_output == *$'\033[3;1H '* ]]
stars_seen=()
ez_stars_tick 1100
[[ -z $stars_output ]]
printf 'PASS fast eased twinkle, slow fade, and permanent collision removal\n'

# The probability envelope is periodic, smooth and nonzero through the sweep.
ez_stars_twinkle_weight 4000
edge_weight=$stars_spawn_weight
ez_stars_twinkle_weight 4500
[[ $stars_spawn_weight == 200 ]]
ez_stars_twinkle_weight 5000
[[ $stars_spawn_weight == "$edge_weight" ]]
ez_stars_twinkle_weight 6500
[[ $stars_spawn_weight == 1000 ]]
previous=-1
for ((instant = 0; instant <= 8000; instant += 10)); do
  ez_stars_twinkle_weight "$instant"
  (( stars_spawn_weight >= 200 && stars_spawn_weight <= 1000 ))
  if (( previous >= 0 )); then (( stars_spawn_weight - previous <= 9 && previous - stars_spawn_weight <= 9 )); fi
  previous=$stars_spawn_weight
done
RANDOM=1801
during=0 between=0
for instant in 4500 6500; do
  for ((trial = 0; trial < 200; trial++)); do
    stars_char=() stars_birth=() stars_next=0
    ez_stars_tick "$instant"
    if [[ ${stars_birth[160]+present} ]]; then
      if (( instant == 4500 )); then during=$((during + 1)); else between=$((between + 1)); fi
    fi
    (( stars_next > instant && stars_next <= instant + 500 ))
  done
done
(( during > 10 && during < 80 && between == 200 ))
stars_char=() stars_birth=() stars_next=999999
ez_stars_spawn 160 3950
ez_stars_tick 4050
[[ ${stars_birth[160]} == 3950 && $stars_r -gt 0 ]]
ez_stars_tick 4850
[[ ! ${stars_birth[160]+present} && ! ${stars_char[160]+present} ]]
printf 'PASS smooth weighted births, fewer during sweeps, and uninterrupted overlapping fades\n'

# Deadlines create exactly one star when space is available, even after a pause.
stars_char=() stars_birth=() stars_cells=(160 161 162 163 164 165 166 167)
instant=2500
for ((trial = 0; trial < 8; trial++)); do
  before=${#stars_birth[@]} stars_next=0
  ez_stars_tick "$instant"
  (( ${#stars_birth[@]} == before + 1 ))
  (( stars_next > instant && stars_next <= instant + 500 ))
done
saved_saturation=$(declare -p stars_saturation)
saved_hues=$(declare -p stars_hue_offset)
stars_next=999999
ez_stars_tick 2600
[[ $(declare -p stars_saturation) == "$saved_saturation" ]]
[[ $(declare -p stars_hue_offset) == "$saved_hues" ]]
printf 'PASS single births, sub-half-second delays, and stable per-star saturation\n'

# Title and two-digit numbers sweep with the palette's complementary hue.
title_rows=('AB') COLUMNS=80 LINES=24 visible=3 option_left=30 option_right=46
menu_enabled=([9]=1 [10]=0 [11]=1)
ez_stars_layout 6 1 2 2
ez_stars_text_layout 6 2 2 0 9 9 2
title_cell=$((4 * 80 + 39)) number_cell=$((8 * 80 + 31)) disabled_cell=$((9 * 80 + 31))
[[ ${stars_text_char[$title_cell]} == A && ${stars_text_char[$number_cell]} == 1 ]]
[[ ${stars_text_style[$number_cell]} == 1 && ${stars_text_style[$disabled_cell]} == 9 ]]
[[ ${stars_text_fade[$disabled_cell]} == 60 ]]
for cell in "${stars_cells[@]}"; do [[ ! ${stars_text_char[$cell]+present} ]]; done
[[ ${stars_hue[3]} == $(((stars_hue[0] + (stars_hue[1] - stars_hue[0] + stars_hue[2] - stars_hue[0]) / 3 + 180) % 360)) ]]
stars_next=999999
ez_stars_tick 3999
[[ ${stars_text_seen[$title_cell]%:*:*} == "${stars_text_seen[$number_cell]%:*:*}" ]]
original_accent=${stars_text_seen[$title_cell]}
# At the title cell's white peak, disabled rows are still styled independently.
arrival=$((700 * (39 * 1000 / 79 + (5 - stars_top) * 1000 / (stars_bottom - stars_top)) / 2000))
ez_stars_tick "$((4000 + arrival + 60))"
[[ ${stars_text_seen[$title_cell]} == '255;255;255:1:A' ]]
ez_stars_tick 5000
[[ ${stars_text_seen[$title_cell]} != "$original_accent" ]]
[[ ${stars_text_seen[$title_cell]%:*:*} == "${stars_text_seen[$number_cell]%:*:*}" ]]
ez_stars_text_layout 6 2 2 0 9 11 2
[[ ${stars_text_style[$number_cell]} == 0 && ${stars_text_style[$disabled_cell]} == 9 ]]
ez_stars_tick 5100
[[ ${stars_text_seen[$number_cell]} == *':0:1' ]]
EZ_MENU_TITLE='A compact title'
ez_stars_text_layout 6 15 2 1 9 11 2
[[ ${#stars_text_char[@]} -gt 8 ]]
printf 'PASS complementary title/numbers, shared sweep, scrolling, and disabled/selected styles\n'

# Wrapped hints extend the spatial sweep and retain a dimmer, softer palette.
for COLUMNS in 20 36 80; do
  LINES=30 visible=3 option_left=3 option_right=3 title_rows=('AB')
  mapfile -t hint_rows < <(ez_menu_hint_lines)
  ez_stars_layout 6 1 2 2
  ez_stars_text_layout 6 2 2 0 0 0 1
  [[ $stars_sweep_bottom == $((6 + visible + 5 + ${#hint_rows[@]})) ]]
  hint_cell=''
  for cell in "${!stars_text_char[@]}"; do
    if [[ ${stars_text_palette[$cell]} == 4 ]]; then
      hint_cell=$cell
      [[ ${stars_text_style[$cell]} == 0 && ${stars_text_fade[$cell]} == 55 ]]
    fi
  done
  [[ -n $hint_cell ]]
  row=$((hint_cell / COLUMNS + 1)) col=$((hint_cell % COLUMNS))
  arrival=$((700 * (col * 1000 / (COLUMNS - 1) + (row - stars_top) * 1000 / (stars_sweep_bottom - stars_top)) / 2000))
  stars_next=999999
  ez_stars_tick "$((4000 + arrival + 60))"
  [[ ${stars_text_seen[$hint_cell]} == '140;140;140:0:'* ]]
done
[[ ${stars_hue[4]} == "${stars_hue[3]}" && ${stars_sat[4]} -lt ${stars_sat[3]} ]]
ez_stars_color 4 0 0 55 1000
from_r=$stars_r from_g=$stars_g from_b=$stars_b
ez_stars_color 4 1 0 55 1000
to_r=$stars_r to_g=$stars_g to_b=$stars_b
ez_stars_bar_color 4000
[[ $stars_r == "$from_r" && $stars_g == "$from_g" && $stars_b == "$from_b" ]]
ez_stars_bar_color 4500
(( stars_r == from_r + (to_r - from_r) / 2 ))
(( stars_g == from_g + (to_g - from_g) / 2 ))
(( stars_b == from_b + (to_b - from_b) / 2 ))
ez_stars_bar_color 5000
[[ $stars_r == "$to_r" && $stars_g == "$to_g" && $stars_b == "$to_b" ]]
settled_bg=$stars_bar_bg
ez_stars_bar_color 7000
[[ $stars_bar_bg == "$settled_bg" ]]
printf 'PASS responsive hint sweep and linear status-bar color endpoints/midpoint\n'

# Invalid settings cannot create division by zero or overlapping sweeps.
EZ_MENU_SWEEP_INTERVAL_MS=0 EZ_MENU_SWEEP_DURATION_MS=nope EZ_MENU_SWEEP_HUE_STEP=-1
ez_stars_init
[[ $stars_period == 4000 && $stars_duration == 1000 && $stars_step == 70 ]]
printf 'PASS invalid animation settings use safe defaults\n'
