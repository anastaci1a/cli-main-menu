#!/usr/bin/env bash
# Deterministic animation times; no wall-clock sleeps or user sessions.
set -eo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source -- "$cli_dir/init.bash"
declare -a stars_cells stars_fade stars_hue stars_sat stars_value
declare -A stars_char stars_palette stars_saturation stars_birth stars_seen stars_rgb_cache
declare -A stars_text_char stars_text_style stars_text_fade stars_text_seen
EZ_MENU_SWEEP_INTERVAL_MS=4000 EZ_MENU_SWEEP_DURATION_MS=1000 EZ_MENU_SWEEP_HUE_STEP=70
EZ_MENU_STAR_SATURATION_MAX=800 EZ_MENU_SWEEP_ACCENT_OFFSET=180
ez_stars_init

# Masks adapt to title width, option width/count, and the viewport.
for COLUMNS in 5 36 80 160; do
  for visible in 1 4 15; do
    LINES=40 option_left=$((COLUMNS / 3)) option_right=$((COLUMNS / 3))
    title_width=$((COLUMNS / 2)) title_left=$(((COLUMNS - title_width) / 2))
    ez_stars_layout 10 5 "$title_width" 2
    for cell in "${stars_cells[@]}"; do
      row=$((cell / COLUMNS + 1)) col=$((cell % COLUMNS))
      (( row >= 3 && row <= 12 + visible && col < COLUMNS ))
      if (( row >= 5 && row < 10 )); then
        (( col < title_left - 2 || col >= title_left + title_width + 2 ))
      elif (( row >= 12 )); then
        (( col < option_left - 3 || col >= COLUMNS - option_right + 3 ))
      fi
    done
    [[ ${stars_fade[13]} == 65 || $visible == 1 ]]
    (( visible == 1 )) || [[ ${stars_fade[12+visible]} == 5 ]]
    for cell in "${!stars_char[@]}"; do
      (( stars_saturation[$cell] >= stars_sat[${stars_palette[$cell]}] && stars_saturation[$cell] <= 800 ))
    done
  done
done
printf 'PASS scalable text masks, row brightness, and randomized saturation bounds\n'

# Three fixed stars span the sweep's diagonal; suppress random births.
COLUMNS=80 stars_top=3 stars_bottom=16
stars_cells=(160 239 1279) stars_fade=([3]=100 [16]=5)
stars_char=([160]='.' [239]='+' [1279]='*')
stars_palette=([160]=0 [239]=0 [1279]=0) stars_birth=() stars_seen=()
stars_saturation=()
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

for instant in 3600 4000 4500 4999; do
  stars_next=0
  ez_stars_tick "$instant"
  [[ ${#stars_birth[@]} == 0 ]]
done
stars_next=0
ez_stars_tick 5100
[[ ${stars_birth[160]} == 5100 ]]
(( stars_next > 5100 && stars_next <= 5600 ))
ez_stars_tick 6000
[[ ${#stars_birth[@]} == 0 ]]
printf 'PASS random birth scheduling and twinkle-free sweeps\n'

# Deadlines create exactly one star when space is available, even after a pause.
stars_char=() stars_birth=() stars_cells=(160 161 162 163 164 165 166 167)
for ((instant = 100; instant <= 170; instant += 10)); do
  before=${#stars_birth[@]} stars_next=0
  ez_stars_tick "$instant"
  (( ${#stars_birth[@]} == before + 1 ))
  (( stars_next > instant && stars_next <= instant + 500 ))
done
saved_saturation=$(declare -p stars_saturation)
stars_next=999999
ez_stars_tick 200
[[ $(declare -p stars_saturation) == "$saved_saturation" ]]
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

# Invalid settings cannot create division by zero or overlapping sweeps.
EZ_MENU_SWEEP_INTERVAL_MS=0 EZ_MENU_SWEEP_DURATION_MS=nope EZ_MENU_SWEEP_HUE_STEP=-1
ez_stars_init
[[ $stars_period == 4000 && $stars_duration == 1000 && $stars_step == 70 ]]
printf 'PASS invalid animation settings use safe defaults\n'
