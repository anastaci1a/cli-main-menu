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
  local color code red green blue high low delta hue palette=0
  local -a levels=(0 95 135 175 215 255)
  stars_period=${EZ_MENU_SWEEP_INTERVAL_MS:-4000}
  stars_duration=${EZ_MENU_SWEEP_DURATION_MS:-1000}
  stars_step=${EZ_MENU_SWEEP_HUE_STEP:-70}
  [[ $stars_period =~ ^[1-9][0-9]{0,5}$ ]] || stars_period=4000
  [[ $stars_duration =~ ^[1-9][0-9]{0,4}$ ]] || stars_duration=1000
  [[ $stars_step =~ ^[0-9]{1,3}$ ]] || stars_step=70
  stars_step=$((10#$stars_step))
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
  ez_stars_now
  stars_origin=$stars_now stars_next=$((80 + RANDOM % 1421)) stars_cache_cycle=-1
  stars_render_cycle=-1 stars_was_sweeping=0
}

function ez_stars_layout() {
  local banner_count=$1 title_height=$2 title_width=$3 margin=$4
  local option_start=$((banner_count + 3)) row col cell mask_left mask_right brightness
  local title_left=$(( (COLUMNS - title_width) / 2 )) chars='*.+ '
  stars_cells=() stars_char=() stars_palette=() stars_birth=() stars_seen=() stars_fade=()
  stars_top=3 stars_bottom=$((option_start + visible - 1))
  (( stars_bottom >= LINES )) && stars_bottom=$((LINES - 1))
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
      fi
    done
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
  local key="$palette:$cycle" hue chroma secondary minimum value saturation
  if [[ ! ${stars_rgb_cache[$key]+present} ]]; then
    hue=$(( (stars_hue[palette] + cycle * stars_step) % 360 ))
    value=${stars_value[palette]} saturation=${stars_sat[palette]}
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
}

function ez_stars_tick() {
  local elapsed=$1 cycle phase cell row col age white intensity color_cycle char token piece
  local travel arrival local_phase rise tail batch index count=${#stars_cells[@]}
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
      batch=$((1 + RANDOM % 3))
      for ((index = 0; index < batch; index++)); do
        cell=${stars_cells[(RANDOM * 32768 + RANDOM) % count]}
        [[ ${stars_birth[$cell]+present} ]] || ez_stars_spawn "$cell" "$elapsed"
      done
    fi
    stars_next=$((elapsed + 80 + RANDOM % 1421))
  fi
  travel=$((stars_duration * 7 / 10))
  rise=$((stars_duration * 6 / 100)) tail=$((stars_duration - travel - rise))
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
        unset 'stars_birth[$cell]' 'stars_char[$cell]' 'stars_palette[$cell]' 'stars_seen[$cell]'
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
    elif (( cycle > 0 && phase < stars_duration )); then
      # x+y advances a diagonal band down/right across the full field.
      arrival=$((travel * (col * 1000 / (COLUMNS > 1 ? COLUMNS - 1 : 1) + (row - stars_top) * 1000 / (stars_bottom > stars_top ? stars_bottom - stars_top : 1)) / 2000))
      local_phase=$((phase - arrival))
      if (( local_phase < 0 )); then
        color_cycle=$((cycle - 1))
      elif (( local_phase < rise )); then
        color_cycle=$((cycle - 1))
        ez_stars_ease "$((local_phase * 1000 / rise))"
        white=$stars_eased
      elif (( local_phase < rise + tail )); then
        ez_stars_ease "$((1000 - (local_phase - rise) * 1000 / tail))"
        white=$stars_eased
      fi
    fi
    ez_stars_color "${stars_palette[$cell]}" "$color_cycle" "$white" "${stars_fade[row]}" "$intensity"
    token="$stars_r;$stars_g;$stars_b:$char"
    if [[ ${stars_seen[$cell]-} != "$token" ]]; then
      printf -v piece '\033[%d;%dH\033[38;2;%d;%d;%dm%s' "$row" "$((col + 1))" "$stars_r" "$stars_g" "$stars_b" "$char"
      stars_output+=$piece stars_seen[$cell]=$token
    fi
  done
  stars_render_cycle=$cycle stars_was_sweeping=$sweeping
  [[ -z $stars_output ]] || stars_output+=$'\033[0m'
  return 0
}
