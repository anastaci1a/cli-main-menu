#!/usr/bin/env bash
# Keyboard selection, disabled options, screen lifecycle, and cached backgrounds.

function ez_menu_choose() (
  local selected=$1 banner=$2 key sequence next label index
  local disabled_indices='' enabled_count=0 direction attempts label_color weight number_color note note_text
  local read_status last_tick=-1 redraw=1 layout_dirty=1
  local full_redraw=1 option_frame=0 text_cache_key='' new_text_key
  local last_repair=$SECONDS
  local status_line='' status_output='' status_seen='' status_token elapsed
  local first=0 visible available_rows frame row frame_banner
  local term_size term_lines term_columns hint_count main_banner=0
  local terminal_state
  local compact star_margin title_height title_width cached_columns=0 cached_compact=-1 cached_margin=-1
  local star_cache_key='' new_star_key star_row brightness left_gutter right_gutter
  local marker_width label_width option_block_width option_left option_right
  local ez_menu_draw_cached=0
  local stars_repair_active=0 stars_repair_index stars_repair_last stars_repair_spaces
  local stars_emit_limit
  local -a stars_repair_cells
  local COLUMNS=${COLUMNS:-80} LINES=${LINES:-24}
  local ez_stars_animated=0 input_timeout=1 actual_title_width
  local stars_now stars_origin stars_next stars_period stars_duration stars_step stars_cache_cycle
  local stars_travel stars_rise stars_tail
  local stars_render_cycle stars_was_sweeping stars_frame_started stars_delay
  local stars_sat_max stars_accent_offset stars_white stars_color_cycle stars_hue_spread stars_sweep_bottom stars_bar_bg
  local stars_top stars_bottom stars_eased stars_r stars_g stars_b stars_output
  local stars_rgb_value
  local stars_rotation_seed stars_rotation_state stars_rotation_cycle stars_rotation_value stars_pair_epoch
  local -a stars_rotation
  local stars_bar_cycle stars_bar_from stars_bar_to stars_bar_target_bg
  local stars_spawn_weight stars_twinkle_advance stars_twinkle_rate stars_twinkle_delay
  local stars_density_max
  local stars_horizon_delay stars_horizon_next
  local stars_geometry_key
  local -a stars_flash stars_arrival_cell stars_settled stars_text_settled
  local -a stars_star_band stars_text_band stars_text_dirty
  local stars_work_ready stars_work_dirty stars_last_elapsed stars_last_phase
  local -a stars_color_pair stars_prefetch_cells
  local stars_prefetch_cycle stars_prefetch_cursor stars_prefetch_budget
  local stars_density_percent stars_replace_head stars_replace_tail
  local -a stars_peak stars_replenish stars_replace_queue stars_star_dirty stars_band_member
  local -a stars_replacement_birth
  local -a stars_twinkle_curve stars_twinkle_glyph stars_replacement_curve
  local -a stars_baseline_blocked stars_clear_pending
  local -a stars_cells stars_fade stars_density stars_hue stars_sat stars_value stars_sweep_arrival
  local -A stars_char stars_palette stars_saturation stars_birth stars_seen stars_rgb_cache
  local -A stars_text_char stars_text_style stars_text_fade stars_text_seen
  local -A stars_text_flash stars_occluded
  local -A stars_hue_offset stars_cell_render stars_text_palette
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

  # read -s only suppresses echo during the read itself. Keep it off while
  # rendering too, so queued arrow bytes never appear as literal ^[[A text.
  terminal_state=$(stty -g <&0 2>/dev/null) || return 130
  # Restore the exact input modes before launching an action (including tmux/fg).
  trap 'stty "$terminal_state" <&0 2>/dev/null; printf "\033[?1004l\033[0m\033[?25h\033[?1049l" >&2' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  trap 'redraw=1; layout_dirty=1; full_redraw=1' WINCH
  trap 'stty -echo -echonl <&0 2>/dev/null; redraw=1; layout_dirty=1; full_redraw=1' CONT
  stty -echo -echonl <&0 || return 130
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
    frame='' status_output='' option_frame=0
    if (( ez_stars_animated )); then
      ez_stars_now
      stars_frame_started=$stars_now
      # Keep the Termux recovery fallback for missing focus/continue events,
      # without coupling every clock update to a full-screen repaint.
      (( SECONDS - last_repair >= 5 )) && full_redraw=1
    fi
    if (( redraw || SECONDS != last_tick )); then
      # Read the real terminal size: phone keyboards/app switching can change it.
      term_size=$(stty size <&2 2>/dev/null) || term_size=''
      read -r term_lines term_columns <<< "$term_size"
      if [[ $term_lines =~ ^[1-9][0-9]*$ && $term_columns =~ ^[1-9][0-9]*$ ]]; then
        if (( LINES != term_lines || COLUMNS != term_columns )); then
          LINES=$term_lines COLUMNS=$term_columns layout_dirty=1 full_redraw=1
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
        (( first > count - visible )) && first=$((count - visible))
        (( selected < first )) && first=$selected
        (( selected >= first + visible )) && first=$((selected - visible + 1))
        read -r marker_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "$@")
        ez_menu_draw_cached=$ez_stars_animated
        new_star_key="$COLUMNS:$LINES:$visible:$option_left:$option_right:${#fitted_rows[@]}:$cached_compact:$cached_margin"
        if [[ $new_star_key != "$star_cache_key" ]]; then
          if (( ez_stars_animated )); then
            actual_title_width=$title_width
            if (( compact )); then
              row=$(ez_menu_title_text)
              actual_title_width=${#row}
              (( actual_title_width > COLUMNS )) && actual_title_width=$COLUMNS
            fi
            ez_stars_layout "${#fitted_rows[@]}" "$title_height" "$actual_title_width" "$star_margin" "$count" "$first" "$@"
          else
            # Keep clear gutter cells beside the option block and its selector.
            left_gutter=3 right_gutter=3
            (( left_gutter > option_left )) && left_gutter=$option_left
            (( right_gutter > option_right )) && right_gutter=$option_right
            menu_star_left=() menu_star_right=()
            for ((star_row = 0; star_row < visible; star_row++)); do
              # Keep the darkest fade endpoint one row beyond the visible field.
              brightness=$((65 - 60 * star_row / visible))
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
        new_text_key="$new_star_key:$first:$selected"
        if [[ $new_text_key != "$text_cache_key" ]]; then
          if [[ ${text_cache_key%:*} == "$new_star_key:$first" ]]; then
            ez_stars_select "$first" "$selected" "${#fitted_rows[@]}"
          else
            ez_stars_text_layout "${#fitted_rows[@]}" "$actual_title_width" "$star_margin" "$compact" "$first" "$selected" "$@"
            ez_stars_build_work
          fi
          text_cache_key=$new_text_key
        fi
        status_line=$(ez_menu_status_text)
        (( redraw )) && option_frame=1
      else
        # Static/submenu rendering keeps the original terminal fallback.
        frame=$(
          ez_menu_status
          printf '\n'
          for row in "${fitted_rows[@]}"; do printf '\r\033[2K%s\r\n' "$row"; done
          printf '\r\033[2K\n'
          ez_menu_draw "$selected" "$first" "$visible" "$@"
          printf '\r\033[J'
        )
      fi
      last_tick=$SECONDS
      redraw=0
    fi
    if (( ez_stars_animated )); then
      ez_stars_now
      elapsed=$((stars_now - stars_origin))
      stars_emit_limit=-1
      if (( full_redraw )); then stars_emit_limit=0;
      elif (( option_frame )); then stars_emit_limit=$(( (${#fitted_rows[@]} + 2) * COLUMNS )); fi
      ez_stars_tick "$elapsed" "$stars_emit_limit"
      ez_stars_bar_color "$elapsed"
      status_token="$stars_bar_bg:$status_line"
      if [[ $status_token != "$status_seen" ]] || (( full_redraw )); then
        printf -v status_output '\033[1;1H%s%s%s%s' "$stars_bar_bg" "$C_WHITE" "$status_line" "$C_RESET"
        status_seen=$status_token
      fi
      if (( full_redraw )); then
        # Paint final colors directly: no blank or original-color underlay.
        frame=$(
          ez_stars_prepare_repair
          printf '\033[H%s\r\n' "$status_output"
          for ((row = 2; row <= ${#fitted_rows[@]} + 2; row++)); do
            ez_stars_render_span "$row" 0 "$COLUMNS"
            printf '\r\n'
          done
          ez_menu_draw "$selected" "$first" "$visible" "$@"
          printf '\r\033[J'
        )
        status_output='' stars_output='' full_redraw=0 last_repair=$SECONDS
      elif (( option_frame )); then
        frame=$(
          ez_stars_prepare_repair "$(( (${#fitted_rows[@]} + 2) * COLUMNS ))"
          printf '\033[%d;1H' "$(( ${#fitted_rows[@]} + 3 ))"
          ez_menu_draw "$selected" "$first" "$visible" "$@"
        )
      fi
      printf '%s%s%s' "$status_output" "$frame" "$stars_output" >&2
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
      $'\014') redraw=1; layout_dirty=1; full_redraw=1; continue ;;
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
          I) redraw=1; layout_dirty=1; full_redraw=1; continue ;;
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
