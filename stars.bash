#!/usr/bin/env bash
# Stateful star animation. All stars_* variables belong to the chooser subshell.
# Coordinates are terminal cells; text/gutters never enter stars_cells.

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
  local color code red green blue high low delta hue palette=0 hue_total=0
  local -a levels=(0 95 135 175 215 255)
  stars_period=${EZ_MENU_SWEEP_INTERVAL_MS:-4000}
  stars_duration=${EZ_MENU_SWEEP_DURATION_MS:-1000}
  stars_step=${EZ_MENU_SWEEP_HUE_STEP:-70}
  stars_sat_max=${EZ_MENU_STAR_SATURATION_MAX:-800}
  stars_accent_offset=${EZ_MENU_SWEEP_ACCENT_OFFSET:-180}
  stars_hue_spread=${EZ_MENU_STAR_HUE_SPREAD:-60}
  [[ $stars_hue_spread =~ ^[0-9]{1,3}$ ]] || stars_hue_spread=60
  stars_hue_spread=$((10#$stars_hue_spread))
  (( stars_hue_spread > 360 )) && stars_hue_spread=360
  [[ $stars_period =~ ^[1-9][0-9]{0,5}$ ]] || stars_period=4000
  [[ $stars_duration =~ ^[1-9][0-9]{0,4}$ ]] || stars_duration=1000
  [[ $stars_step =~ ^[0-9]{1,3}$ ]] || stars_step=70
  stars_step=$((10#$stars_step))
  [[ $stars_sat_max =~ ^[0-9]{1,4}$ ]] || stars_sat_max=800
  stars_sat_max=$((10#$stars_sat_max))
  (( stars_sat_max > 1000 )) && stars_sat_max=1000
  [[ $stars_accent_offset =~ ^[0-9]{1,3}$ ]] || stars_accent_offset=180
  stars_accent_offset=$((10#$stars_accent_offset))
  (( stars_duration < 300 )) && stars_duration=300
  (( stars_period < stars_duration + 1800 )) && stars_period=$((stars_duration + 1800))
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
  stars_origin=$stars_now stars_next=$((1 + RANDOM % 500)) stars_cache_cycle=-1
  stars_render_cycle=-1 stars_was_sweeping=0
}

function ez_stars_layout() {
  local banner_count=$1 title_height=$2 title_width=$3 margin=$4
  local option_start=$((banner_count + 3)) row col cell mask_left mask_right brightness
  local title_left=$(( (COLUMNS - title_width) / 2 )) chars='*.+ '
  stars_cells=() stars_char=() stars_palette=() stars_saturation=() stars_hue_offset=()
  stars_birth=() stars_seen=() stars_fade=() stars_cell_render=() stars_text_seen=()
  stars_top=3 stars_bottom=$((option_start + visible - 1))
  (( stars_bottom >= LINES )) && stars_bottom=$((LINES - 1))
  stars_sweep_bottom=$stars_bottom
  for ((row = stars_top; row <= stars_bottom; row++)); do
    mask_left=$COLUMNS mask_right=$COLUMNS brightness=100
    if (( row >= 3 + margin && row < 3 + margin + title_height )); then
      mask_left=$((title_left - 2)) mask_right=$((title_left + title_width + 2))
    elif (( row >= option_start )); then
      mask_left=$((option_left - 3)) mask_right=$((COLUMNS - option_right + 3))
      brightness=15
      (( visible > 1 )) && brightness=$((65 - 60 * (row - option_start) / (visible - 1)))
    elif (( row > banner_count + 1 )); then
      brightness=80
      # Keep the approach to the option block clear as well.
      mask_left=$((option_left - 3)) mask_right=$((COLUMNS - option_right + 3))
    fi
    stars_fade[row]=$brightness
    for ((col = 0; col < COLUMNS; col++)); do
      (( col >= mask_left && col < mask_right )) && continue
      cell=$(( (row - 1) * COLUMNS + col ))
      stars_cells+=("$cell")
      if (( RANDOM % 8 == 0 )); then
        stars_char[$cell]=${chars:RANDOM%3:1}
        stars_palette[$cell]=$((RANDOM % 3))
        ez_stars_pick_saturation "$cell"
        ez_stars_pick_hue "$cell"
      fi
    done
  done
}

function ez_stars_pick_hue() {
  local cell=$1 sample index
  # Twelve uniforms approximate a normal distribution, sigma ~1000. Reject
  # beyond 3 sigma rather than piling clamped samples onto the endpoints.
  while :; do
    sample=-5994
    for ((index = 0; index < 12; index++)); do sample=$((sample + RANDOM % 1000)); done
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
  local banner_count=$1 title_width=$2 margin=$3 compact=$4 first=$5 selected=$6 number_width=$7
  local row col cell line index text style fade hint_width=0 left=$(( (COLUMNS - title_width) / 2 ))
  local -a letters=("${title_rows[@]}")
  local -a old_cells=("${!stars_text_char[@]}")
  stars_text_char=() stars_text_style=() stars_text_fade=() stars_text_palette=()
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
      stars_text_char[$cell]=${text:col:1} stars_text_style[$cell]=1 stars_text_fade[$cell]=100
      stars_text_palette[$cell]=3
    done
  done
  for ((index = first; index < first + visible; index++)); do
    row=$((banner_count + 3 + index - first))
    (( row >= LINES )) && break
    style=0 fade=100
    if [[ ${menu_enabled[index]:-1} == 0 ]]; then style=9 fade=60;
    elif (( index == selected )); then style=1; fi
    printf -v text '%*d' "$number_width" "$((index + 1))"
    if (( index == selected )); then text=">$text"; else text=" $text"; fi
    for ((col = 0; col < ${#text}; col++)); do
      [[ ${text:col:1} == ' ' ]] && continue
      (( option_left + col >= COLUMNS )) && break
      cell=$(( (row - 1) * COLUMNS + option_left + col ))
      stars_text_char[$cell]=${text:col:1} stars_text_style[$cell]=$style stars_text_fade[$cell]=$fade
      stars_text_palette[$cell]=3
    done
  done
  for text in "${hint_rows[@]}"; do (( ${#text} > hint_width )) && hint_width=${#text}; done
  left=$(( (COLUMNS - hint_width) / 2 ))
  (( left < 0 )) && left=0
  stars_sweep_bottom=$stars_bottom
  for ((line = 0; line < ${#hint_rows[@]}; line++)); do
    row=$((banner_count + visible + 4 + line))
    (( row >= LINES )) && break
    stars_sweep_bottom=$row
    text=${hint_rows[line]}
    for ((col = 0; col < ${#text} && left + col < COLUMNS; col++)); do
      [[ ${text:col:1} == ' ' ]] && continue
      cell=$(( (row - 1) * COLUMNS + left + col ))
      stars_text_char[$cell]=${text:col:1} stars_text_style[$cell]=0 stars_text_fade[$cell]=55
      stars_text_palette[$cell]=4
    done
  done
  for cell in "${old_cells[@]}"; do
    if [[ ! ${stars_text_char[$cell]+present} ]]; then
      unset 'stars_text_seen[$cell]' 'stars_cell_render[$cell]'
    fi
  done
  for cell in "${!stars_text_char[@]}"; do
    if [[ ${stars_text_seen[$cell]#*:} != "${stars_text_style[$cell]}:${stars_text_char[$cell]}" ]]; then
      unset 'stars_text_seen[$cell]'
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

function ez_stars_color() {
  local palette=$1 cycle=$2 white=$3 fade=$4 intensity=$5
  local saturation=${6:-${stars_sat[palette]}}
  local offset=${7:-0}
  local key="$palette:$cycle:$saturation:$offset" hue chroma secondary minimum value
  if [[ ! ${stars_rgb_cache[$key]+present} ]]; then
    hue=$(( (stars_hue[palette] + cycle * stars_step + offset + 360) % 360 ))
    value=${stars_value[palette]}
    chroma=$((value * saturation / 1000))
    secondary=$((hue % 120 - 60))
    (( secondary < 0 )) && secondary=$((-secondary))
    secondary=$((chroma * (60 - secondary) / 60)) minimum=$((value - chroma))
    case $((hue / 60)) in
      0) stars_r=$chroma stars_g=$secondary stars_b=0 ;;
      1) stars_r=$secondary stars_g=$chroma stars_b=0 ;;
      2) stars_r=0 stars_g=$chroma stars_b=$secondary ;;
      3) stars_r=0 stars_g=$secondary stars_b=$chroma ;;
      4) stars_r=$secondary stars_g=0 stars_b=$chroma ;;
      5) stars_r=$chroma stars_g=0 stars_b=$secondary ;;
    esac
    stars_rgb_cache[$key]="$((stars_r + minimum)) $((stars_g + minimum)) $((stars_b + minimum))"
  fi
  read -r stars_r stars_g stars_b <<< "${stars_rgb_cache[$key]}"
  stars_r=$(( (stars_r * (1000 - white) + 255 * white) * fade * intensity / 100000000 ))
  stars_g=$(( (stars_g * (1000 - white) + 255 * white) * fade * intensity / 100000000 ))
  stars_b=$(( (stars_b * (1000 - white) + 255 * white) * fade * intensity / 100000000 ))
}

function ez_stars_spawn() {
  local cell=$1 elapsed=$2
  # Replace the base star permanently; it must not return after this fades out.
  stars_birth[$cell]=$elapsed
  stars_char[$cell]='.'
  stars_palette[$cell]=$((RANDOM % 3))
  ez_stars_pick_saturation "$cell"
  ez_stars_pick_hue "$cell"
}

function ez_stars_sweep() {
  local row=$1 col=$2 cycle=$3 phase=$4
  local travel=$((stars_duration * 7 / 10)) rise=$((stars_duration * 6 / 100))
  local tail=$((stars_duration - travel - rise)) arrival local_phase
  local bottom=${stars_sweep_bottom:-$stars_bottom}
  stars_white=0 stars_color_cycle=$cycle
  if (( cycle > 0 && phase < stars_duration )); then
    # Shared spatial phase keeps letters, digits, and stars in the same band.
    arrival=$((travel * (col * 1000 / (COLUMNS > 1 ? COLUMNS - 1 : 1) + (row - stars_top) * 1000 / (bottom > stars_top ? bottom - stars_top : 1)) / 2000))
    local_phase=$((phase - arrival))
    if (( local_phase < 0 )); then
      stars_color_cycle=$((cycle - 1))
    elif (( local_phase < rise )); then
      stars_color_cycle=$((cycle - 1))
      ez_stars_ease "$((local_phase * 1000 / rise))"
      stars_white=$stars_eased
    elif (( local_phase < rise + tail )); then
      ez_stars_ease "$((1000 - (local_phase - rise) * 1000 / tail))"
      stars_white=$stars_eased
    fi
  fi
  return 0
}

function ez_stars_tick() {
  local elapsed=$1 cycle phase cell row col age white intensity color_cycle char token piece
  local index start count=${#stars_cells[@]}
  local sweeping=0 stable=0
  stars_output=''
  cycle=$((elapsed / stars_period)) phase=$((elapsed % stars_period))
  (( cycle > 0 && phase < stars_duration )) && sweeping=1
  if (( ! sweeping && ! stars_was_sweeping && cycle == stars_render_cycle )); then stable=1; fi
  if (( cycle != stars_cache_cycle )); then
    stars_rgb_cache=() stars_cache_cycle=$cycle
  fi
  # Finish every twinkle before the sweep starts. Never spawn during its passage.
  if (( elapsed >= stars_next )); then
    if (( count && (cycle == 0 || phase >= stars_duration) && phase + 900 < stars_period )); then
      start=$(((RANDOM * 32768 + RANDOM) % count))
      for ((index = 0; index < count; index++)); do
        cell=${stars_cells[(start + index) % count]}
        if [[ ! ${stars_birth[$cell]+present} ]]; then
          ez_stars_spawn "$cell" "$elapsed"
          break
        fi
      done
    fi
    # One birth at most per frame; never catch up missed time with a burst.
    stars_next=$((elapsed + 1 + RANDOM % 500))
  fi
  for cell in "${!stars_char[@]}"; do
    # Between effects, unchanged stars cost no color conversion or terminal I/O.
    if (( stable )) && [[ ${stars_seen[$cell]+present} && ! ${stars_birth[$cell]+present} ]]; then continue; fi
    row=$((cell / COLUMNS + 1)) col=$((cell % COLUMNS))
    char=${stars_char[$cell]} white=0 intensity=1000 color_cycle=$cycle
    if [[ ${stars_birth[$cell]+present} ]]; then
      age=$((elapsed - stars_birth[$cell]))
      if (( age >= 900 )); then
        printf -v piece '\033[%d;%dH ' "$row" "$((col + 1))"
        stars_output+=$piece
        unset 'stars_birth[$cell]' 'stars_char[$cell]' 'stars_palette[$cell]' 'stars_saturation[$cell]' 'stars_seen[$cell]' 'stars_hue_offset[$cell]' 'stars_cell_render[$cell]'
        continue
      fi
      if (( age < 120 )); then
        ez_stars_ease "$((age * 1000 / 120))"
      else
        ez_stars_ease "$((1000 - (age - 120) * 1000 / 780))"
      fi
      intensity=$stars_eased white=$stars_eased
      if (( intensity < 250 )); then char='.';
      elif (( intensity < 650 )); then char='+';
      else char='*'; fi
    elif (( sweeping )); then
      ez_stars_sweep "$row" "$col" "$cycle" "$phase"
      white=$stars_white color_cycle=$stars_color_cycle
    fi
    ez_stars_color "${stars_palette[$cell]}" "$color_cycle" "$white" "${stars_fade[row]}" "$intensity" "${stars_saturation[$cell]-}" "${stars_hue_offset[$cell]:-0}"
    token="$stars_r;$stars_g;$stars_b:$char"
    if [[ ${stars_seen[$cell]-} != "$token" ]]; then
      printf -v piece '\033[%d;%dH\033[38;2;%d;%d;%dm%s' "$row" "$((col + 1))" "$stars_r" "$stars_g" "$stars_b" "$char"
      stars_output+=$piece stars_seen[$cell]=$token
      printf -v 'stars_cell_render[$cell]' '\033[38;2;%d;%d;%dm%s\033[0m' "$stars_r" "$stars_g" "$stars_b" "$char"
    fi
  done
  for cell in "${!stars_text_char[@]}"; do
    if (( stable )) && [[ ${stars_text_seen[$cell]+present} ]]; then continue; fi
    row=$((cell / COLUMNS + 1)) col=$((cell % COLUMNS))
    ez_stars_sweep "$row" "$col" "$cycle" "$phase"
    ez_stars_color "${stars_text_palette[$cell]}" "$stars_color_cycle" "$stars_white" "${stars_text_fade[$cell]}" 1000
    token="$stars_r;$stars_g;$stars_b:${stars_text_style[$cell]}:${stars_text_char[$cell]}"
    if [[ ${stars_text_seen[$cell]-} != "$token" ]]; then
      printf -v piece '\033[%d;%dH\033[0;%sm\033[38;2;%d;%d;%dm%s' "$row" "$((col + 1))" "${stars_text_style[$cell]}" "$stars_r" "$stars_g" "$stars_b" "${stars_text_char[$cell]}"
      stars_output+=$piece stars_text_seen[$cell]=$token
      printf -v 'stars_cell_render[$cell]' '\033[0;%sm\033[38;2;%d;%d;%dm%s\033[0m' "${stars_text_style[$cell]}" "$stars_r" "$stars_g" "$stars_b" "${stars_text_char[$cell]}"
    fi
  done
  stars_render_cycle=$cycle stars_was_sweeping=$sweeping
  [[ -z $stars_output ]] || stars_output+=$'\033[0m'
  return 0
}

# Full/partial foreground redraws use the same final cells as animation updates.
# No original pink title or empty star field is painted underneath an overlay.
function ez_stars_render_span() {
  local row=$1 left=$2 width=$3 col cell result='' rendered prefix active='' char
  for ((col = left; col < left + width; col++)); do
    cell=$(((row - 1) * COLUMNS + col))
    rendered=${stars_cell_render[$cell]-}
    if [[ -n $rendered ]]; then
      char=${rendered: -5:1}
      prefix=${rendered:0:${#rendered}-5}
      if [[ $prefix != "$active" ]]; then result+=$'\033[0m'"$prefix"; active=$prefix; fi
      result+=$char
    else
      # Preserve color across spaces to batch whole title/hint runs, but never
      # extend a disabled digit's strikethrough into adjacent empty cells.
      if [[ $active == *$'\033[0;9m'* ]]; then result+=$'\033[0m'; active=''; fi
      result+=' '
    fi
  done
  printf '%s\033[0m' "$result"
}

function ez_stars_bar_color() {
  local elapsed=$1 cycle phase from_red from_green from_blue fraction
  cycle=$((elapsed / stars_period)) phase=$((elapsed % stars_period))
  if (( cycle > 0 && phase < stars_duration )); then
    ez_stars_color 4 "$((cycle - 1))" 0 55 1000
    from_red=$stars_r from_green=$stars_g from_blue=$stars_b
    ez_stars_color 4 "$cycle" 0 55 1000
    fraction=$((phase * 1000 / stars_duration))
    stars_r=$((from_red + (stars_r - from_red) * fraction / 1000))
    stars_g=$((from_green + (stars_g - from_green) * fraction / 1000))
    stars_b=$((from_blue + (stars_b - from_blue) * fraction / 1000))
  else
    ez_stars_color 4 "$cycle" 0 55 1000
  fi
  printf -v stars_bar_bg '\033[48;2;%d;%d;%dm' "$stars_r" "$stars_g" "$stars_b"
}
