#!/usr/bin/env bash
# Deterministic animation times; no wall-clock sleeps or user sessions.
set -eo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source -- "$cli_dir/init.bash"
declare -a stars_cells stars_fade stars_hue stars_sat stars_value
declare -A stars_char stars_palette stars_saturation stars_birth stars_seen stars_rgb_cache
declare -A stars_text_char stars_text_style stars_text_fade stars_text_seen
declare -A stars_text_flash stars_occluded
declare -A stars_hue_offset stars_cell_render stars_text_palette
declare -a hint_rows=()
EZ_MENU_SWEEP_INTERVAL_MS=4000 EZ_MENU_SWEEP_DURATION_MS=1000 EZ_MENU_SWEEP_HUE_STEP=70
EZ_MENU_STAR_SATURATION_MAX=800 EZ_MENU_SWEEP_ACCENT_OFFSET=180
EZ_MENU_STAR_HUE_SPREAD=60
EZ_MENU_TWINKLE_ADVANCE_MS=500 EZ_MENU_TWINKLE_RATE_PERCENT=200
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
      fi
    done
    [[ ${stars_fade[13]} == 65 ]]
    (( stars_fade[stars_bottom] == 65 - 60 * (stars_bottom - 13) / (stars_bottom - 12) ))
    (( stars_fade[stars_bottom] > 5 ))
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
[[ $stars_bottom == 17 && ${stars_fade[17]} == 17 ]]
hint_rows=()
printf 'PASS extended field, text masks, stretched fade, and saturation bounds\n'

# Three fixed stars span the sweep's diagonal; suppress random births.
COLUMNS=80 stars_top=3 stars_bottom=16 stars_sweep_bottom=16
stars_cells=(160 239 1279) stars_fade=([3]=100 [16]=5)
stars_peak=([3]=1000 [16]=50)
stars_char=([160]='.' [239]='+' [1279]='*')
stars_palette=([160]=0 [239]=0 [1279]=0) stars_birth=() stars_seen=()
stars_saturation=() stars_hue_offset=()
stars_next=999999
ez_stars_tick 3999
original=${stars_seen[160]}
ez_stars_tick 4060
[[ ${stars_seen[160]} == '255;255;255:1:.' ]]
[[ ${stars_cell_render[160]} == '255;255;255:1:.' ]]
[[ ${stars_seen[239]} == "${original%:*}:+" ]]
ez_stars_tick 4080
[[ ${stars_seen[160]} == *':1:.' ]]
ez_stars_tick 4120
[[ ${stars_seen[160]} == *':0:.' && ${stars_cell_render[160]} == "${stars_seen[160]}" ]]
ez_stars_tick 4410
[[ ${stars_seen[239]} == '255;255;255:1:+' ]]
ez_stars_tick 4760
[[ ${stars_seen[1279]} == '12;12;12:1:*' ]]
ez_stars_tick 5000
rotated=${stars_seen[160]}
[[ $rotated != "$original" && $rotated == *':0:.' ]]
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
[[ ${stars_seen[160]} == '0;0;0:0:.' ]]
ez_stars_tick 220
[[ ${stars_seen[160]} == '255;255;255:0:*' ]]
ez_stars_tick 340
[[ $stars_r -gt 200 && $stars_r -lt 255 ]]
ez_stars_tick 800
[[ $stars_r -gt 0 && $stars_r -lt 100 && ${stars_char[160]+present} ]]
ez_stars_tick 1000
[[ ! ${stars_char[160]+present} && ! ${stars_birth[160]+present} ]]
[[ $stars_output == *$'\033[3;1H\033[0;0m '* ]]
stars_seen=()
ez_stars_tick 1100
[[ -z $stars_output ]]
printf 'PASS fast eased twinkle, slow fade, and permanent collision removal\n'
stars_replenish=() stars_replace_queue=() stars_replace_head=0 stars_replace_tail=0

# The probability envelope is periodic, smooth and nonzero through the sweep.
ez_stars_twinkle_weight 3500
edge_weight=$stars_spawn_weight
ez_stars_twinkle_weight 4000
[[ $stars_spawn_weight == 200 ]]
ez_stars_twinkle_weight 4500
[[ $stars_spawn_weight == "$edge_weight" ]]
ez_stars_twinkle_weight 6000
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
for instant in 4000 6000; do
  for ((trial = 0; trial < 200; trial++)); do
    stars_char=() stars_birth=() stars_next=0
    ez_stars_tick "$instant"
    if [[ ${stars_birth[160]+present} ]]; then
      if (( instant == 4000 )); then during=$((during + 1)); else between=$((between + 1)); fi
    fi
    (( stars_next > instant && stars_next <= instant + 250 ))
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
instant=2000
for ((trial = 0; trial < 8; trial++)); do
  before=${#stars_birth[@]} stars_next=0
  ez_stars_tick "$instant"
  (( ${#stars_birth[@]} == before + 1 ))
  (( stars_next > instant && stars_next <= instant + 250 ))
done
saved_saturation=$(declare -p stars_saturation)
saved_hues=$(declare -p stars_hue_offset)
stars_next=999999
ez_stars_tick 2600
[[ $(declare -p stars_saturation) == "$saved_saturation" ]]
[[ $(declare -p stars_hue_offset) == "$saved_hues" ]]
printf 'PASS single births, sub-half-second delays, and stable per-star saturation\n'

# Title and markers sweep with the palette's complementary hue across scrolling.
title_rows=('AB') COLUMNS=80 LINES=24 visible=3 option_left=30 option_right=46
menu_enabled=([9]=1 [10]=0 [11]=1)
ez_stars_layout 6 1 2 2
ez_stars_text_layout 6 2 2 0 9 9
title_cell=$((4 * 80 + 39)) marker_cell=$((8 * 80 + 30)) disabled_cell=$((9 * 80 + 30))
[[ ! ${stars_text_char[$((marker_cell - 1))]+present} && ! ${stars_text_char[$((marker_cell + 1))]+present} ]]
[[ ${stars_text_char[$title_cell]} == A && ${stars_text_char[$marker_cell]} == '●' ]]
[[ ${stars_text_char[$disabled_cell]} == '○' ]]
[[ ${stars_text_style[$marker_cell]} == 1 && ${stars_text_style[$disabled_cell]} == 9 ]]
[[ ${stars_text_fade[$disabled_cell]} == 60 ]]
# The field now extends behind text; foreground glyphs win during rendering.
[[ " ${stars_cells[*]} " == *" $marker_cell "* ]]
[[ ${stars_hue[3]} == $(((stars_hue[0] + (stars_hue[1] - stars_hue[0] + stars_hue[2] - stars_hue[0]) / 3 + 180) % 360)) ]]
stars_next=999999
ez_stars_tick 3999
[[ ${stars_text_seen[$title_cell]%:*:*} == "${stars_text_seen[$marker_cell]%:*:*}" ]]
[[ ${stars_text_seen[$title_cell]} == *':0:A' && ${stars_text_seen[$marker_cell]} == *':1:●' ]]
original_accent=${stars_text_seen[$title_cell]}
# At the title cell's white peak, disabled rows are still styled independently.
distance=$(((39 * 1000 / 79 + (5 - stars_top) * 1000 / (stars_bottom - stars_top)) / 2))
arrival=${stars_sweep_arrival[distance]}
ez_stars_tick "$((4000 + arrival + 60))"
[[ ${stars_text_seen[$title_cell]} == '255;255;255:1:A' ]]
[[ ${stars_cell_render[$title_cell]} == '255;255;255:1:A' ]]
ez_stars_tick 5000
[[ ${stars_text_seen[$title_cell]} != "$original_accent" ]]
[[ ${stars_text_seen[$title_cell]} == *':0:A' && ${stars_text_seen[$marker_cell]} == *':1:●' ]]
[[ ${stars_text_seen[$disabled_cell]} == *':9:○' ]]
[[ ${stars_text_seen[$title_cell]%:*:*} == "${stars_text_seen[$marker_cell]%:*:*}" ]]
ez_stars_text_layout 6 2 2 0 9 11
[[ ${stars_text_char[$marker_cell]} == '○' && ${stars_text_char[$((marker_cell + 2 * 80))]} == '●' ]]
[[ ${stars_text_style[$marker_cell]} == 0 && ${stars_text_style[$disabled_cell]} == 9 ]]
ez_stars_tick 5100
[[ ${stars_text_seen[$marker_cell]} == *':0:○' ]]
EZ_MENU_TITLE='A compact title'
ez_stars_text_layout 6 15 2 1 9 11
[[ ${#stars_text_char[@]} -gt 8 ]]
printf 'PASS complementary circle markers, shared sweep, scrolling, and disabled/selected styles\n'

# Markers stay one column wide as the option count grows, including in C locale.
(
  COLUMNS=80 menu_enabled=() menu_disabled_notes=()
  labels=()
  for ((index = 0; index < 100; index++)); do labels+=(Entry); done
  for count in 3 10 100; do
    [[ $(ez_menu_option_layout "${labels[@]:0:count}") == '1 5 7 36 37' ]]
  done
  prefix=$'\033[0;0;38;2;1;2;3m'
  stars_cell_render=([0]='1;2;3:0:○' [1]='1;2;3:0:○' [2]='1;2;3:0:●' [3]='1;2;3:0:m')
  [[ $(ez_stars_render_span 1 0 4) == "$prefix○○●m$C_RESET" ]]
)
printf 'PASS fixed marker columns and intact UTF-8 glyphs in batched redraws\n'

# Wrapped hints extend the spatial sweep and retain a dimmer, softer palette.
for COLUMNS in 20 36 80; do
  LINES=30 visible=3 option_left=3 option_right=3 title_rows=('AB')
  mapfile -t hint_rows < <(ez_menu_hint_lines)
  ez_stars_layout 6 1 2 2
  ez_stars_text_layout 6 2 2 0 0 0
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
  distance=$(((col * 1000 / (COLUMNS - 1) + (row - stars_top) * 1000 / (stars_sweep_bottom - stars_top)) / 2))
  arrival=${stars_sweep_arrival[distance]}
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
ez_stars_bar_color 4250
(( stars_r == from_r + (to_r - from_r) * 97 / 1000 ))
(( stars_g == from_g + (to_g - from_g) * 97 / 1000 ))
(( stars_b == from_b + (to_b - from_b) * 97 / 1000 ))
ez_stars_bar_color 4500
(( stars_r == from_r + (to_r - from_r) / 2 ))
(( stars_g == from_g + (to_g - from_g) / 2 ))
(( stars_b == from_b + (to_b - from_b) / 2 ))
ez_stars_bar_color 4750
(( stars_r == from_r + (to_r - from_r) * 902 / 1000 ))
(( stars_g == from_g + (to_g - from_g) * 902 / 1000 ))
(( stars_b == from_b + (to_b - from_b) * 902 / 1000 ))
ez_stars_bar_color 5000
[[ $stars_r == "$to_r" && $stars_g == "$to_g" && $stars_b == "$to_b" ]]
settled_bg=$stars_bar_bg
ez_stars_bar_color 7000
[[ $stars_bar_bg == "$settled_bg" ]]
printf 'PASS responsive hint sweep and eased status-bar colors\n'

# Invalid settings cannot create division by zero or overlapping sweeps.
EZ_MENU_SWEEP_INTERVAL_MS=0 EZ_MENU_SWEEP_DURATION_MS=nope EZ_MENU_SWEEP_HUE_STEP=-1
EZ_MENU_TWINKLE_ADVANCE_MS=invalid EZ_MENU_TWINKLE_RATE_PERCENT=0
ez_stars_init
[[ $stars_period == 4000 && $stars_duration == 1467 && $stars_step == random ]]
[[ $stars_twinkle_advance == 500 && $stars_twinkle_rate == 250 && $stars_twinkle_delay == 200 ]]
printf 'PASS invalid animation settings use safe defaults\n'

# Advancing translates the same curve; the rate changes waiting times, not weights.
for instant in 0 500 1500 3000 3999; do
  stars_twinkle_advance=0
  ez_stars_twinkle_weight "$((instant + 500))"
  baseline_weight=$stars_spawn_weight
  stars_twinkle_advance=500
  ez_stars_twinkle_weight "$instant"
  [[ $stars_spawn_weight == "$baseline_weight" ]]
done
for rate in 100 250; do
  EZ_MENU_TWINKLE_RATE_PERCENT=$rate
  ez_stars_init
  stars_cells=() stars_char=() stars_text_char=()
  RANDOM=2103
  total_wait=0
  for ((trial = 0; trial < 1000; trial++)); do
    stars_next=0
    ez_stars_tick 5000
    total_wait=$((total_wait + stars_next - 5000))
  done
  if (( rate == 100 )); then
    base_wait=$total_wait baseline_weight=$stars_spawn_weight
  else
    fast_wait=$total_wait
    [[ $stars_spawn_weight == "$baseline_weight" ]]
  fi
done
(( fast_wait * 100 > base_wait * 36 && fast_wait * 100 < base_wait * 44 ))
printf 'PASS earlier probability cycle and multiplicative spawn frequency\n'

# The front starts slowly, crosses the middle quickly, and slows at the end.
EZ_MENU_SWEEP_DURATION_MS=1000
ez_stars_init
COLUMNS=101 stars_top=1 stars_bottom=101 stars_sweep_bottom=101
ez_stars_sweep 1 50 1 200
[[ $stars_white == 0 && $stars_color_cycle == 0 ]]
ez_stars_sweep 101 50 1 500
(( stars_white > 0 ))
# Arrival changes; each position still takes 60 ms to peak and 240 ms to fade.
for position in '1 50 280' '101 50 420'; do
  read -r row col arrival <<< "$position"
  ez_stars_sweep "$row" "$col" 1 "$((arrival + 60))"
  [[ $stars_white == 1000 ]]
  ez_stars_sweep "$row" "$col" 1 "$((arrival + 300))"
  [[ $stars_white == 0 && $stars_color_cycle == 1 ]]
done
for duration in 300 1000 1467 2500; do
  EZ_MENU_SWEEP_DURATION_MS=$duration
  ez_stars_init
  travel=$stars_travel previous=-1
  [[ ${stars_sweep_arrival[0]} == 0 && ${stars_sweep_arrival[1000]} == "$travel" ]]
  (( stars_sweep_arrival[500] == travel / 2 ))
  (( stars_sweep_arrival[250] > travel * 3 / 8 && stars_sweep_arrival[750] < travel * 5 / 8 ))
  for arrival in "${stars_sweep_arrival[@]}"; do
    (( arrival >= previous && arrival <= travel ))
    previous=$arrival
  done
done
printf 'PASS eased diagonal movement, unchanged flash durations, and scalable arrival times\n'

# Default timing keeps the previous cubic's 3/700 peak speed. Broad quarter-
# distance bands now get ~467 ms each instead of the old ~278 ms.
EZ_MENU_SWEEP_DURATION_MS=1467
ez_stars_init
[[ $stars_rise == 60 && $stars_tail == 240 && $stars_travel == 1167 ]]
(( stars_sweep_arrival[250] >= 466 && stars_sweep_arrival[750] <= 701 ))
ez_stars_sweep_ease 499
before=$stars_eased
ez_stars_sweep_ease 500
distance=$((stars_eased - before))
# Finite differences allow integer coordinate rounding; target ~4.286/s.
(( distance * 1000000 / stars_travel >= 4200 ))
(( distance * 1000000 / stars_travel <= 4400 ))
for progress in 100 250 400 499; do
  ez_stars_sweep_ease "$progress"
  before=$stars_eased
  ez_stars_sweep_ease "$((1000 - progress))"
  (( stars_eased + before >= 999 && stars_eased + before <= 1000 ))
done
printf 'PASS broad slow edges, symmetric movement, and preserved default peak speed\n'

# Count real generated stars over many columns, including protected text rows.
EZ_MENU_HORIZON_DENSITY_PERCENT=600
ez_stars_init
COLUMNS=800 LINES=30 visible=4 option_left=350 option_right=350
hint_rows=('controls')
RANDOM=4871
ez_stars_layout 10 5 53 2
[[ ${stars_density[$stars_top]} == 1000 && ${stars_density[$stars_bottom]} == 6000 ]]
top_count=0 bottom_count=0
for cell in "${!stars_char[@]}"; do
  row=$((cell / COLUMNS + 1))
  if (( row == stars_top )); then top_count=$((top_count + 1)); fi
  if (( row == stars_bottom )); then bottom_count=$((bottom_count + 1)); fi
done
(( top_count > 25 && top_count < 80 && bottom_count > 250 && bottom_count < 360 ))
(( bottom_count > top_count * 4 ))
for ((row = stars_top + 1; row <= stars_bottom; row++)); do
  (( stars_density[row] >= stars_density[row-1] ))
done
(( stars_fade[stars_bottom] > 5 ))
# Equal-size top/bottom samples isolate spatial bias from row width and masking.
stars_cells=()
for ((col = 0; col < 80; col++)); do
  stars_cells+=("$(((stars_top - 1) * COLUMNS + col))" "$(((stars_bottom - 1) * COLUMNS + col))")
done
stars_char=() stars_birth=() stars_text_char=() stars_occluded=()
ez_stars_twinkle_timing
[[ $stars_twinkle_delay == 200 && $stars_horizon_delay == 80 ]]
# At the real 20 FPS cadence the extra stream must not steal baseline top births.
for horizon in 0 1; do
  ez_stars_init
  ez_stars_twinkle_timing
  (( horizon )) || stars_horizon_delay=0
  upper=0 lower=0 RANDOM=2161
  for ((instant = 0; instant < 200000; instant += 50)); do
    stars_birth=() stars_char=()
    ez_stars_tick "$instant"
    (( ${#stars_birth[@]} <= 1 ))
    for cell in "${!stars_birth[@]}"; do
      if (( cell / COLUMNS + 1 == stars_top )); then upper=$((upper + 1)); else lower=$((lower + 1)); fi
    done
  done
  if (( ! horizon )); then base_upper=$upper base_lower=$lower; fi
done
(( upper * 100 > base_upper * 80 && upper * 100 < base_upper * 120 ))
(( lower > base_lower * 2 ))
EZ_MENU_HORIZON_DENSITY_PERCENT=100
ez_stars_init
ez_stars_layout 10 5 53 2
for density in "${stars_density[@]}"; do [[ $density == 1000 ]]; done
printf 'PASS denser dim horizon, weighted single twinkles, and flat-density override\n'

# Text occludes glyph cells only; an underlying star survives navigation, and
# hint spaces stay part of the field on repairs as well as ticks.
COLUMNS=80 LINES=24 visible=1 title_rows=('T') hint_rows=('Go now')
labels=('A B') menu_enabled=(1) menu_disabled_notes=()
read -r marker_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "${labels[@]}")
ez_stars_layout 10 1 1 2
ez_stars_text_layout 10 1 2 0 0 0 "${labels[@]}"
glyph=$((12 * COLUMNS + option_left + 2)) gap=$((glyph + 1))
[[ ${stars_occluded[$glyph]} == 1 && ! ${stars_occluded[$gap]+present} ]]
stars_char=([$glyph]='*' [$gap]='+') stars_palette=([$glyph]=0 [$gap]=0)
stars_birth=() stars_seen=() stars_saturation=() stars_hue_offset=()
stars_next=999999 stars_horizon_next=999999
ez_stars_text_layout 10 1 2 0 0 0 "${labels[@]}"
ez_stars_tick 0
[[ ! ${stars_seen[$glyph]+present} && ! ${stars_char[$gap]+present} ]]
[[ ${stars_char[$glyph]} == '*' ]]
rendered=$(ez_menu_overlay_text 13 "$((option_left + 2))" 'A B' "$C_WHITE" "$C_BOLD")
[[ $rendered == *"${C_BOLD}A"* && $rendered == *"${C_BOLD}B"* ]]
ez_stars_text_layout 10 1 2 0 0 0 ''
ez_stars_tick 10
[[ ${stars_seen[$glyph]} == *':*' ]]
# Even if every candidate is under foreground text, no birth can overwrite it.
ez_stars_text_layout 10 1 2 0 0 0 'A B'
stars_cells=("$glyph") stars_char=() stars_birth=()
stars_next=0 stars_horizon_next=0
ez_stars_tick 2000
[[ ${#stars_birth[@]} == 0 ]]
printf 'PASS clear option spaces, foreground occlusion, and preserved underlying glyph stars\n'

# The baseline multiplier changes quantity, not the horizon weights or twinkle
# clock. A large sample distinguishes half the former population from 50% fill.
(
  COLUMNS=800 LINES=30 visible=4 hint_rows=('controls')
  EZ_MENU_HORIZON_DENSITY_PERCENT=600
  for percent in 100 50 0; do
    EZ_MENU_STAR_DENSITY_PERCENT=$percent
    ez_stars_init
    RANDOM=2941
    ez_stars_layout 10 5 53 2
    case $percent in
      100) original_count=${#stars_char[@]} ;;
      50) half_count=${#stars_char[@]} ;;
      0) [[ ${#stars_char[@]} == 0 ]] ;;
    esac
    [[ ${stars_density[$stars_top]} == 1000 && ${stars_density[$stars_bottom]} == 6000 ]]
    [[ $stars_twinkle_rate == 250 ]]
  done
  (( half_count * 100 > original_count * 45 && half_count * 100 < original_count * 55 ))
)
printf 'PASS half baseline quantity with unchanged horizon weights and twinkle rate\n'

(
  EZ_MENU_STAR_DENSITY_PERCENT=50 EZ_MENU_HORIZON_DENSITY_PERCENT=600
  COLUMNS=80 LINES=24 visible=4 hint_rows=('controls')
  ez_stars_init
  ez_stars_layout 10 5 53 2
  stars_text_char=() stars_occluded=() stars_char=([160]='*')
  stars_palette=([160]=0) stars_seen=() stars_birth=()
  stars_next=999999 stars_horizon_next=999999
  ez_stars_build_work
  ez_stars_spawn 160 100
  ez_stars_tick 999
  [[ ${stars_replenish[160]} == 1 && ${stars_birth[160]} == 100 ]]
  ez_stars_tick 1000
  [[ ! ${stars_char[160]+present} && ${#stars_char[@]} == 1 && ${#stars_birth[@]} == 0 ]]
  replacement=${!stars_char[*]}
  [[ $replacement != 160 && ${stars_seen[$replacement]+present} && ! ${stars_band_member[replacement]+present} ]]
  before=${stars_seen[$replacement]}
  ez_stars_tick 5600
  [[ ${stars_seen[$replacement]} != "$before" && ${stars_band_member[replacement]} == 1 ]]
  # A twinkle on empty space owes no star; consuming the replacement preserves
  # population again, and must never restore it at the same coordinate.
  ez_stars_spawn 160 6000
  ez_stars_tick 6900
  [[ ${#stars_char[@]} == 1 && ${stars_char[$replacement]+present} ]]
  ez_stars_spawn "$replacement" 7000
  ez_stars_tick 7900
  [[ ${#stars_char[@]} == 1 && ! ${stars_char[$replacement]+present} ]]
  # Rejection sampling uses the original row weights for replacement locations.
  stars_cells=(160 "$(((stars_bottom - 1) * COLUMNS))")
  upper=0 lower=0 RANDOM=9017
  for ((trial = 0; trial < 1000; trial++)); do
    stars_char=() stars_birth=() stars_replace_head=0 stars_replace_tail=1
    stars_replace_queue=([0]=999999)
    ez_stars_replace
    for cell in "${!stars_char[@]}"; do
      if (( cell == 160 )); then upper=$((upper + 1)); else lower=$((lower + 1)); fi
    done
  done
  (( lower > upper * 4 && lower < upper * 8 ))
  # A full/one-cell field defers its debt instead of reviving the consumed star.
  stars_cells=(160) stars_char=() stars_birth=()
  stars_replace_head=0 stars_replace_tail=1 stars_replace_queue=([0]=160)
  ez_stars_replace
  [[ ${#stars_char[@]} == 0 && $stars_replace_tail == 1 ]]

  # Across many overlapping births and complete sweeps, every initial baseline
  # star is either present, temporarily consumed, or queued for replenishment.
  ez_stars_init
  ez_stars_layout 10 5 53 2
  stars_text_char=() stars_occluded=()
  initial_population=${#stars_char[@]}
  ez_stars_build_work
  for ((instant = 0; instant < 20000; instant += 50)); do
    ez_stars_tick "$instant"
    population=$((${#stars_char[@]} - ${#stars_birth[@]} + ${#stars_replenish[@]} + stars_replace_tail - stars_replace_head))
    (( population == initial_population ))
  done
  # Repeated consumption must not leave stale or duplicate sweep work behind.
  indexed=()
  for members in "${stars_star_band[@]}"; do
    for cell in $members; do
      [[ ${stars_char[$cell]+present} && ! ${stars_birth[$cell]+present} && ! ${stars_replacement_birth[cell]+present} && ! ${indexed[cell]+present} ]]
      indexed[cell]=1
    done
  done
)
printf 'PASS population replacement at weighted empty cells, future sweeps, and full-field deferral\n'

(
  COLUMNS=80 LINES=24 visible=4 hint_rows=('controls')
  ez_stars_init
  ez_stars_layout 10 5 53 2
  stars_text_char=() stars_occluded=() stars_birth=()
  stars_next=999999 stars_horizon_next=999999
  previous=256
  for ((row = stars_top; row <= stars_bottom; row++)); do
    cell=$(((row - 1) * COLUMNS))
    stars_char=([$cell]='*') stars_palette=([$cell]=0) stars_seen=()
    distance=$(((row - stars_top) * 1000 / (stars_sweep_bottom - stars_top) / 2))
    instant=$((4000 + stars_sweep_arrival[distance] + stars_rise))
    ez_stars_tick "$instant"
    peak=${stars_peak[row]}
    level=$((255 * peak / 1000))
    [[ ${stars_seen[$cell]} == "$level;$level;$level:1:*" ]]
    (( level > 0 && level <= previous ))
    if (( (row - stars_top) * 10 < (stars_bottom - stars_top + 1) * 3 )); then
      [[ $level == 255 ]]
    fi
    previous=$level
  done
  [[ ${stars_peak[$stars_top]} == 1000 ]]
  (( stars_peak[stars_bottom] == 10000 / (7 * (stars_bottom - stars_top + 1)) ))
)
printf 'PASS uniform white upper-30-percent shimmer and exclusive black endpoint\n'

(
  COLUMNS=80 LINES=24 visible=2 title_rows=('T') hint_rows=('Go now')
  labels=('A B' 'Longer Label') menu_enabled=(1 0) menu_disabled_notes=([1]='(not ready)')
  read -r marker_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "${labels[@]}")
  ez_stars_init
  ez_stars_layout 10 1 1 2 2 0 "${labels[@]}"
  gap=$((12 * COLUMNS + option_left + 3)) marker_gap=$((gap - 2)) allowed=$((gap + 30))
  [[ ${stars_baseline_blocked[gap]} == 1 && ${stars_baseline_blocked[marker_gap]} == 1 ]]
  for cell in "${!stars_baseline_blocked[@]}"; do [[ ! ${stars_char[$cell]+present} ]]; done
  ez_stars_text_layout 10 1 2 0 0 0 "${labels[@]}"
  # Replacement sampling cannot pick either class of protected whitespace.
  stars_char=() stars_birth=() stars_cells=("$gap" "$marker_gap" "$allowed")
  stars_replace_queue=([0]=161) stars_replace_head=0 stars_replace_tail=1
  for ((trial = 0; trial < 20 && stars_replace_tail; trial++)); do ez_stars_replace 1000; done
  [[ ${stars_char[$allowed]+present} && ! ${stars_char[$gap]+present} && ! ${stars_char[$marker_gap]+present} ]]
  # The baseline exclusion does not change the existing twinkle spawn mask.
  stars_cells=("$gap") stars_spawned=0
  ez_stars_try_spawn 1100 0
  [[ ${stars_birth[$gap]} == 1100 ]]
  # Scrolling onto a new internal space relocates an underlying baseline star.
  stars_birth=() stars_char=([$gap]='*') stars_replacement_birth=()
  ez_stars_text_layout 10 1 2 0 0 0 'ABCD' 'Longer Label'
  [[ ${stars_char[$gap]+present} && ! ${stars_baseline_blocked[gap]+present} ]]
  ez_stars_text_layout 10 1 2 0 0 0 "${labels[@]}"
  [[ ! ${stars_char[$gap]+present} && ${stars_clear_pending[gap]} == 1 && $stars_replace_tail == 1 ]]
  stars_cells=("$allowed") stars_char=() stars_next=999999 stars_horizon_next=999999
  ez_stars_build_work
  ez_stars_tick 2000
  [[ ${stars_char[$allowed]+present} && ${#stars_clear_pending[@]} == 0 ]]
  # A note that no longer fits must not leave its old whitespace exclusions.
  COLUMNS=12
  read -r marker_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "${labels[@]}")
  ez_stars_layout 10 1 1 2 2 0 "${labels[@]}"
  [[ ${#stars_baseline_blocked[@]} == 4 ]]
  for cell in "${!stars_baseline_blocked[@]}"; do
    (( cell / COLUMNS + 1 >= 13 && cell / COLUMNS + 1 <= 14 ))
    (( cell % COLUMNS >= option_left + 1 && cell % COLUMNS < option_left + 2 + label_width ))
  done
)
printf 'PASS initial/replacement option-space exclusions, unchanged twinkles, and scroll relocation\n'

(
  COLUMNS=80 LINES=24 visible=4 hint_rows=('controls')
  ez_stars_init
  ez_stars_layout 10 5 53 2
  stars_cells=(160) stars_char=() stars_birth=() stars_text_char=() stars_occluded=()
  stars_next=999999 stars_horizon_next=999999
  stars_replace_queue=([0]=161) stars_replace_head=0 stars_replace_tail=1
  ez_stars_build_work
  RANDOM=419
  ez_stars_replace 1000
  [[ ${stars_replacement_birth[160]} == 1000 && ! ${stars_birth[160]+present} ]]
  glyph=${stars_char[160]}
  ez_stars_color "${stars_palette[160]}" 0 0 100 1000 "${stars_saturation[160]}" "${stars_hue_offset[160]}"
  full_red=$stars_r full_green=$stars_g full_blue=$stars_b
  (( full_red != full_green || full_green != full_blue ))
  previous=-1
  for age in 0 100 250 400 499 500; do
    ez_stars_tick "$((1000 + age))"
    IFS=';:' read -r red green blue style actual_glyph <<< "${stars_seen[160]}"
    [[ $actual_glyph == "$glyph" && $style == 0 ]]
    (( red >= previous && red <= full_red && green <= full_green && blue <= full_blue ))
    previous=$red
    case $age in
      0) [[ $red == 0 && $green == 0 && $blue == 0 ]] ;;
      100) (( red * 5 < full_red )) ;;
      250) (( full_red - red * 2 <= 1 && full_green - green * 2 <= 1 && full_blue - blue * 2 <= 1 )) ;;
      400) (( red * 5 > full_red * 4 )) ;;
      500) [[ $red == "$full_red" && $green == "$full_green" && $blue == "$full_blue" && ! ${stars_replacement_birth[160]+present} ]] ;;
    esac
  done
  ez_stars_tick 1600
  [[ -z $stars_output ]]
  # The global sweep still whitens/bolds a fading star, scaled by its intensity.
  stars_replacement_birth[160]=4000
  ez_stars_build_work
  ez_stars_tick 4060
  IFS=';:' read -r red green blue style actual_glyph <<< "${stars_seen[160]}"
  [[ $red == "$green" && $green == "$blue" && $style == 1 && $actual_glyph == "$glyph" ]]
  (( red > 0 && red < 255 ))
  # Consuming a still-fading replacement transfers its one baseline-star debt.
  ez_stars_spawn 160 4100
  [[ ! ${stars_replacement_birth[160]+present} && ${stars_replenish[160]} == 1 ]]
  # Fades hidden by text also finish; revealing one paints the settled star.
  stars_birth=() stars_replenish=() stars_replacement_birth=([160]=6000)
  stars_occluded=([160]=1)
  ez_stars_build_work
  ez_stars_tick 6500
  [[ ! ${stars_replacement_birth[160]+present} ]]
  stars_occluded=() stars_work_dirty=1
  ez_stars_tick 6550
  [[ ${stars_seen[160]+present} && -n $stars_output ]]
)
printf 'PASS 500 ms eased replacement color fade, final frame, shimmer, and hidden/collision cleanup\n'

(
  COLUMNS=80 LINES=24 visible=4 hint_rows=('controls')
  for hue_step in 0 1 74 359 360 random; do
    EZ_MENU_SWEEP_HUE_STEP=$hue_step
    ez_stars_init
    ez_stars_layout 10 5 53 2
    stars_char=([160]='*') stars_palette=([160]=0) stars_saturation=([160]=700) stars_hue_offset=([160]=0)
    stars_birth=() stars_text_char=() stars_occluded=()
    stars_next=999999999 stars_horizon_next=999999999
    ez_stars_build_work
    for cycle in 358 359 360 361 720 16383 16384 16385; do
      ez_stars_prefetch "$((cycle - 1))"
      for phase in 30 120 1600; do
        ez_stars_tick "$((cycle * stars_period + phase))"
        actual=${stars_seen[160]}
        ez_stars_sweep 3 0 "$cycle" "$phase"
        ez_stars_color 0 "$stars_color_cycle" "$stars_white" 100 1000 700 0
        [[ $actual == "$stars_r;$stars_g;$stars_b:"* ]]
      done
    done
  done
  # Zero RGB must be a valid cached color, distinct from a missing cache entry.
  stars_value[0]=0 stars_rgb_cache=() stars_color_pair=() stars_seen=()
  ez_stars_prefetch 800
  ez_stars_tick "$((800 * stars_period + 1600))"
  [[ ${stars_seen[160]} == '0;0;0:0:*' ]]
)
printf 'PASS packed-color cache wraparound, custom hue steps, skipped cycles, and black RGB\n'

(
  EZ_MENU_SWEEP_HUE_STEP=random RANDOM=1967
  ez_stars_init
  declare -a counts=() history=(0)
  previous=0
  for ((cycle = 1; cycle <= 6100; cycle++)); do
    ez_stars_rotation "$cycle"
    rotation=${stars_rotation[cycle % 3]}
    increment=$(((rotation - previous + 360) % 360))
    (( increment >= 60 && increment <= 120 ))
    counts[increment]=$(( ${counts[increment]:-0} + 1 ))
    history[cycle]=$rotation previous=$rotation
  done
  [[ ${#counts[@]} == 61 && ${#stars_rotation[@]} == 3 ]]
  for count in "${counts[@]}"; do (( count > 50 && count < 155 )); done
  # Repeated reads, backwards seeks and prefetch lookahead must share one path.
  for cycle in 6100 6099 10 9 11 5000 4999; do
    ez_stars_rotation "$cycle"
    [[ ${stars_rotation[cycle % 3]} == "${history[cycle]}" ]]
  done
  # Every palette receives the same cumulative rotation, not its own draw.
  for palette in 0 3 4; do
    stars_rgb_cache=()
    ez_stars_color "$palette" 11 0 100 1000
    actual="$stars_r;$stars_g;$stars_b"
    stars_step=${history[11]} stars_rgb_cache=()
    ez_stars_color "$palette" 1 0 100 1000
    [[ "$stars_r;$stars_g;$stars_b" == "$actual" ]]
    stars_step=random
  done
)
printf 'PASS uniform 60–120 degree sweep increments, bounded history, replay, and shared palette rotation\n'

(
  stars_cell_render=()
  normal='100;150;200:0:' strike='40;50;60:9:'
  stars_cell_render=([0]="$normal○" [1]="$strike●" [7]="${normal}m" [10]="${normal}*" [159]="${strike}+" [170]="${normal}." [171]="${normal}:")
  spans=('1 0 80' '1 0 0' '1 1 3' '3 0 30' '1 0 80' '2 75 5')
  for COLUMNS in 1 80; do
    stars_repair_active=0
    dense=$(for span in "${spans[@]}"; do ez_stars_render_span $span; done)
    sparse=$(ez_stars_prepare_repair; for span in "${spans[@]}"; do ez_stars_render_span $span; done)
    [[ $dense == "$sparse" ]]
  done
)
printf 'PASS sparse repairs preserve UTF-8, strike gaps, empty/overlapping spans, and narrow screens\n'

(
  COLUMNS=80 LINES=24 visible=4 hint_rows=('controls')
  # Compare full and partial repair suppression against the ordinary tick. Each
  # run starts from the same seed, including the replacement/twinkle state.
  for limit in -1 0 800; do
    RANDOM=4183
    ez_stars_init
    ez_stars_layout 10 5 53 2
    stars_text_char=() stars_occluded=()
    ez_stars_build_work
    ez_stars_tick 3990
    ez_stars_tick 4750 "$limit"
    repair=$(for ((row = stars_top; row <= stars_bottom; row++)); do ez_stars_render_span "$row" 0 "$COLUMNS"; done)
    if (( limit == -1 )); then reference=$repair;
    else [[ $repair == "$reference" ]]; fi
    if (( limit == 0 )); then [[ -z $stars_output ]]; fi
  done
)
printf 'PASS foreground repairs suppress redundant deltas while retaining exact final cells\n'

(
  COLUMNS=240 LINES=80 visible=48 hint_rows=('controls')
  ez_stars_init
  ez_stars_layout 10 5 53 2
  stars_text_char=() stars_occluded=()
  ez_stars_prefetch 5 "$((stars_period - 1))"
  [[ $stars_prefetch_budget == 128 && $stars_prefetch_cursor == 128 ]]
  ez_stars_prefetch 6 1500
  (( stars_prefetch_budget >= 32 && stars_prefetch_budget <= 128 ))
  [[ $stars_prefetch_cursor == "$stars_prefetch_budget" ]]
)
printf 'PASS bounded adaptive color preparation, including a nearly expired idle window\n'
