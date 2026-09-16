#!/usr/bin/env bash
# Banner, status, hints, option geometry, and star rendering.

function ez_menu_banner() {
  local compact=${1:-0} star_margin=${2:-2}
  local -a title_rows
  mapfile -t title_rows < <(ez_menu_title_rows)
  local title_width=${#title_rows[0]} star_padding banner_width=${COLUMNS:-80}
  local star_chars='*.+                     ' star_row star_col star_index star_color
  local -a star_colors=("$C_STAR_BLUE" "$C_STAR_LAVENDER" "$C_STAR_PINK")

  # The star field fills the screen; center the lettering within that width.
  if (( compact || banner_width < title_width + 4 )); then
    title_rows=("$(ez_menu_title_text)")
    title_rows[0]=${title_rows[0]:0:banner_width}
    title_width=${#title_rows[0]}
  fi
  star_padding=$(( (banner_width - title_width) / 2 ))

  if (( ${ez_stars_animated:-0} )); then
    # Animated stars are painted later. Format the blank runs in one builtin
    # call instead of walking every placeholder cell during startup/resize.
    printf '\n'
    for ((star_row = -star_margin; star_row < ${#title_rows[@]} + star_margin; star_row++)); do
      if (( star_row >= 0 && star_row < ${#title_rows[@]} )); then
        printf '%*s%s\033[1m%s%s%*s\n' "$star_padding" '' "$C_PINK" "${title_rows[star_row]}" "$C_RESET" "$((banner_width - star_padding - title_width))" ''
      else
        printf '%*s\n' "$banner_width" ''
      fi
    done
    printf '\n'
    return
  fi

  # A sparse star field surrounds the lettering, with no border or outline.
  printf '\n'
  for ((star_row = -star_margin; star_row < ${#title_rows[@]} + star_margin; star_row++)); do
    for ((star_col = 0; star_col < banner_width; star_col++)); do
      if (( star_row >= 0 && star_row < ${#title_rows[@]} )); then
        if (( star_col == star_padding )); then
          printf '%s\033[1m%s%s' "$C_PINK" "${title_rows[star_row]}" "$C_RESET"
          star_col=$((star_col + title_width - 1))
          continue
        elif (( star_col >= star_padding - 2 && star_col < star_padding + title_width + 2 )); then
          printf ' '
          continue
        fi
      fi
      star_index=$((RANDOM % ${#star_chars}))
      if [[ ${star_chars:star_index:1} == ' ' ]]; then
        printf ' '
      else
        star_color=${star_colors[RANDOM % ${#star_colors[@]}]}
        printf '%s%s%s' "$star_color" "${star_chars:star_index:1}" "$C_RESET"
      fi
    done
    printf '\n'
  done
  printf '\n'
}

function ez_menu_status_text() {
  local width=${COLUMNS:-80}
  local clock_text host_text=${HOSTNAME%%.*} path_text=$PWD status_text path_width
  (( width < 1 )) && width=1
  if (( BASH_VERSINFO[0] > 4 || BASH_VERSINFO[1] >= 2 )); then
    printf -v clock_text '%(%a %b %d  %H:%M:%S)T' -1
  else
    clock_text=$(date '+%a %b %d  %H:%M:%S')
  fi
  case $path_text in
    "$HOME") path_text='~' ;;
    "$HOME/"*) path_text="~/${path_text#"$HOME/"}" ;;
  esac
  status_text=" $clock_text | ${host_text:0:12} | "
  path_width=$((width - ${#status_text} - 1))
  if (( path_width > 3 )); then
    if (( ${#path_text} > path_width )); then
      path_text="...${path_text: -$((path_width - 3))}"
    fi
    status_text+=$path_text
  else
    status_text=" $clock_text"
  fi
  printf '%-*s' "$width" "${status_text:0:width}"
}

function ez_menu_status() {
  printf '\r%s%s%s%s' "$C_STATUS_BG" "$C_WHITE" "$(ez_menu_status_text)" "$C_RESET"
}

function ez_menu_clip() {
  local text=$1 width=$2 visible=0 result='' plain take color_pattern=$'^\033\\[[0-9;]*m'
  while [[ -n $text ]] && (( visible < width )); do
    if [[ $text =~ $color_pattern ]]; then
      result+=${BASH_REMATCH[0]}
      text=${text#"${BASH_REMATCH[0]}"}
    else
      plain=${text%%$'\033['*}
      # Unrecognized control sequences retain the old one-character behavior.
      [[ -n $plain ]] || plain=${text:0:1}
      take=${#plain}
      (( take > width - visible )) && take=$((width - visible))
      result+=${plain:0:take} text=${text:take} visible=$((visible + take))
    fi
  done
  printf '%s%s' "$result" "$C_RESET"
}

function ez_menu_hint_lines() {
  local width=$(( ${COLUMNS:-80} - 4 )) full first second left_width
  local -a hints=('Up/Down: move' 'Enter: select' 'Esc: back' 'Ctrl-L: redraw')
  printf -v full '%s   %s   %s   %s' "${hints[@]}"
  if (( ${#full} <= width )); then
    printf '%s\n' "$full"
    return
  fi

  # Align the second column in the two-row layout.
  left_width=${#hints[0]}
  (( ${#hints[2]} > left_width )) && left_width=${#hints[2]}
  printf -v first '%-*s   %s' "$left_width" "${hints[0]}" "${hints[1]}"
  printf -v second '%-*s   %s' "$left_width" "${hints[2]}" "${hints[3]}"
  if (( ${#first} <= width && ${#second} <= width )); then
    printf '%s\n' "$first" "$second"
  else
    printf '%s\n' "${hints[@]}"
  fi
}

function ez_menu_star_palette() {
  local brightness=$1 color code red green blue
  local -a levels=(0 95 135 175 215 255)
  for color in "$C_STAR_BLUE" "$C_STAR_LAVENDER" "$C_STAR_PINK"; do
    code=${color##*;}
    code=${code%m}
    if [[ $code =~ ^[0-9]+$ ]] && (( code >= 16 && code <= 255 )); then
      if (( code >= 232 )); then
        red=$((8 + (code - 232) * 10)) green=$red blue=$red
      else
        code=$((code - 16))
        red=${levels[code / 36]}
        green=${levels[code / 6 % 6]}
        blue=${levels[code % 6]}
      fi
      printf '\033[38;2;%d;%d;%dm\n' "$((red * brightness / 100))" \
        "$((green * brightness / 100))" "$((blue * brightness / 100))"
    else
      printf '%s\n' "$color"
    fi
  done
}

function ez_menu_side_stars() {
  local width=$1 brightness=$2 col star_index star_color
  local star_chars='*.+                     '
  local -a star_colors
  mapfile -t star_colors < <(ez_menu_star_palette "$brightness")
  for ((col = 0; col < width; col++)); do
    star_index=$((RANDOM % ${#star_chars}))
    if [[ ${star_chars:star_index:1} != ' ' ]]; then
      star_color=${star_colors[RANDOM % ${#star_colors[@]}]}
      printf '%s%s%s' "$star_color" "${star_chars:star_index:1}" "$C_RESET"
    else
      printf ' '
    fi
  done
}

function ez_menu_option_layout() {
  local marker_width=1 label_width=0 label option_block_width indent right_width
  local index=0 note measured_width available_width
  available_width=$(( ${COLUMNS:-80} - marker_width - 2 ))
  for label in "$@"; do
    measured_width=${#label}
    note=${menu_disabled_notes[index]-}
    if [[ ${menu_enabled[index]:-1} == 0 && -n $note ]] && (( ${#label} + 1 + ${#note} <= available_width )); then
      measured_width=$(( ${#label} + 1 + ${#note} ))
    fi
    (( measured_width > label_width )) && label_width=$measured_width
    index=$((index + 1))
  done
  # Center one fixed-width block, then left-align every row inside it.
  (( label_width > available_width )) && label_width=$available_width
  (( label_width < 1 )) && label_width=1
  option_block_width=$((marker_width + 1 + label_width))
  indent=$(( (${COLUMNS:-80} - option_block_width) / 2 ))
  (( indent < 0 )) && indent=0
  right_width=$(( ${COLUMNS:-80} - indent - option_block_width ))
  (( right_width < 0 )) && right_width=0
  printf '%d %d %d %d %d\n' "$marker_width" "$label_width" "$option_block_width" "$indent" "$right_width"
}

# Draw foreground words while revealing the animated field through their spaces.
function ez_menu_overlay_text() {
  local row=$1 col=$2 text=$3 color=$4 weight=$5 word spaces
  while [[ $text == *' '* ]]; do
    word=${text%% *}
    [[ -z $word ]] || printf '%s%s%s%s' "$color" "$weight" "$word" "$C_RESET"
    text=${text#"$word"}
    spaces=${text%%[! ]*}
    col=$((col + ${#word}))
    ez_stars_render_span "$row" "$col" "${#spaces}"
    col=$((col + ${#spaces})) text=${text#"$spaces"}
  done
  [[ -z $text ]] || printf '%s%s%s%s' "$color" "$weight" "$text" "$C_RESET"
  return 0
}

function ez_menu_draw() {
  # Only the chooser opts into reusing its measured geometry. Standalone calls
  # keep measuring their own arguments, even if unrelated outer variables exist.
  local -a cached_geometry=("${marker_width-}" "${label_width-}" "${option_block_width-}" "${option_left-}" "${option_right-}")
  local selected=$1 first=$2 visible=$3 index label marker weight marker_weight label_color label_padding
  local marker_color note note_text
  local label_width marker_width option_block_width indent right_width hint hint_width=0 page
  local left_stars right_stars screen_row
  local -a labels hints
  shift 3
  labels=("$@")
  if (( ${ez_menu_draw_cached:-0} )); then
    marker_width=${cached_geometry[0]} label_width=${cached_geometry[1]} option_block_width=${cached_geometry[2]}
    indent=${cached_geometry[3]} right_width=${cached_geometry[4]}
  else
    read -r marker_width label_width option_block_width indent right_width < <(ez_menu_option_layout "$@")
  fi
  for ((index = first; index < first + visible; index++)); do
    label=${labels[index]}
    note=${menu_disabled_notes[index]-}
    note_text=''
    # Explanations are indivisible: omit them if the complete label won't fit.
    if [[ ${menu_enabled[index]:-1} == 0 && -n $note ]] && (( ${#label} + 1 + ${#note} <= label_width )); then
      note_text=" $note"
    fi
    label=${label:0:label_width}
    printf -v label_padding '%*s' "$((label_width - ${#label} - ${#note_text}))" ''
    marker='○' weight='' marker_weight='' label_color=$C_GRAY marker_color=$C_PINK
    if [[ ${menu_enabled[index]:-1} == 0 ]]; then
      weight=$C_STRIKE marker_weight=$C_STRIKE label_color=$C_DISABLED marker_color=$C_DISABLED_NUMBER
    elif (( index == selected )); then
      marker='●' weight=$C_BOLD marker_weight=$C_BOLD label_color=$C_WHITE
    fi
    if (( ${ez_stars_animated:-0} )); then
      screen_row=$(( ${#fitted_rows[@]} + 3 + index - first ))
      printf '\r'
      ez_stars_render_span "$screen_row" 0 "$((indent + marker_width + 1))"
      ez_menu_overlay_text "$screen_row" "$((indent + marker_width + 1))" "$label" "$label_color" "$weight"
      ez_menu_overlay_text "$screen_row" "$((indent + marker_width + 1 + ${#label}))" "$note_text" "$label_color" ''
      ez_stars_render_span "$screen_row" "$((indent + marker_width + 1 + ${#label} + ${#note_text}))" "$(( ${#label_padding} + right_width ))"
      printf '\r\n'
      continue
    fi
    left_stars=${menu_star_left[index-first]-}
    right_stars=${menu_star_right[index-first]-}
    [[ -n $left_stars ]] || printf -v left_stars '%*s' "$indent" ''
    [[ -n $right_stars ]] || printf -v right_stars '%*s' "$right_width" ''
    printf '\r\033[2K%s%s%s%s%s %s%s%s%s%s%s%s%s\r\n' \
      "$left_stars" "$marker_color" "$marker_weight" "$marker" "$C_RESET" \
      "$label_color" "$weight$label" "$C_RESET" "$label_color" "$note_text" "$C_RESET" "$label_padding" "$right_stars"
  done
  if (( ${ez_stars_animated:-0} )); then
    screen_row=$(( ${#fitted_rows[@]} + visible + 3 ))
    printf '\r'
    ez_stars_render_span "$screen_row" 0 "$COLUMNS"
    printf '\r'
  else
    printf '\r\033[2K'
  fi
  if (( visible < ${#labels[@]} )); then
    printf -v page '%d-%d of %d' "$((first + 1))" "$((first + visible))" "${#labels[@]}"
    indent=$(( (${COLUMNS:-80} - ${#page}) / 2 ))
    (( indent < 0 )) && indent=0
    if (( ${ez_stars_animated:-0} )); then
      printf '\033[%d;%dH%s%s%s' "$screen_row" "$((indent + 1))" "$C_STAR_LAVENDER" "${page:0:COLUMNS}" "$C_RESET"
    else
      printf '%*s%s%s%s' "$indent" '' "$C_STAR_LAVENDER" "$page" "$C_RESET"
    fi
  fi
  printf '\r\n'
  if (( ${ez_menu_draw_cached:-0} )); then hints=("${hint_rows[@]}");
  else mapfile -t hints < <(ez_menu_hint_lines); fi
  for hint in "${hints[@]}"; do
    (( ${#hint} > hint_width )) && hint_width=${#hint}
  done
  indent=$(( (${COLUMNS:-80} - hint_width) / 2 ))
  (( indent < 0 )) && indent=0
  screen_row=$(( ${#fitted_rows[@]} + visible + 4 ))
  for hint in "${hints[@]}"; do
    if (( ${ez_stars_animated:-0} )); then
      printf '\r'
      ez_stars_render_span "$screen_row" 0 "$COLUMNS"
      printf '\r\n'
      screen_row=$((screen_row + 1))
    else
      printf '\r\033[2K%*s%s%s%s\n' "$indent" '' "$C_STAR_LAVENDER" "$hint" "$C_RESET"
    fi
  done
  if (( ${ez_stars_animated:-0} )); then
    for ((; screen_row <= stars_bottom; screen_row++)); do
      printf '\r'
      ez_stars_render_span "$screen_row" 0 "$COLUMNS"
      printf '\r\n'
    done
  fi
}
