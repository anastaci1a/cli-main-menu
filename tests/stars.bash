#!/usr/bin/env bash
# Deterministic animation times; no wall-clock sleeps or user sessions.
set -eo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source -- "$cli_dir/init.bash"
declare -a stars_cells stars_fade stars_hue stars_sat stars_value
declare -A stars_char stars_palette stars_birth stars_seen stars_rgb_cache
EZ_MENU_SWEEP_INTERVAL_MS=4000 EZ_MENU_SWEEP_DURATION_MS=1000 EZ_MENU_SWEEP_HUE_STEP=70
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
  done
done
printf 'PASS scalable text masks and row brightness\n'

# Three fixed stars span the sweep's diagonal; suppress random births.
COLUMNS=80 stars_top=3 stars_bottom=16
stars_cells=(160 239 1279) stars_fade=([3]=100 [16]=5)
stars_char=([160]='.' [239]='+' [1279]='*')
stars_palette=([160]=0 [239]=0 [1279]=0) stars_birth=() stars_seen=()
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
(( stars_next > 5100 && stars_next < 7100 ))
ez_stars_tick 6000
[[ ${#stars_birth[@]} == 0 ]]
printf 'PASS random birth scheduling and twinkle-free sweeps\n'

# Invalid settings cannot create division by zero or overlapping sweeps.
EZ_MENU_SWEEP_INTERVAL_MS=0 EZ_MENU_SWEEP_DURATION_MS=nope EZ_MENU_SWEEP_HUE_STEP=-1
ez_stars_init
[[ $stars_period == 4000 && $stars_duration == 1000 && $stars_step == 70 ]]
printf 'PASS invalid animation settings use safe defaults\n'
