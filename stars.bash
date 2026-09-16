#!/usr/bin/env bash
# Stateful star animation. All stars_* variables belong to the chooser subshell.
# Coordinates are terminal cells; foreground glyphs occlude the field.

function ez_stars_now() {
  local clock_value unused fraction
  # Linux/Termux uptime is monotonic and reading it needs no child process.
  if IFS=' ' read -r clock_value unused < /proc/uptime 2>/dev/null; then
    fraction=${clock_value#*.}000
    stars_now=$(( ${clock_value%.*} * 1000 + 10#${fraction:0:3} ))
  else
    clock_value=${EPOCHREALTIME:-$SECONDS.000}
    fraction=${clock_value#*.}000
    stars_now=$(( ${clock_value%.*} * 1000 + 10#${fraction:0:3} ))
  fi
}

function ez_stars_init() {
  stars_repair_active=0
  stars_bar_cycle=-1
  local color code red green blue high low delta hue palette=0 hue_total=0
  local -a levels=(0 95 135 175 215 255)
  stars_period=${EZ_MENU_SWEEP_INTERVAL_MS:-4000}
  stars_duration=${EZ_MENU_SWEEP_DURATION_MS:-1467}
  stars_step=${EZ_MENU_SWEEP_HUE_STEP:-random}
  stars_sat_max=${EZ_MENU_STAR_SATURATION_MAX:-800}
  stars_accent_offset=${EZ_MENU_SWEEP_ACCENT_OFFSET:-180}
  stars_hue_spread=${EZ_MENU_STAR_HUE_SPREAD:-60}
  stars_twinkle_advance=${EZ_MENU_TWINKLE_ADVANCE_MS:-500}
  stars_twinkle_rate=${EZ_MENU_TWINKLE_RATE_PERCENT:-250}
  stars_density_max=${EZ_MENU_HORIZON_DENSITY_PERCENT:-600}
  stars_density_percent=${EZ_MENU_STAR_DENSITY_PERCENT:-50}
  [[ $stars_density_percent =~ ^[0-9]{1,3}$ ]] || stars_density_percent=50
  stars_density_percent=$((10#$stars_density_percent))
  (( stars_density_percent > 100 )) && stars_density_percent=100
  [[ $stars_density_max =~ ^[1-9][0-9]{0,3}$ ]] || stars_density_max=600
  (( stars_density_max < 100 )) && stars_density_max=100
  (( stars_density_max > 800 )) && stars_density_max=800
  stars_density_max=$((stars_density_max * 10))
  [[ $stars_twinkle_advance =~ ^[0-9]{1,5}$ ]] || stars_twinkle_advance=500
  stars_twinkle_advance=$((10#$stars_twinkle_advance))
  [[ $stars_twinkle_rate =~ ^[1-9][0-9]{0,3}$ ]] || stars_twinkle_rate=250
  (( stars_twinkle_rate > 1000 )) && stars_twinkle_rate=1000
  # Scale opportunity frequency, preserving the envelope's peak/trough ratio.
  stars_twinkle_delay=$((50000 / stars_twinkle_rate))
  stars_horizon_delay=0 stars_horizon_next=0
  [[ $stars_hue_spread =~ ^[0-9]{1,3}$ ]] || stars_hue_spread=60
  stars_hue_spread=$((10#$stars_hue_spread))
  (( stars_hue_spread > 360 )) && stars_hue_spread=360
  [[ $stars_period =~ ^[1-9][0-9]{0,5}$ ]] || stars_period=4000
  [[ $stars_duration =~ ^[1-9][0-9]{0,4}$ ]] || stars_duration=1467
  [[ $stars_step =~ ^[0-9]{1,3}$ ]] || stars_step=random
  if [[ $stars_step != random ]]; then stars_step=$((10#$stars_step)); fi
  stars_rotation=(0) stars_rotation_cycle=0 stars_rotation_value=0 stars_pair_epoch=-1
  stars_rotation_seed=0
  if [[ $stars_step == random ]]; then stars_rotation_seed=$((RANDOM * 32768 + RANDOM)); fi
  stars_rotation_state=$stars_rotation_seed
  [[ $stars_sat_max =~ ^[0-9]{1,4}$ ]] || stars_sat_max=800
  stars_sat_max=$((10#$stars_sat_max))
  (( stars_sat_max > 1000 )) && stars_sat_max=1000
  [[ $stars_accent_offset =~ ^[0-9]{1,3}$ ]] || stars_accent_offset=180
  stars_accent_offset=$((10#$stars_accent_offset))
  (( stars_duration < 300 )) && stars_duration=300
  (( stars_period < stars_duration + 1800 )) && stars_period=$((stars_duration + 1800))
  # Keep the 60 ms rise / 240 ms fade when extending movement. Only compress
  # flashes for unusually short custom sweeps so travel still has time to run.
  local flash=300
  (( stars_duration < 600 )) && flash=$((stars_duration / 2))
  stars_travel=$((stars_duration - flash))
  stars_rise=$((flash / 5)) stars_tail=$((flash - stars_rise))
  stars_flash=()
  stars_twinkle_curve=() stars_replacement_curve=() stars_twinkle_glyph=()
  local age amount
  for ((age = 0; age < 900; age++)); do
    if (( age < 120 )); then amount=$((age * 1000 / 120));
    else amount=$((1000 - (age - 120) * 1000 / 780)); fi
    amount=$((amount * amount * (3000 - 2 * amount) / 1000000))
    stars_twinkle_curve[age]=$amount
    if (( amount < 250 )); then stars_twinkle_glyph[age]='.';
    elif (( amount < 650 )); then stars_twinkle_glyph[age]='+';
    else stars_twinkle_glyph[age]='*'; fi
    if (( age < 500 )); then
      amount=$((age * 2))
      stars_replacement_curve[age]=$((amount * amount * (3000 - 2 * amount) / 1000000))
    fi
  done
  for ((age = 0; age < flash; age++)); do
    if (( age < stars_rise )); then amount=$((age * 1000 / stars_rise));
    else amount=$((1000 - (age - stars_rise) * 1000 / stars_tail)); fi
    stars_flash[age]=$((amount * amount * (3000 - 2 * amount) / 1000000))
  done
  stars_arrival_cell=() stars_settled=() stars_text_settled=() stars_geometry_key=''
  stars_work_ready=0 stars_work_dirty=1 stars_last_elapsed=-1 stars_last_phase=0
  stars_text_dirty=()
  stars_star_dirty=() stars_band_member=() stars_replenish=() stars_replace_queue=()
  stars_replacement_birth=()
  stars_baseline_blocked=() stars_clear_pending=()
  stars_replace_head=0 stars_replace_tail=0
  stars_color_pair=()
  stars_prefetch_cycle=-1 stars_prefetch_cursor=0 stars_prefetch_cells=() stars_prefetch_budget=32
  # Invert the movement once; no curve solving in the per-cell frame loop.
  local progress distance=0
  stars_sweep_arrival=()
  for ((progress = 0; progress <= 1000; progress++)); do
    ez_stars_sweep_ease "$progress"
    while (( distance <= stars_eased )); do
      stars_sweep_arrival[distance]=$((stars_travel * progress / 1000))
      distance=$((distance + 1))
    done
  done
  stars_hue=() stars_sat=() stars_value=() stars_rgb_cache=()
  for color in "$C_STAR_BLUE" "$C_STAR_LAVENDER" "$C_STAR_PINK"; do
    red=135 green=135 blue=175
    if [[ $color =~ ^$'\033'\[38\;2\;([0-9]+)\;([0-9]+)\;([0-9]+)m$ ]]; then
      red=$((10#${BASH_REMATCH[1]})) green=$((10#${BASH_REMATCH[2]})) blue=$((10#${BASH_REMATCH[3]}))
    else
      code=${color##*;} code=${code%m}
      if [[ $code =~ ^[0-9]+$ ]] && (( code >= 16 && code <= 255 )); then
        if (( code >= 232 )); then
          red=$((8 + (code - 232) * 10)) green=$red blue=$red
        else
          code=$((code - 16))
          red=${levels[code / 36]} green=${levels[code / 6 % 6]} blue=${levels[code % 6]}
        fi
      fi
    fi
    (( red > 255 )) && red=255
    (( green > 255 )) && green=255
    (( blue > 255 )) && blue=255
    high=$red low=$red
    (( green > high )) && high=$green
    (( blue > high )) && high=$blue
    (( green < low )) && low=$green
    (( blue < low )) && low=$blue
    delta=$((high - low)) hue=0
    if (( delta )); then
      if (( high == red )); then hue=$((60 * (green - blue) / delta));
      elif (( high == green )); then hue=$((120 + 60 * (blue - red) / delta));
      else hue=$((240 + 60 * (red - green) / delta)); fi
    fi
    stars_hue[palette]=$(( (hue + 360) % 360 ))
    stars_sat[palette]=0 stars_value[palette]=$high
    (( high )) && stars_sat[palette]=$((1000 * delta / high))
    palette=$((palette + 1))
  done
  # Average relative to the first hue so a palette crossing 0 degrees works.
  for ((palette = 0; palette < 3; palette++)); do
    hue_total=$((hue_total + (stars_hue[palette] - stars_hue[0] + 540) % 360 - 180))
  done
  hue=$(( (stars_hue[0] + hue_total / 3 + 360) % 360 ))
  stars_hue[0]=$hue stars_hue[1]=$hue stars_hue[2]=$hue
  stars_hue[3]=$(( (hue + stars_accent_offset) % 360 ))
  stars_sat[3]=700 stars_value[3]=255
  stars_hue[4]=${stars_hue[3]} stars_sat[4]=350 stars_value[4]=255
  ez_stars_now
  stars_origin=$stars_now stars_next=$((1 + (RANDOM * 32768 + RANDOM) % stars_twinkle_delay)) stars_cache_cycle=-1
  stars_render_cycle=-1 stars_was_sweeping=0
}

function ez_stars_layout() {
  stars_repair_active=0
  stars_work_ready=0 stars_work_dirty=1
  local banner_count=$1 title_height=$2 title_width=$3 margin=$4
  local total_count=${5:-$visible} page_width=0 page_left page_right page
  local option_start=$((banner_count + 3)) row col cell mask_left mask_right brightness depth
  local option_end=$((option_start + visible - 1)) hint_start=$((option_start + visible + 1)) hint_end
  local title_left=$(( (COLUMNS - title_width) / 2 )) chars='*.+ '
  hint_end=$((hint_start + ${#hint_rows[@]} - 1))
  if (( visible < total_count )); then
    printf -v page '%d-%d of %d' "$total_count" "$total_count" "$total_count"
    page_width=${#page}
  fi
  page_left=$(( (COLUMNS - page_width) / 2 - 3 )) page_right=$(( (COLUMNS + page_width + 1) / 2 + 3 ))
  stars_cells=() stars_char=() stars_palette=() stars_saturation=() stars_hue_offset=()
  stars_birth=() stars_seen=() stars_fade=() stars_density=() stars_cell_render=() stars_text_seen=()
  stars_color_pair=() stars_prefetch_cycle=-1
  stars_star_dirty=() stars_replenish=() stars_replace_queue=()
  stars_replacement_birth=()
  stars_clear_pending=()
  ez_stars_baseline_mask "$banner_count" "${6:-0}" "${label_width:-0}" "${@:7}"
  stars_replace_head=0 stars_replace_tail=0 stars_peak=()
  # Leave the final terminal row free so repainting cannot scroll the screen.
  stars_top=3 stars_bottom=$((hint_end + 2))
  (( stars_bottom >= LINES )) && stars_bottom=$((LINES - 1))
  stars_sweep_bottom=$stars_bottom
  for ((row = stars_top; row <= stars_bottom; row++)); do
    depth=0
    (( stars_bottom > stars_top )) && depth=$(((row - stars_top) * 1000 / (stars_bottom - stars_top)))
    # Preserve the top's 1-in-8 baseline; quadratic density builds a dim horizon.
    stars_density[row]=$((1000 + (stars_density_max - 1000) * depth * depth / 1000000))
    mask_left=$COLUMNS mask_right=$COLUMNS brightness=100
    if (( row >= 3 + margin && row < 3 + margin + title_height )); then
      mask_left=$((title_left - 2)) mask_right=$((title_left + title_width + 2))
    elif (( row == option_end + 1 && page_width )); then
      mask_left=$((page_left + 3)) mask_right=$((page_right - 3))
    elif (( row > banner_count + 1 && row < option_start )); then
      brightness=80
    fi
    if (( row >= option_start )); then
      # Sample [0, 1): the darkest endpoint lies one row beyond the field.
      brightness=$((65 - 60 * (row - option_start) / (stars_bottom - option_start + 1)))
    fi
    stars_fade[row]=$brightness
    # The top 30% peaks at white; the remaining 70% approaches black on [0, 1).
    # Keep at least one RGB step for unusually tall fields (8-bit quantization).
    brightness=$((10000 * (stars_bottom - row + 1) / (7 * (stars_bottom - stars_top + 1))))
    (( brightness > 1000 )) && brightness=1000
    (( brightness < 4 )) && brightness=4
    stars_peak[row]=$brightness
    for ((col = 0; col < COLUMNS; col++)); do
      (( col >= mask_left && col < mask_right )) && continue
      cell=$(( (row - 1) * COLUMNS + col ))
      stars_cells+=("$cell")
      [[ ${stars_baseline_blocked[cell]+present} ]] && continue
      if (( (RANDOM * 32768 + RANDOM) % 800000 < stars_density[row] * stars_density_percent )); then
        stars_char[$cell]=${chars:RANDOM%3:1}
        stars_palette[$cell]=$((RANDOM % 3))
        ez_stars_pick_saturation "$cell"
        ez_stars_pick_hue "$cell"
      fi
    done
  done
}

function ez_stars_baseline_mask() {
  local banner_count=$1 first=$2 width=$3 index row col cell label note
  local -a labels=("${@:4}")
  stars_baseline_blocked=()
  for ((index = first; index < first + visible && index < ${#labels[@]}; index++)); do
    row=$((banner_count + 3 + index - first))
    (( row >= LINES )) && break
    cell=$(((row - 1) * COLUMNS + option_left + 1))
    (( option_left + 1 < COLUMNS )) && stars_baseline_blocked[cell]=1
    label=${labels[index]} note=${menu_disabled_notes[index]-}
    if [[ ${menu_enabled[index]:-1} == 0 && -n $note ]] && (( ${#label} + 1 + ${#note} <= width )); then
      label+=" $note"
    fi
    label=${label:0:width}
    for ((col = 0; col < ${#label}; col++)); do
      [[ ${label:col:1} == ' ' ]] || continue
      cell=$(((row - 1) * COLUMNS + option_left + 2 + col))
      stars_baseline_blocked[cell]=1
    done
  done
}

function ez_stars_pick_hue() {
  local cell=$1 sample
  # Twelve uniforms approximate a normal distribution, sigma ~1000. Reject
  # beyond 3 sigma rather than piling clamped samples onto the endpoints.
  while :; do
    # Keep the exact twelve draws and their order, without dispatching a shell
    # loop/assignment for every draw during field generation or a birth.
    (( sample = -5994 + RANDOM % 1000 + RANDOM % 1000 + RANDOM % 1000
                     + RANDOM % 1000 + RANDOM % 1000 + RANDOM % 1000
                     + RANDOM % 1000 + RANDOM % 1000 + RANDOM % 1000
                     + RANDOM % 1000 + RANDOM % 1000 + RANDOM % 1000, 1 ))
    (( sample >= -3000 && sample <= 3000 )) && break
  done
  stars_hue_offset[$cell]=$((sample * stars_hue_spread / 6000))
}

function ez_stars_pick_saturation() {
  local cell=$1 minimum=${stars_sat[${stars_palette[$1]}]} maximum=$stars_sat_max
  (( maximum < minimum )) && maximum=$minimum
  stars_saturation[$cell]=$((minimum + RANDOM % (maximum - minimum + 1)))
}

# Accent cells are separate from the spawn mask: text can sweep, never twinkle.
function ez_stars_text_layout() {
  stars_repair_active=0
  stars_work_ready=0 stars_work_dirty=1
  local banner_count=$1 title_width=$2 margin=$3 compact=$4 first=$5 selected=$6
  local row col cell line index text style fade hint_width=0 left=$(( (COLUMNS - title_width) / 2 ))
  local -a letters=("${title_rows[@]}")
  local -a old_cells=("${!stars_text_char[@]}")
  local -a old_occluded=("${!stars_occluded[@]}") labels=("${@:7}")
  local label note label_width marker_width block_width indent right_width
  stars_occluded=()
  read -r marker_width label_width block_width indent right_width < <(ez_menu_option_layout "${labels[@]}")
  ez_stars_baseline_mask "$banner_count" "$first" "$label_width" "${labels[@]}"
  # Scrolling can move a label's spaces over existing baseline stars. Relocate
  # those stars through the same weighted replacement queue, keeping population.
  for cell in "${!stars_baseline_blocked[@]}"; do
    [[ ${stars_char[$cell]+present} && ! ${stars_birth[$cell]+present} ]] || continue
    stars_replace_queue[stars_replace_tail]=$cell
    stars_replace_tail=$((stars_replace_tail + 1))
    stars_clear_pending[cell]=1
    unset 'stars_char[$cell]' 'stars_palette[$cell]' 'stars_saturation[$cell]' 'stars_hue_offset[$cell]'
    unset 'stars_replacement_birth[cell]' 'stars_seen[$cell]' 'stars_settled[cell]' 'stars_cell_render[$cell]'
    unset 'stars_color_pair[cell]'
  done
  stars_text_char=() stars_text_style=() stars_text_fade=() stars_text_palette=() stars_text_flash=()
  if (( compact )); then
    text=$(ez_menu_title_text)
    letters=("${text:0:COLUMNS}")
  fi
  for ((line = 0; line < ${#letters[@]}; line++)); do
    row=$((3 + margin + line))
    (( row >= LINES )) && break
    text=${letters[line]}
    for ((col = 0; col < ${#text}; col++)); do
      [[ ${text:col:1} == ' ' ]] && continue
      (( left + col >= COLUMNS )) && break
      cell=$(( (row - 1) * COLUMNS + left + col ))
      stars_text_char[$cell]=${text:col:1} stars_text_style[$cell]=0 stars_text_fade[$cell]=100
      stars_text_flash[$cell]=1
      stars_text_palette[$cell]=3
    done
  done
  for ((index = first; index < first + visible; index++)); do
    row=$((banner_count + 3 + index - first))
    (( row >= LINES )) && break
    style=0 fade=100
    if [[ ${menu_enabled[index]:-1} == 0 ]]; then style=9 fade=60;
    elif (( index == selected )); then style=1; fi
    # Store each UTF-8 marker as one terminal cell, even in the C locale.
    text='○'
    (( index == selected )) && text='●'
    cell=$(( (row - 1) * COLUMNS + option_left ))
    stars_text_char[$cell]=$text stars_text_style[$cell]=$style stars_text_fade[$cell]=$fade
    stars_text_palette[$cell]=3
    label=${labels[index]-} note=${menu_disabled_notes[index]-}
    if [[ ${menu_enabled[index]:-1} == 0 && -n $note ]] && (( ${#label} + 1 + ${#note} <= label_width )); then
      label+=" $note"
    fi
    label=${label:0:label_width}
    for ((col = 0; col < ${#label}; col++)); do
      [[ ${label:col:1} == ' ' ]] && continue
      cell=$(((row - 1) * COLUMNS + option_left + 2 + col))
      stars_occluded[$cell]=1
    done
  done
  for text in "${hint_rows[@]}"; do (( ${#text} > hint_width )) && hint_width=${#text}; done
  left=$(( (COLUMNS - hint_width) / 2 ))
  (( left < 0 )) && left=0
  stars_sweep_bottom=$stars_bottom
  for ((line = 0; line < ${#hint_rows[@]}; line++)); do
    row=$((banner_count + visible + 4 + line))
    (( row >= LINES )) && break
    (( row > stars_sweep_bottom )) && stars_sweep_bottom=$row
    text=${hint_rows[line]}
    for ((col = 0; col < ${#text} && left + col < COLUMNS; col++)); do
      [[ ${text:col:1} == ' ' ]] && continue
      cell=$(( (row - 1) * COLUMNS + left + col ))
      stars_text_char[$cell]=${text:col:1} stars_text_style[$cell]=0 stars_text_fade[$cell]=55
      stars_text_palette[$cell]=4
    done
  done
  for cell in "${old_cells[@]}" "${old_occluded[@]}"; do
    if [[ ! ${stars_text_char[$cell]+present} ]]; then
      unset 'stars_text_seen[$cell]' 'stars_cell_render[$cell]' 'stars_seen[$cell]' 'stars_settled[$cell]'
    fi
  done
  for cell in "${!stars_text_char[@]}"; do
    if [[ ${stars_text_seen[$cell]#*:} != "${stars_text_style[$cell]}:${stars_text_char[$cell]}" ]]; then
      unset 'stars_text_seen[$cell]' 'stars_text_settled[$cell]'
    fi
  done
  ez_stars_twinkle_timing
}

# Keep the uniform baseline clock; add density-weighted opportunities for the
# excess above that baseline. Baseline births take priority so a busy horizon
# never steals a top-row opportunity under the one-birth-per-frame limit.
function ez_stars_twinkle_timing() {
  local cell row total=0 count=0
  for cell in "${stars_cells[@]}"; do
    [[ ${stars_text_char[$cell]+present} || ${stars_occluded[$cell]+present} ]] && continue
    row=$((cell / COLUMNS + 1))
    total=$((total + ${stars_density[row]:-1000} - 1000)) count=$((count + 1))
  done
  stars_twinkle_delay=$((50000 / stars_twinkle_rate))
  stars_horizon_delay=0
  if (( total )); then
    stars_horizon_delay=$((50000000 * count / (stars_twinkle_rate * total)))
    (( stars_horizon_delay < 1 )) && stars_horizon_delay=1
  fi
  return 0
}

# Rebuild only when the viewport or foreground text changes. Buckets are indexed
# in 16 ms buckets, so a tick visits the moving band rather than the field.
# Each cell still uses its exact millisecond arrival: buckets only select work.
function ez_stars_build_work() {
  local cell row col distance arrival bottom=${stars_sweep_bottom:-$stars_bottom}
  stars_star_band=() stars_text_band=() stars_arrival_cell=() stars_band_member=()
  for cell in "${!stars_char[@]}" "${!stars_text_char[@]}"; do
    row=$((cell / COLUMNS + 1)) col=$((cell % COLUMNS))
    distance=$(((col * 1000 / (COLUMNS > 1 ? COLUMNS - 1 : 1) + (row - stars_top) * 1000 / (bottom > stars_top ? bottom - stars_top : 1)) / 2))
    stars_arrival_cell[cell]=${stars_sweep_arrival[distance]}
  done
  for cell in "${!stars_char[@]}"; do
    [[ ${stars_text_char[$cell]+present} || ${stars_occluded[$cell]+present} ]] && continue
    [[ ${stars_birth[$cell]+present} || ${stars_replacement_birth[cell]+present} ]] && continue
    arrival=$((stars_arrival_cell[cell] / 16))
    stars_star_band[arrival]+=" $cell"
    stars_band_member[cell]=1
  done
  for cell in "${!stars_text_char[@]}"; do
    arrival=$((stars_arrival_cell[cell] / 16))
    stars_text_band[arrival]+=" $cell"
  done
  stars_geometry_key="$COLUMNS:$stars_top:$bottom"
  stars_work_ready=1 stars_work_dirty=1
}

# Arrow movement changes marker weight/glyph, not the field or its text mask.
function ez_stars_select() {
  local first=$1 selected=$2 banner_count=$3 index cell style fade char
  for ((index = first; index < first + visible; index++)); do
    cell=$(((banner_count + 2 + index - first) * COLUMNS + option_left))
    style=0 fade=100 char='○'
    if [[ ${menu_enabled[index]:-1} == 0 ]]; then style=9 fade=60;
    elif (( index == selected )); then style=1 char='●'; fi
    if [[ ${stars_text_char[$cell]-} != "$char" || ${stars_text_style[$cell]-} != "$style" || ${stars_text_fade[$cell]-} != "$fade" ]]; then
      stars_text_char[$cell]=$char stars_text_style[$cell]=$style stars_text_fade[$cell]=$fade
      unset 'stars_text_seen[$cell]' 'stars_text_settled[cell]'
      stars_text_dirty[cell]=1
    fi
  done
}

# Smoothstep easing, in thousandths, without floating-point subprocesses.
function ez_stars_ease() {
  local amount=$1
  (( amount < 0 )) && amount=0
  (( amount > 1000 )) && amount=1000
  stars_eased=$((amount * amount * (3000 - 2 * amount) / 1000000))
}

# Broad slow shoulders: the first/last quarter of diagonal distance each takes
# 40% of travel time. Unlike simply raising an easing exponent, this slows broad
# edge bands, not just tiny corners. Velocity is continuous at both joins.
# Peak slope is 5 (previous cubic: 3); 1167 ms travel preserves the old 700 ms
# travel's peak speed to rounding precision. Light fades remain independent.
function ez_stars_sweep_ease() {
  local amount=$1 reverse=0 position
  (( amount < 0 )) && amount=0
  (( amount > 1000 )) && amount=1000
  if (( amount > 500 )); then
    amount=$((1000 - amount)) reverse=1
  fi
  if (( amount <= 400 )); then
    position=$((amount * amount * 25))
  else
    amount=$((amount - 400))
    position=$((4000000 + 2 * (amount * 10000 + amount * amount * amount)))
  fi
  # Round after reflection, so the endpoint cannot arrive prematurely.
  (( reverse )) && position=$((16000000 - position))
  stars_eased=$((position / 16000))
  return 0
}

# One independent random stream chooses shared sweep increments. Keep only the
# previous/current/next rotations; replay the seed if a caller seeks backwards.
# Rejection sampling avoids modulo bias among the 61 inclusive degree choices.
function ez_stars_rotation() {
  local target=$1
  if (( target < stars_rotation_cycle - 2 )); then
    stars_rotation=(0) stars_rotation_cycle=0 stars_rotation_value=0
    stars_rotation_state=$stars_rotation_seed
  fi
  while (( stars_rotation_cycle < target )); do
    while :; do
      stars_rotation_state=$(((1664525 * stars_rotation_state + 1013904223) & 4294967295))
      (( stars_rotation_state < 4294967239 )) && break
    done
    (( stars_rotation_value = (stars_rotation_value + 60 + stars_rotation_state % 61) % 360,
       stars_rotation_cycle += 1,
       stars_rotation[stars_rotation_cycle % 3] = stars_rotation_value, 1 ))
  done
}

function ez_stars_palette_rgb() {
  local palette=$1 cycle=$2
  local saturation=${3:-${stars_sat[palette]}} offset=${4:-0}
  local key="$palette:$cycle:$saturation:$offset" hue chroma secondary minimum value red green blue rotation
  if [[ ! ${stars_rgb_cache[$key]+present} ]]; then
    if [[ $stars_step == random ]]; then
      if (( cycle > stars_rotation_cycle || cycle < stars_rotation_cycle - 2 )); then
        ez_stars_rotation "$cycle"
      fi
      rotation=${stars_rotation[cycle % 3]}
    else rotation=$((cycle * stars_step)); fi
    (( hue = (stars_hue[palette] + rotation + offset + 360) % 360,
       value = stars_value[palette], chroma = value * saturation / 1000,
       secondary = hue % 120 - 60, secondary = secondary < 0 ? -secondary : secondary,
       secondary = chroma * (60 - secondary) / 60, minimum = value - chroma, 1 ))
    case $((hue / 60)) in
      0) red=$chroma green=$secondary blue=0 ;;
      1) red=$secondary green=$chroma blue=0 ;;
      2) red=0 green=$chroma blue=$secondary ;;
      3) red=0 green=$secondary blue=$chroma ;;
      4) red=$secondary green=0 blue=$chroma ;;
      5) red=$chroma green=0 blue=$secondary ;;
    esac
    stars_rgb_cache[$key]=$((((red + minimum) << 16) | ((green + minimum) << 8) | (blue + minimum)))
  fi
  stars_rgb_value=${stars_rgb_cache[$key]}
}

function ez_stars_color() {
  local palette=$1 cycle=$2 white=$3 fade=$4 intensity=$5 value
  ez_stars_palette_rgb "$palette" "$cycle" "${6:-${stars_sat[palette]}}" "${7:-0}"
  # Packed RGB avoids a here-string pipe/read for every colored cell.
  value=$stars_rgb_value
  (( stars_r = ((value >> 16) * (1000 - white) + 255 * white) * fade * intensity / 100000000,
     stars_g = (((value >> 8) & 255) * (1000 - white) + 255 * white) * fade * intensity / 100000000,
     stars_b = ((value & 255) * (1000 - white) + 255 * white) * fade * intensity / 100000000, 1 ))
  return 0
}

function ez_stars_spawn() {
  local cell=$1 elapsed=$2
  # The consumed star never returns at this position. Remember to replenish it
  # elsewhere after the twinkle, while births on empty cells owe no replacement.
  if [[ ${stars_char[$cell]+present} && ! ${stars_birth[$cell]+present} ]]; then
    stars_replenish[cell]=1
  fi
  if [[ ${stars_band_member[cell]:-0} == 1 ]]; then
    local bucket=$((stars_arrival_cell[cell] / 16)) members
    # Active twinkles already have their own work list. Remove the old baseline
    # entry instead of accumulating empty positions in the sweep buckets.
    members="${stars_star_band[bucket]} "
    members=${members/" $cell "/ }
    stars_star_band[bucket]=${members% }
    unset 'stars_band_member[cell]'
  fi
  stars_birth[$cell]=$elapsed
  unset 'stars_replacement_birth[cell]'
  stars_char[$cell]='.'
  stars_palette[$cell]=$((RANDOM % 3))
  ez_stars_pick_saturation "$cell"
  ez_stars_pick_hue "$cell"
  unset 'stars_settled[$cell]'
  unset 'stars_color_pair[cell]'
}

# Retire twinkles before choosing new births, including ones occluded by text.
# Pending replacements use a bounded queue and retry if no other empty spot exists.
function ez_stars_retire() {
  local elapsed=$1 cell
  # Complete even hidden fades. Dirty the final frame so idle/settled shortcuts
  # cannot leave a star just below its full brightness after the timer expires.
  for cell in "${!stars_replacement_birth[@]}"; do
    (( elapsed - stars_replacement_birth[cell] >= 500 )) || continue
    unset 'stars_replacement_birth[cell]' 'stars_seen[$cell]' 'stars_settled[cell]'
    stars_star_dirty[cell]=1
    ez_stars_index_baseline "$cell"
  done
  for cell in "${!stars_birth[@]}"; do
    (( elapsed - stars_birth[$cell] >= 900 )) || continue
    if [[ ${stars_replenish[cell]:-0} == 1 ]]; then
      stars_replace_queue[stars_replace_tail]=$cell
      stars_replace_tail=$((stars_replace_tail + 1))
    fi
    if [[ ! ${stars_text_char[$cell]+present} ]]; then
      unset 'stars_cell_render[$cell]'
      [[ ${stars_occluded[$cell]+present} ]] || updates[cell]=':0: '
    fi
    unset 'stars_birth[$cell]' 'stars_char[$cell]' 'stars_palette[$cell]' 'stars_saturation[$cell]' 'stars_seen[$cell]' 'stars_hue_offset[$cell]'
    unset 'stars_color_pair[cell]' 'stars_settled[cell]' 'stars_replenish[cell]'
  done
}

function ez_stars_replace() {
  local elapsed=${1:-0}
  local cell row origin attempt
  local count=${#stars_cells[@]} chars='*.+ '
  (( count && stars_replace_head < stars_replace_tail )) || return 0
  origin=${stars_replace_queue[stars_replace_head]}
  for ((attempt = 0; attempt < 32; attempt++)); do
    cell=${stars_cells[(RANDOM * 32768 + RANDOM) % count]}
    [[ $cell == "$origin" || ${stars_char[$cell]+present} || ${stars_birth[$cell]+present} || ${stars_baseline_blocked[cell]+present} ]] && continue
    row=$((cell / COLUMNS + 1))
    # Same spatial weights as initial generation; the overall 50% multiplier
    # cancels when choosing where to put one replacement.
    (( (RANDOM * 32768 + RANDOM) % stars_density_max < ${stars_density[row]:-1000} )) || continue
    stars_char[$cell]=${chars:RANDOM%3:1} stars_palette[$cell]=$((RANDOM % 3))
    ez_stars_pick_saturation "$cell"
    ez_stars_pick_hue "$cell"
    unset 'stars_seen[$cell]' 'stars_settled[cell]' 'stars_color_pair[cell]'
    stars_replacement_birth[cell]=$elapsed
    unset 'stars_replace_queue[stars_replace_head]'
    stars_replace_head=$((stars_replace_head + 1))
    if (( stars_replace_head == stars_replace_tail )); then
      stars_replace_head=0 stars_replace_tail=0 stars_replace_queue=()
    fi
    break
  done
  return 0
}

function ez_stars_index_baseline() {
  local cell=$1 row col distance arrival bottom=${stars_sweep_bottom:-$stars_bottom}
  if [[ ${stars_band_member[cell]:-0} != 1 && ${stars_char[$cell]+present} && ! ${stars_birth[$cell]+present} && ! ${stars_replacement_birth[cell]+present} && ! ${stars_text_char[$cell]+present} && ! ${stars_occluded[$cell]+present} ]] && (( stars_work_ready )); then
    (( row = cell / COLUMNS + 1, col = cell % COLUMNS, 1 ))
    distance=$(((col * 1000 / (COLUMNS > 1 ? COLUMNS - 1 : 1) + (row - stars_top) * 1000 / (bottom > stars_top ? bottom - stars_top : 1)) / 2))
    arrival=${stars_sweep_arrival[distance]} stars_arrival_cell[cell]=$arrival
    arrival=$((arrival / 16))
    stars_star_band[arrival]+=" $cell" stars_band_member[cell]=1
  fi
  return 0
}

# Prepare the next hue in small idle-frame slices. Keep only two colors per
# cell; sweeping never pays the full HSV-conversion bill at its busiest point.
function ez_stars_prefetch() {
  local cycle=$1 cell palette saturation offset target value pair previous count=0
  local current_tag=$((cycle % 16384 + 1)) next_tag=$(((cycle + 1) % 16384 + 1))
  if (( stars_pair_epoch != cycle / 16384 )); then
    stars_color_pair=() stars_pair_epoch=$((cycle / 16384))
  fi
  local remaining_frames
  target=$((cycle + 1))
  if (( stars_prefetch_cycle != cycle )); then
    stars_prefetch_cells=("${!stars_char[@]}") stars_prefetch_cursor=0 stars_prefetch_cycle=$cycle
    # Finish in the first three quarters of the remaining idle window where
    # practical. Large fields need a larger slice, still capped per frame.
    remaining_frames=$(((stars_period - ${2:-0}) * 3 / 200))
    (( remaining_frames < 1 )) && remaining_frames=1
    stars_prefetch_budget=$(((${#stars_prefetch_cells[@]} + remaining_frames - 1) / remaining_frames))
    (( stars_prefetch_budget < 32 )) && stars_prefetch_budget=32
    (( stars_prefetch_budget > 128 )) && stars_prefetch_budget=128
  fi
  while (( stars_prefetch_cursor < ${#stars_prefetch_cells[@]} && count < stars_prefetch_budget )); do
    cell=${stars_prefetch_cells[stars_prefetch_cursor]}
    stars_prefetch_cursor=$((stars_prefetch_cursor + 1)) count=$((count + 1))
    [[ ${stars_char[$cell]+present} ]] || continue
    [[ ${stars_text_char[$cell]+present} || ${stars_occluded[$cell]+present} ]] && continue
    pair=${stars_color_pair[cell]:-0}
    (( pair >> 48 == next_tag )) && continue
    palette=${stars_palette[$cell]} saturation=${stars_saturation[$cell]:-${stars_sat[palette]}} offset=${stars_hue_offset[$cell]:-0}
    if (( pair >> 48 == current_tag )); then
      value=$(((pair >> 24) & 16777215))
    else
      ez_stars_palette_rgb "$palette" "$cycle" "$saturation" "$offset"
      value=$stars_rgb_value
    fi
    previous=$value
    ez_stars_palette_rgb "$palette" "$target" "$saturation" "$offset"
    value=$stars_rgb_value
    # Two RGB colors and a cycle tag fit in 63 bits. Clear all pairs on tag
    # epoch changes: random rotations do not repeat after 360 cycles.
    stars_color_pair[cell]=$(((next_tag << 48) | (value << 24) | previous))
  done
  return 0
}

function ez_stars_sweep() {
  local row=$1 col=$2 cycle=$3 phase=$4
  local rise=$stars_rise tail=$stars_tail distance arrival local_phase
  local bottom=${stars_sweep_bottom:-$stars_bottom}
  stars_white=0 stars_color_cycle=$cycle
  if (( cycle > 0 && phase < stars_duration )); then
    # Shared eased arrival keeps letters, markers, and stars in the same band.
    if [[ -n ${5:-} ]]; then arrival=$5;
    else
      distance=$(((col * 1000 / (COLUMNS > 1 ? COLUMNS - 1 : 1) + (row - stars_top) * 1000 / (bottom > stars_top ? bottom - stars_top : 1)) / 2))
      arrival=${stars_sweep_arrival[distance]}
    fi
    local_phase=$((phase - arrival))
    if (( local_phase < 0 )); then
      stars_color_cycle=$((cycle - 1))
    elif (( local_phase < rise )); then
      stars_color_cycle=$((cycle - 1))
      stars_white=${stars_flash[local_phase]}
    elif (( local_phase < rise + tail )); then
      stars_white=${stars_flash[local_phase]}
    fi
  fi
  return 0
}

function ez_stars_twinkle_weight() {
  local elapsed=$1 phase position product sine
  # Advance the entire sine-squared envelope: both its fall and rise occur sooner.
  # Bhaskara's sine approximation avoids a process or floating-point work per
  # frame. Weight stays between 20% and 100%, with smooth, periodic shoulders.
  phase=$(((elapsed - stars_duration / 2 + stars_twinkle_advance + stars_period) % stars_period))
  position=$((phase * 1000 / stars_period))
  product=$((position * (1000 - position)))
  sine=$((16000 * product / (5000000 - 4 * product)))
  stars_spawn_weight=$((200 + 800 * sine * sine / 1000000))
}

# Sample one unoccupied text-free cell, optionally weighted by excess density.
function ez_stars_try_spawn() {
  local elapsed=$1 horizon=$2 cell row index start count=${#stars_cells[@]}
  (( count )) || return 0
  start=$(((RANDOM * 32768 + RANDOM) % count))
  for ((index = 0; index < count; index++)); do
    if (( horizon )); then cell=${stars_cells[(RANDOM * 32768 + RANDOM) % count]};
    else cell=${stars_cells[(start + index) % count]}; fi
    [[ ${stars_text_char[$cell]+present} || ${stars_occluded[$cell]+present} || ${stars_birth[$cell]+present} ]] && continue
    if (( horizon )); then
      row=$((cell / COLUMNS + 1))
      (( (RANDOM * 32768 + RANDOM) % (stars_density_max - 1000) < ${stars_density[row]:-1000} - 1000 )) || continue
    fi
    ez_stars_spawn "$cell" "$elapsed"
    stars_spawned=1
    break
  done
  return 0
}

function ez_stars_tick() {
  stars_repair_active=0
  local elapsed=$1 cycle phase cell row col age white intensity color_cycle char token style
  local emit_limit=${2:--1}
  local sweeping=0 stable=0 stars_spawned=0 trusted_work=0 birth replacement seen
  local arrival local_phase expected distance bottom=${stars_sweep_bottom:-$stars_bottom}
  local rgb_key value fade palette saturation offset peak sweep_white active_flash pair tag next_tag
  local color_weight white_value flash_duration=$((stars_rise + stars_tail))
  local geometry="$COLUMNS:$stars_top:${stars_sweep_bottom:-$stars_bottom}"
  local -a updates=() work_stars work_text
  local lower upper bucket IFS=$' \t\n'
  for cell in "${!stars_clear_pending[@]}"; do updates[cell]=':0: '; done
  stars_clear_pending=()
  if [[ $geometry != "$stars_geometry_key" ]]; then
    stars_arrival_cell=() stars_settled=() stars_text_settled=() stars_geometry_key=$geometry
    stars_work_ready=0
  fi
  stars_output=''
  cycle=$((elapsed / stars_period)) phase=$((elapsed % stars_period))
  if (( stars_pair_epoch != cycle / 16384 )); then
    stars_color_pair=() stars_pair_epoch=$((cycle / 16384))
  fi
  (( cycle > 0 && phase < stars_duration )) && sweeping=1
  if (( ! sweeping && ! stars_was_sweeping && cycle == stars_render_cycle )); then stable=1; fi
  if (( cycle != stars_cache_cycle )); then
    stars_rgb_cache=() stars_cache_cycle=$cycle
  fi
  ez_stars_retire "$elapsed"
  ez_stars_replace "$elapsed"
  # Faster random opportunities keep the same smooth probability envelope.
  if (( elapsed >= stars_next )); then
    ez_stars_twinkle_weight "$elapsed"
    if (( RANDOM % 1000 < stars_spawn_weight )); then
      ez_stars_try_spawn "$elapsed" 0
    fi
    # One birth at most per frame; never catch up missed time with a burst.
    stars_next=$((elapsed + 1 + (RANDOM * 32768 + RANDOM) % stars_twinkle_delay))
  fi
  if (( ! stars_spawned && stars_horizon_delay && elapsed >= stars_horizon_next )); then
    ez_stars_twinkle_weight "$elapsed"
    if (( RANDOM % 1000 < stars_spawn_weight )); then
      ez_stars_try_spawn "$elapsed" 1
    fi
    stars_horizon_next=$((elapsed + 1 + (RANDOM * 32768 + RANDOM) % stars_horizon_delay))
  fi
  if (( stars_work_ready && ! stars_work_dirty && elapsed >= stars_last_elapsed )) &&
     (( cycle == stars_render_cycle || (cycle == stars_render_cycle + 1 && ! stars_was_sweeping && sweeping) )); then
    trusted_work=1 work_stars=() work_text=("${!stars_text_dirty[@]}")
    # Negative IDs mark transient/dirty cells that need general state checks.
    # Bucket entries are live, visible, settled baseline stars by construction.
    for cell in "${!stars_birth[@]}" "${!stars_replacement_birth[@]}" "${!stars_star_dirty[@]}"; do
      work_stars+=("$((-cell - 1))")
    done
    if (( sweeping || stars_was_sweeping )); then
      lower=0 upper=$phase
      (( cycle == stars_render_cycle && stars_was_sweeping )) && lower=$((stars_last_phase - stars_rise - stars_tail + 1))
      (( lower < 0 )) && lower=0
      (( ! sweeping || upper > stars_travel )) && upper=$stars_travel
      (( lower /= 16, upper /= 16, 1 ))
      for ((bucket = lower; bucket <= upper; bucket++)); do
        # Intentional splitting: bucket contents are space-separated cell IDs.
        work_stars+=(${stars_star_band[bucket]-})
        work_text+=(${stars_text_band[bucket]-})
      done
    fi
  else
    work_stars=("${!stars_char[@]}") work_text=("${!stars_text_char[@]}")
  fi
  for cell in "${work_stars[@]}"; do
    if (( trusted_work && cell >= 0 )); then
      char=${stars_char[$cell]} birth='' replacement=''
    else
      (( cell < 0 )) && cell=$((-cell - 1))
      char=${stars_char[$cell]-}
      [[ -n $char ]] || continue
      [[ ${stars_text_char[$cell]+present} || ${stars_occluded[$cell]+present} ]] && continue
      birth=${stars_birth[$cell]-} replacement=${stars_replacement_birth[cell]-}
    fi
    seen=${stars_seen[$cell]-}
    # Between effects, unchanged stars cost no color conversion or terminal I/O.
    if (( stable )) && [[ -n $seen && -z $birth && -z $replacement ]]; then continue; fi
    arrival=${stars_arrival_cell[cell]-}
    if [[ -z $arrival ]]; then
      (( row = cell / COLUMNS + 1, col = cell % COLUMNS, 1 ))
      distance=$(((col * 1000 / (COLUMNS > 1 ? COLUMNS - 1 : 1) + (row - stars_top) * 1000 / (bottom > stars_top ? bottom - stars_top : 1)) / 2))
      arrival=${stars_sweep_arrival[distance]} stars_arrival_cell[cell]=$arrival
    fi
    (( local_phase = phase - arrival,
       expected = cycle - (sweeping && local_phase < 0),
       active_flash = sweeping && local_phase >= 0 && local_phase < flash_duration, 1 ))
    if [[ -n $seen && -z $birth && -z $replacement ]] &&
       (( ! active_flash )); then
      [[ ${stars_settled[cell]:--1} == "$expected" ]] && continue
    fi
    white=0 intensity=1000 color_cycle=$cycle style=0 sweep_white=0
    if [[ -n $birth ]]; then
      age=$((elapsed - birth))
      (( age < 0 )) && age=0
      intensity=${stars_twinkle_curve[age]} white=$intensity char=${stars_twinkle_glyph[age]}
    elif [[ -n $replacement ]]; then
      age=$((elapsed - replacement))
      (( age < 0 )) && age=0
      # Fade only intensity: preserve the chosen glyph, hue and saturation.
      # A crossing shimmer can still apply its usual color/bold treatment.
      intensity=${stars_replacement_curve[age]}
    fi
    # Batch integer work to avoid dispatching shell commands for each scalar.
    # The shimmer changes saturation, while each star's own fade owns intensity.
    (( stars_white = active_flash ? stars_flash[local_phase] : 0,
       color_cycle = cycle - (sweeping && local_phase < stars_rise),
       style = stars_white >= 900, sweep_white = stars_white,
       white = 1000 - (1000 - white) * (1000 - stars_white) / 1000,
       stars_settled[cell] = active_flash ? -1 : expected, 1 ))
    pair=${stars_color_pair[cell]:-0}
    (( tag = color_cycle % 16384 + 1, next_tag = (color_cycle + 1) % 16384 + 1, 1 ))
    if (( pair >> 48 == tag )); then
      value=$(((pair >> 24) & 16777215))
    elif (( pair >> 48 == next_tag )); then
      value=$((pair & 16777215))
    else
      palette=${stars_palette[$cell]} saturation=${stars_saturation[$cell]:-${stars_sat[palette]}} offset=${stars_hue_offset[$cell]:-0}
      rgb_key="$palette:$color_cycle:$saturation:$offset" value=${stars_rgb_cache[$rgb_key]-}
      if [[ -z $value ]]; then
        ez_stars_palette_rgb "$palette" "$color_cycle" "$saturation" "$offset"
        value=$stars_rgb_value
      fi
    fi
    (( row = cell / COLUMNS + 1, fade = stars_fade[row], 1 ))
    # Keep ordinary/twinkle colors intact. Only the sweep's white endpoint uses
    # the uniform upper 30% and exclusive fade over the remaining 70%.
    peak=${stars_peak[row]:-$((fade * 10))}
    (( peak = fade * 10 - (fade * 10 - peak) * sweep_white / 1000,
       color_weight = (1000 - white) * fade * 10, white_value = 255 * white * peak,
       stars_r = ((value >> 16) * color_weight + white_value) * intensity / 1000000000,
       stars_g = (((value >> 8) & 255) * color_weight + white_value) * intensity / 1000000000,
       stars_b = ((value & 255) * color_weight + white_value) * intensity / 1000000000, 1 ))
    token="$stars_r;$stars_g;$stars_b:$style:$char"
    if [[ $seen != "$token" ]]; then
      updates[cell]=$token stars_seen[$cell]=$token stars_cell_render[$cell]=$token
    fi
  done
  for cell in "${work_text[@]}"; do
    seen=${stars_text_seen[$cell]-}
    if (( stable )) && [[ -n $seen ]]; then continue; fi
    arrival=${stars_arrival_cell[cell]-}
    if [[ -z $arrival ]]; then
      (( row = cell / COLUMNS + 1, col = cell % COLUMNS, 1 ))
      distance=$(((col * 1000 / (COLUMNS > 1 ? COLUMNS - 1 : 1) + (row - stars_top) * 1000 / (bottom > stars_top ? bottom - stars_top : 1)) / 2))
      arrival=${stars_sweep_arrival[distance]} stars_arrival_cell[cell]=$arrival
    fi
    (( local_phase = phase - arrival,
       expected = cycle - (sweeping && local_phase < 0),
       active_flash = sweeping && local_phase >= 0 && local_phase < flash_duration, 1 ))
    if [[ -n $seen ]] &&
       (( ! active_flash )); then
      [[ ${stars_text_settled[cell]:--1} == "$expected" ]] && continue
    fi
    (( stars_white = active_flash ? stars_flash[local_phase] : 0,
       color_cycle = cycle - (sweeping && local_phase < stars_rise),
       stars_text_settled[cell] = active_flash ? -1 : expected, 1 ))
    style=${stars_text_style[$cell]}
    if [[ ${stars_text_flash[$cell]:-0} == 1 ]] && (( stars_white >= 900 )); then style=1; fi
    palette=${stars_text_palette[$cell]} rgb_key="$palette:$color_cycle:${stars_sat[palette]}:0"
    value=${stars_rgb_cache[$rgb_key]-}
    if [[ -z $value ]]; then
      ez_stars_palette_rgb "$palette" "$color_cycle"
      value=$stars_rgb_value
    fi
    fade=${stars_text_fade[$cell]}
    (( color_weight = 1000 - stars_white, white_value = 255 * stars_white,
       stars_r = ((value >> 16) * color_weight + white_value) * fade / 100000,
       stars_g = (((value >> 8) & 255) * color_weight + white_value) * fade / 100000,
       stars_b = ((value & 255) * color_weight + white_value) * fade / 100000, 1 ))
    token="$stars_r;$stars_g;$stars_b:$style:${stars_text_char[$cell]}"
    if [[ $seen != "$token" ]]; then
      updates[cell]=$token stars_text_seen[$cell]=$token stars_cell_render[$cell]=$token
    fi
  done
  stars_render_cycle=$cycle stars_was_sweeping=$sweeping
  stars_work_dirty=0 stars_last_elapsed=$elapsed stars_last_phase=$phase
  stars_text_dirty=()
  stars_star_dirty=()
  # A foreground repair will paint these cells from the final cache. Avoid
  # encoding a second, unused copy of their cursor/style/color output.
  if (( emit_limit == 0 )); then
    updates=()
  elif (( emit_limit > 0 )); then
    for cell in "${!updates[@]}"; do
      (( cell < emit_limit )) || unset 'updates[cell]'
    done
  fi
  ez_stars_emit
  (( stars_work_ready && ! sweeping )) && ez_stars_prefetch "$cycle" "$phase"
  return 0
}

# Indexed arrays enumerate in cell order: no sort process, fewer cursor moves,
# and one color/style command for each run instead of for every character.
function ez_stars_emit() {
  local cell row col token rgb style char sgr active_rgb='' active_style=-1 row_end=0 next_cell=0
  for cell in "${!updates[@]}"; do
    if (( cell >= row_end )); then
      (( row = cell / COLUMNS + 1, col = cell % COLUMNS + 1, row_end = row * COLUMNS, 1 ))
      stars_output+=$'\033['"$row;${col}H"
    elif (( cell != next_cell )); then
      if (( cell == next_cell + 1 )); then stars_output+=$'\033[C';
      else
        stars_output+=$'\033['"$((cell - next_cell))C"
      fi
    fi
    next_cell=$((cell + 1)) sgr=''
    token=${updates[cell]} rgb=${token%%:*} token=${token#*:}
    style=${token%%:*} char=${token#*:}
    if (( style != active_style )); then
      if (( active_style < 0 )); then sgr="0;$style";
      else
        case $active_style in
          1) sgr=22 ;;
          9) sgr=29 ;;
        esac
        (( style )) && sgr+="${sgr:+;}$style"
      fi
      active_style=$style
    fi
    if [[ -n $rgb && $rgb != "$active_rgb" ]]; then
      sgr+="${sgr:+;}38;2;$rgb" active_rgb=$rgb
    fi
    if [[ -n $sgr ]]; then stars_output+=$'\033['"${sgr}m$char";
    else stars_output+=$char; fi
  done
  [[ -z $stars_output ]] || stars_output+=$'\033[0m'
  return 0
}

# Cache compact RGB:style:glyph tokens, not preformatted escape sequences. This
# avoids constructing and then parsing ANSI for every animated cell, and lets
# repairs combine style and color into one command without splitting UTF-8.
# Full/partial foreground redraws use the same final cells as animation updates.
# No original pink title or empty star field is painted underneath an overlay.
function ez_stars_render_span() {
  if (( ${stars_repair_active:-0} )); then
    ez_stars_render_sparse_span "$@"
    return
  fi
  local row=$1 left=$2 width=$3 col cell result='' rendered prefix active='' char rgb style active_style=0
  for ((col = left; col < left + width; col++)); do
    cell=$(((row - 1) * COLUMNS + col))
    rendered=${stars_cell_render[$cell]-}
    if [[ -n $rendered ]]; then
      rgb=${rendered%%:*} rendered=${rendered#*:}
      style=${rendered%%:*} char=${rendered#*:}
      prefix=$'\033[0;'"$style;38;2;${rgb}m"
      if [[ $prefix != "$active" ]]; then result+=$prefix; active=$prefix; active_style=$style; fi
      result+=$char
    else
      # Preserve color across spaces to batch whole title/hint runs, but never
      # extend a disabled marker's strikethrough into adjacent empty cells.
      if (( active_style == 9 )); then result+=$'\033[0m'; active='' active_style=0; fi
      result+=' '
    fi
  done
  printf '%s\033[0m' "$result"
}

# A foreground repair sees a frozen frame inside the chooser's command
# substitution. Sort its occupied cells once, then skip empty runs in C-backed
# string slices instead of visiting every empty terminal cell in Bash.
function ez_stars_prepare_repair() {
  local cell first=${1:-0}
  local -a sorted=()
  for cell in "${!stars_cell_render[@]}"; do
    (( cell >= first )) && sorted[cell]=1
  done
  stars_repair_cells=("${!sorted[@]}") stars_repair_index=0 stars_repair_last=-1
  printf -v stars_repair_spaces '%*s' "$COLUMNS" ''
  stars_repair_active=1
}

function ez_stars_render_sparse_span() {
  local row=$1 left=$2 width=$3 cursor right cell gap rendered prefix char active='' result='' rgb style active_style=0
  local low high middle count=${#stars_repair_cells[@]}
  if (( width > ${#stars_repair_spaces} )); then printf -v stars_repair_spaces '%*s' "$width" ''; fi
  (( cursor = (row - 1) * COLUMNS + left, right = cursor + width, 1 ))
  if (( cursor < stars_repair_last )); then
    # Support overlapping/out-of-order spans too; normal repairs move forward.
    low=0 high=$count
    while (( low < high )); do
      middle=$(((low + high) / 2))
      if (( stars_repair_cells[middle] < cursor )); then low=$((middle + 1));
      else high=$middle; fi
    done
    stars_repair_index=$low
  fi
  stars_repair_last=$right
  while (( stars_repair_index < count )); do
    cell=${stars_repair_cells[stars_repair_index]}
    (( cell >= right )) && break
    stars_repair_index=$((stars_repair_index + 1))
    (( cell < cursor )) && continue
    gap=$((cell - cursor))
    if (( gap )); then
      if (( active_style == 9 )); then result+=$'\033[0m'; active='' active_style=0; fi
      result+=${stars_repair_spaces:0:gap}
    fi
    rendered=${stars_cell_render[$cell]} rgb=${rendered%%:*} rendered=${rendered#*:}
    style=${rendered%%:*} char=${rendered#*:}
    prefix=$'\033[0;'"$style;38;2;${rgb}m"
    if [[ $prefix != "$active" ]]; then result+=$prefix; active=$prefix; active_style=$style; fi
    result+=$char cursor=$((cell + 1))
  done
  if (( cursor < right )); then
    (( active_style != 9 )) || result+=$'\033[0m'
    result+=${stars_repair_spaces:0:right-cursor}
  fi
  printf '%s\033[0m' "$result"
}

function ez_stars_bar_color() {
  local elapsed=$1 cycle phase from_red from_green from_blue fraction
  cycle=$((elapsed / stars_period)) phase=$((elapsed % stars_period))
  if [[ ${stars_bar_cycle:--1} != "$cycle" ]]; then
    if (( cycle > 0 )); then
      ez_stars_color 4 "$((cycle - 1))" 0 55 1000
      stars_bar_from=$(((stars_r << 16) | (stars_g << 8) | stars_b))
    fi
    ez_stars_color 4 "$cycle" 0 55 1000
    stars_bar_to=$(((stars_r << 16) | (stars_g << 8) | stars_b)) stars_bar_cycle=$cycle
    printf -v stars_bar_target_bg '\033[48;2;%d;%d;%dm' "$stars_r" "$stars_g" "$stars_b"
  fi
  if (( cycle > 0 && phase < stars_duration )); then
    ez_stars_sweep_ease "$((phase * 1000 / stars_duration))"
    fraction=$stars_eased
    (( from_red = stars_bar_from >> 16, from_green = (stars_bar_from >> 8) & 255, from_blue = stars_bar_from & 255,
       stars_r = from_red + ((stars_bar_to >> 16) - from_red) * fraction / 1000,
       stars_g = from_green + (((stars_bar_to >> 8) & 255) - from_green) * fraction / 1000,
       stars_b = from_blue + ((stars_bar_to & 255) - from_blue) * fraction / 1000, 1 ))
    printf -v stars_bar_bg '\033[48;2;%d;%d;%dm' "$stars_r" "$stars_g" "$stars_b"
  else
    (( stars_r = stars_bar_to >> 16, stars_g = (stars_bar_to >> 8) & 255, stars_b = stars_bar_to & 255, 1 ))
    stars_bar_bg=$stars_bar_target_bg
  fi
}
