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

function ez_menu_screen_banner() {
  local title=$1 blank_rows=${2:-0} width=${COLUMNS:-80} header row
  (( width < 1 )) && width=1
  ez_menu_screen_header "$title" "$C_STATUS_BG" header
  printf '%s\n' "$header"
  for ((row = 0; row < blank_rows; row++)); do printf '%*s\n' "$width" ''; done
}

function ez_menu_screen_header() {
  local title=$1 background=$2 output_name=$3 width=${COLUMNS:-80} text
  (( width < 1 )) && width=1
  text=" ${title:0:width-1}"
  printf -v "$output_name" '%s%s%s%-*s%s' "$background" "$C_WHITE" "$C_BOLD" "$width" "$text" "$C_RESET"
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
  local context=${1:-submenu} count=${2:-2} valid=${3:-1}
  local width=$(( ${COLUMNS:-80} - 4 )) line='' hint next first second left_width
  local -a hints=()
  (( width < 1 )) && width=1
  case $context in
    main|submenu)
      if [[ $context == main ]]; then
        if (( ${menu_exit_control:-0} )); then hints+=('▲/▼/◀/▶: Move')
        elif (( count > 1 )); then hints+=('▲/▼: Move'); fi
        hints+=('Enter/Space: Select' 'Esc: Exit')
      else
        if (( count > 1 )); then hints+=('▲/▼/◀/▶: Move')
        else hints+=('◀/▶: Move'); fi
        hints+=('Enter/Space: Select' 'Esc: Back')
      fi
      ;;
    name)
      (( valid )) && hints+=('Enter: Accept')
      hints+=('Esc: Back' 'Ctrl-U: Clear')
      ;;
    directory)
      if (( count > 2 || valid )); then hints+=('▲/▼: Choose'); fi
      if (( count > 2 )); then hints+=('▶/Tab: Open' '◀: Parent'); fi
      (( valid || count > 2 )) && hints+=('Enter: Select')
      hints+=('Esc: Back' 'Ctrl-U: Clear')
      ;;
  esac
  if (( ${#hints[@]} == 4 )); then
    printf -v next '%s   %s   %s   %s' "${hints[@]}"
    if (( ${#next} <= width )); then printf '%s\n' "$next"; return; fi
    left_width=${#hints[0]}
    (( ${#hints[2]} > left_width )) && left_width=${#hints[2]}
    printf -v first '%-*s   %s' "$left_width" "${hints[0]}" "${hints[1]}"
    printf -v second '%-*s   %s' "$left_width" "${hints[2]}" "${hints[3]}"
    if (( ${#first} <= width && ${#second} <= width )); then
      printf '%s\n%s\n' "$first" "$second"
      return
    fi
  fi
  for hint in "${hints[@]}"; do
    (( ${#hint} > width )) && hint=${hint:0:width}
    next=$hint
    [[ -n $line ]] && next="$line   $hint"
    if [[ -n $line && ${#next} -gt $width ]]; then
      printf '%s\n' "$line"
      line=$hint
    else
      line=$next
    fi
  done
  [[ -n $line ]] && printf '%s\n' "$line"
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
  if [[ $weight == "$C_STRIKE" ]]; then
    printf '%s%s%s%s' "$color" "$weight" "$text" "$C_RESET"
    return
  fi
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

# Both submenu Back and home Exit share focus, color and placement rules.
function ez_menu_back_control() {
  local screen_row=$1 indent=$2 back_col back_text='◀—' back_weight='' back_color=$C_GRAY
  back_col=$((indent >= 3 ? indent - 3 : 0))
  if (( ${menu_back_focused:-0} )); then
    back_weight=$C_BOLD back_color=$C_WHITE
    if (( indent >= 8 )); then
      back_col=$((indent - 8)) back_text='◀— Back'
      (( ! ${menu_exit_control:-0} )) || back_text='◀— Exit'
    fi
  fi
  printf '\033[%d;%dH%s%s%s%s\033[%d;1H' "$screen_row" "$((back_col+1))" "$back_color" "$back_weight" "$back_text" "$C_RESET" "$((screen_row+1))"
}

function ez_menu_draw() {
  # Only the chooser opts into reusing its measured geometry. Standalone calls
  # keep measuring their own arguments, even if unrelated outer variables exist.
  local -a cached_geometry=("${marker_width-}" "${label_width-}" "${option_block_width-}" "${option_left-}" "${option_right-}")
  local selected=$1 first=$2 visible=$3 index label marker weight marker_weight label_color label_padding
  local marker_color note note_text accent_suffix gray_suffix prefix_length accent_end base_label screen_row styled_label
  local label_width marker_width option_block_width indent right_width row_label_width row_right_width hint hint_width=0 page
  local left_stars right_stars
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
    if [[ ${menu_spacers[index]:-0} == 1 ]]; then
      if (( ${ez_stars_animated:-0} )); then
        printf '\r'
        ez_stars_render_span "$(( ${#fitted_rows[@]} + 3 + index - first ))" 0 "$COLUMNS"
      else printf '\r\033[2K'; fi
      printf '\r\n'
      if (( ${menu_has_back:-0} && index == first && indent > 0 )); then
        ez_menu_back_control "$(( ${#fitted_rows[@]} + 3 ))" "$indent"
      fi
      continue
    fi
    label=${labels[index]}
    accent_suffix=${menu_accent_suffix[index]-} gray_suffix=${menu_gray_suffix[index]-}
    row_label_width=$label_width row_right_width=$right_width
    if [[ -n $gray_suffix || -n $accent_suffix ]]; then
      row_label_width=$(( ${COLUMNS:-80} - indent - marker_width - 2 ))
      (( row_label_width < 1 )) && row_label_width=1
      row_right_width=1
    fi
    note=${menu_disabled_notes[index]-}
    note_text=''
    # Explanations are indivisible: omit them if the complete label won't fit.
    if [[ ${menu_enabled[index]:-1} == 0 && -n $note ]] && (( ${#label} + 1 + ${#note} <= row_label_width )); then
      note_text=" $note"
    fi
    label=${label:0:row_label_width}
    base_label=${original_labels[index]-${labels[index]}}
    accent_end=${#base_label}
    prefix_length=$((accent_end - ${#accent_suffix}))
    (( prefix_length < 0 )) && prefix_length=0
    (( prefix_length > ${#label} )) && prefix_length=${#label}
    (( accent_end > ${#label} )) && accent_end=${#label}
    printf -v label_padding '%*s' "$((row_label_width - ${#label} - ${#note_text}))" ''
    marker='○' weight='' marker_weight='' label_color=$C_GRAY marker_color=$C_PINK
    if [[ ${menu_enabled[index]:-1} == 0 ]]; then
      weight=$C_STRIKE marker_weight=$C_STRIKE label_color=$C_DISABLED marker_color=$C_DISABLED_NUMBER
    elif (( index == selected && ! ${menu_back_focused:-0} )); then
      marker='●' weight=$C_BOLD marker_weight=$C_BOLD label_color=$C_WHITE
    fi
    if (( ${menu_back_focused:-0} && ${menu_enabled[index]:-1} )); then marker_color=$C_DISABLED_NUMBER; label_color=$C_GRAY; fi
    local accent_color=$C_PINK
    [[ -n $accent_suffix && ( index != selected || ${menu_back_focused:-0} == 1 ) ]] && accent_color=$C_DISABLED_NUMBER
    screen_row=$(( ${#fitted_rows[@]} + 3 + index - first ))
    if (( ${ez_stars_animated:-0} )); then
      printf '\r'
      ez_stars_render_span "$screen_row" 0 "$((indent + marker_width + 1))"
      ez_menu_overlay_text "$screen_row" "$((indent + marker_width + 1))" "${label:0:prefix_length}" "$label_color" "$weight"
      if [[ -n $accent_suffix ]]; then
        ez_stars_render_span "$screen_row" "$((indent + marker_width + 1 + prefix_length))" "$((accent_end - prefix_length))"
      fi
      if [[ -n $gray_suffix ]]; then
        ez_menu_overlay_text "$screen_row" "$((indent + marker_width + 1 + accent_end))" "${label:accent_end}" "$C_RESET$C_GRAY" ''
      fi
      ez_menu_overlay_text "$screen_row" "$((indent + marker_width + 1 + ${#label}))" "$note_text" "$label_color" ''
      ez_stars_render_span "$screen_row" "$((indent + marker_width + 1 + ${#label} + ${#note_text}))" "$(( ${#label_padding} + row_right_width ))"
      printf '\r\n'
      if (( ${menu_has_back:-0} && index == first && indent > 0 )); then
        ez_menu_back_control "$screen_row" "$indent"
      fi
      continue
    fi
    left_stars=${menu_star_left[index-first]-}
    right_stars=${menu_star_right[index-first]-}
    [[ -n $left_stars ]] || printf -v left_stars '%*s' "$indent" ''
    [[ -n $right_stars ]] || printf -v right_stars '%*s' "$right_width" ''
    [[ -n $gray_suffix || -n $accent_suffix ]] && printf -v right_stars '%*s' "$row_right_width" ''
    styled_label="$label_color$weight${label:0:prefix_length}$C_RESET"
    [[ -z $accent_suffix ]] || styled_label+="$accent_color${label:prefix_length:accent_end-prefix_length}$C_RESET"
    [[ -z $gray_suffix ]] || styled_label+="$C_RESET$C_GRAY${label:accent_end}$C_RESET"
    printf '\r\033[2K%s%s%s%s%s %s%s%s%s%s\r\n' \
      "$left_stars" "$marker_color" "$marker_weight" "$marker" "$C_RESET" \
      "$styled_label" "$label_color" "$note_text" "$C_RESET" "$label_padding$right_stars"
    if (( ${menu_has_back:-0} && index == first && indent > 0 )); then
      ez_menu_back_control "$screen_row" "$indent"
    fi
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
