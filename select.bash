#!/usr/bin/env bash
# Keyboard selection, disabled options, screen lifecycle, and cached backgrounds.

function ez_menu_choose() (
  local selected=$1 banner=$2 key sequence next label index
  local disabled_indices='' enabled_count=0 direction attempts label_color weight number_color note note_text
  local read_status last_tick=-1 redraw=1 layout_dirty=1
  local first=0 visible available_rows frame row frame_banner
  local term_size term_lines term_columns hint_count main_banner=0
  local compact star_margin title_height title_width cached_columns=0 cached_compact=-1 cached_margin=-1
  local star_cache_key='' new_star_key star_row brightness left_gutter right_gutter
  local number_width label_width option_block_width option_left option_right
  local COLUMNS=${COLUMNS:-80} LINES=${LINES:-24}
  local ez_stars_animated=0 input_timeout=1 actual_title_width
  local stars_now stars_origin stars_next stars_period stars_duration stars_step stars_cache_cycle
  local stars_render_cycle stars_was_sweeping stars_frame_started stars_delay
  local stars_sat_max stars_accent_offset stars_white stars_color_cycle
  local stars_top stars_bottom stars_eased stars_r stars_g stars_b stars_output
  local -a stars_cells stars_fade stars_hue stars_sat stars_value
  local -A stars_char stars_palette stars_saturation stars_birth stars_seen stars_rgb_cache
  local -A stars_text_char stars_text_style stars_text_fade stars_text_seen
  local -a banner_rows title_rows fitted_rows hint_rows menu_star_left menu_star_right menu_enabled=() menu_disabled_notes=()
  shift 2
  # Optional disabled indices keep availability separate from labels/actions.
  while (( $# )); do
    case $1 in
      --disabled)
        (( $# >= 2 )) || return 1
        disabled_indices=$2
        shift 2
        ;;
      --disabled-note)
        (( $# >= 3 )) && [[ $2 =~ ^[0-9]+$ ]] || return 1
        menu_disabled_notes[$2]=$3
        shift 3
        ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  local count=$#
  (( count > 0 )) || return 1
  for ((index = 0; index < count; index++)); do menu_enabled[index]=1; done
  for index in $disabled_indices; do
    if [[ $index =~ ^[0-9]+$ ]] && (( index < count )); then
      menu_enabled[index]=0
    fi
  done
  for ((index = 0; index < count; index++)); do
    enabled_count=$((enabled_count + menu_enabled[index]))
  done
  (( enabled_count > 0 )) || return 130
  (( selected < 0 || selected >= count )) && selected=0
  while (( ! menu_enabled[selected] )); do selected=$(( (selected + 1) % count )); done

  if [[ ! -t 0 || ! -t 2 || ${TERM:-dumb} == dumb ]]; then
    printf '%s\n\n' "$banner" >&2
    index=0
    for label in "$@"; do
      label_color=$C_WHITE number_color=$C_PINK weight='' note_text=''
      if (( ! menu_enabled[index] )); then
        label_color=$C_DISABLED number_color=$C_DISABLED_NUMBER weight=$C_STRIKE
        note=${menu_disabled_notes[index]-}
        if [[ -n $note ]] && (( ${#label} + 1 + ${#note} <= ${COLUMNS:-80} - ${#count} - 5 )); then
          note_text=" $note"
        fi
      fi
      printf '  %s%s%d%s  %s%s%s%s%s%s\n' "$number_color" "$weight" "$((index + 1))" "$C_RESET" \
        "$label_color" "$weight$label" "$C_RESET" "$label_color" "$note_text" "$C_RESET" >&2
      index=$((index + 1))
    done
    while IFS= read -r -p "  Choose [1-$count] > " key; do
      for ((index = 0; index < count; index++)); do
        if [[ $key == "$((index + 1))" ]] && (( menu_enabled[index] )); then
          printf '%d' "$index"
          return
        fi
      done
      printf '  %sChoose an available option from 1 to %d.%s\n' "$C_RED" "$count" "$C_RESET" >&2
    done
    return 130
  fi

  # Leave the menu screen before launching an action (including tmux/fg).
  trap 'printf "\033[?1004l\033[0m\033[?25h\033[?1049l" >&2' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  trap 'redraw=1; layout_dirty=1' WINCH CONT
  printf '\033[?1049h\033[?1004h\033[?25l\033[2J\033[H' >&2
  mapfile -t banner_rows <<< "$banner"
  (( ${#banner_rows[@]} > 3 )) && main_banner=1
  if (( main_banner )) && [[ ${EZ_MENU_ANIMATE_STARS:-1} == 1 ]]; then
    ez_stars_animated=1 input_timeout=0.05
    ez_stars_init
  fi
  mapfile -t title_rows < <(ez_menu_title_rows)
  title_width=${#title_rows[0]}
  (( selected >= count )) && selected=0
  while :; do
    frame=''
    if (( ez_stars_animated )); then
      ez_stars_now
      stars_frame_started=$stars_now
    fi
    if (( redraw || SECONDS != last_tick )); then
      # Read the real terminal size: phone keyboards/app switching can change it.
      term_size=$(stty size <&2 2>/dev/null) || term_size=''
      read -r term_lines term_columns <<< "$term_size"
      if [[ $term_lines =~ ^[1-9][0-9]*$ && $term_columns =~ ^[1-9][0-9]*$ ]]; then
        if (( LINES != term_lines || COLUMNS != term_columns )); then
          LINES=$term_lines COLUMNS=$term_columns layout_dirty=1
        fi
      fi
      if (( layout_dirty )); then
        mapfile -t hint_rows < <(ez_menu_hint_lines)
        hint_count=${#hint_rows[@]}
        if (( main_banner )); then
          compact=0 title_height=${#title_rows[@]} star_margin=2
          if (( COLUMNS < title_width + 4 || LINES < title_height + 4 + count + hint_count + 5 )); then
            compact=1 title_height=1
          fi
          while (( star_margin > 0 && LINES < title_height + 2 * star_margin + count + hint_count + 5 )); do
            star_margin=$((star_margin - 1))
          done
          # Regenerate only when the available space changes, not on each tick.
          if (( COLUMNS != cached_columns || compact != cached_compact || star_margin != cached_margin )); then
            banner=$(ez_menu_banner "$compact" "$star_margin")
            cached_columns=$COLUMNS cached_compact=$compact cached_margin=$star_margin
          fi
        fi
        frame_banner=$banner
        mapfile -t fitted_rows <<< "$frame_banner"
        for ((index = 0; index < ${#fitted_rows[@]}; index++)); do
          fitted_rows[index]=$(ez_menu_clip "${fitted_rows[index]}" "$COLUMNS")
        done
        available_rows=$((LINES - ${#fitted_rows[@]} - hint_count - 4))
        (( available_rows < 1 )) && available_rows=1
        visible=$count
        (( visible > available_rows )) && visible=$available_rows
        read -r number_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "$@")
        new_star_key="$COLUMNS:$visible:$option_left:$option_right:${#fitted_rows[@]}:$cached_compact:$cached_margin"
        if [[ $new_star_key != "$star_cache_key" ]]; then
          if (( ez_stars_animated )); then
            actual_title_width=$title_width
            if (( compact )); then
              row=$(ez_menu_title_text)
              actual_title_width=${#row}
              (( actual_title_width > COLUMNS )) && actual_title_width=$COLUMNS
            fi
            ez_stars_layout "${#fitted_rows[@]}" "$title_height" "$actual_title_width" "$star_margin"
          else
            # Keep three clear cells beside the entire option block, including >.
            left_gutter=3 right_gutter=3
            (( left_gutter > option_left )) && left_gutter=$option_left
            (( right_gutter > option_right )) && right_gutter=$option_right
            menu_star_left=() menu_star_right=()
            for ((star_row = 0; star_row < visible; star_row++)); do
              # Descend from 65% of the title's brightness to 5% at the bottom.
              brightness=15
              (( visible > 1 )) && brightness=$((65 - 60 * star_row / (visible - 1)))
              menu_star_left[star_row]=$(ez_menu_side_stars "$((option_left - left_gutter))" "$brightness"; printf '%*s' "$left_gutter" '')
              menu_star_right[star_row]=$(printf '%*s' "$right_gutter" ''; ez_menu_side_stars "$((option_right - right_gutter))" "$brightness")
            done
          fi
          star_cache_key=$new_star_key
        fi
        layout_dirty=0
      fi
      (( first > count - visible )) && first=$((count - visible))
      (( selected < first )) && first=$selected
      (( selected >= first + visible )) && first=$((selected - visible + 1))
      if (( ez_stars_animated )); then
        ez_stars_text_layout "${#fitted_rows[@]}" "$actual_title_width" "$star_margin" "$compact" "$first" "$selected" "$number_width"
      fi
      # Repaint from home in one write. No relative cursor offsets can drift.
      # The once-per-second repaint also repairs terminals without focus events.
      frame=$(
        ez_menu_status
        printf '\n'
        for row in "${fitted_rows[@]}"; do
          # CR before LF cancels pending autowrap after a full-width star row.
          printf '\r\033[2K%s\r\n' "$row"
        done
        printf '\r\033[2K\n'
        ez_menu_draw "$selected" "$first" "$visible" "$@"
        printf '\r\033[J'
      )
      # The foreground redraw erased the overlay; restore it from current state.
      stars_seen=()
      last_tick=$SECONDS
      redraw=0
    fi
    if (( ez_stars_animated )); then
      ez_stars_now
      ez_stars_tick "$((stars_now - stars_origin))"
      if [[ -n $frame ]]; then
        # Write foreground and restored stars together, avoiding a blank flash.
        printf '\033[H%s%s' "$frame" "$stars_output" >&2
      elif [[ -n $stars_output ]]; then
        printf '%s' "$stars_output" >&2
      fi
      ez_stars_now
      stars_delay=$((50 - (stars_now - stars_frame_started)))
      (( stars_delay < 1 )) && stars_delay=1
      printf -v input_timeout '0.%03d' "$stars_delay"
    elif [[ -n $frame ]]; then
      printf '\033[H%s' "$frame" >&2
    fi
    if IFS= read -rsn1 -t "$input_timeout" key; then
      :
    else
      read_status=$?
      (( read_status > 128 )) && continue
      return 130
    fi
    case $key in
      '') printf '%d' "$selected"; return ;;
      $'\014') redraw=1; layout_dirty=1; continue ;;
      $'\033')
        # Accept both normal (CSI) and application-mode (SS3) arrow keys.
        IFS= read -rsn1 -t 0.15 next || return 130
        [[ $next == '[' || $next == O ]] || continue
        sequence=''
        while IFS= read -rsn1 -t 0.15 next; do
          sequence+=$next
          [[ $next == [a-zA-Z~] || ${#sequence} -ge 16 ]] && break
        done
        case $sequence in
          *A) direction=-1 ;;
          *B) direction=1 ;;
          I) redraw=1; layout_dirty=1; continue ;;
          O) continue ;;
          *) continue ;;
        esac
        for ((attempts = 0; attempts < count; attempts++)); do
          selected=$(( (selected + direction + count) % count ))
          (( menu_enabled[selected] )) && break
        done
        ;;
      *) continue ;;
    esac
    redraw=1
  done
  return 130
)
