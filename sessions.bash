#!/usr/bin/env bash
# Codex session metadata lives in tmux; no persistent index is needed.

ez_codex_name_chars() {
  local name=$1 char i
  [[ -n $name ]] || return 1
  for ((i=0;i<${#name};i++)); do
    char=${name:i:1}
    case $char in
      [a-zA-Z0-9]|' '|_|+|-|=|'~'|'('|')'|'['|']') ;;
      *) return 1;;
    esac
  done
}

ez_codex_scan() {
  local id name created attached activity i j rank
  ez_codex_ids=() ez_codex_names=() ez_codex_created=() ez_codex_rank=()
  while IFS='|' read -r id name created attached activity; do
    [[ $name == codex-switcher ]] && continue
    [[ $id == \$* && ( $name == codex || $name == codex-* ) && $created =~ ^[0-9]+$ ]] || continue
    [[ $name == codex ]] || name=${name#codex-}
    ez_codex_name_chars "$name" || continue
    rank=$created
    [[ $attached =~ ^[0-9]+$ ]] && (( attached > rank )) && rank=$attached
    [[ $activity =~ ^[0-9]+$ ]] && (( activity > rank )) && rank=$activity
    i=${#ez_codex_ids[@]}
    while (( i > 0 && rank > ez_codex_rank[i-1] )); do
      j=$((i-1))
      ez_codex_ids[i]=${ez_codex_ids[j]} ez_codex_names[i]=${ez_codex_names[j]}
      ez_codex_created[i]=${ez_codex_created[j]} ez_codex_rank[i]=${ez_codex_rank[j]}
      i=$j
    done
    ez_codex_ids[i]=$id ez_codex_names[i]=$name
    ez_codex_created[i]=$created ez_codex_rank[i]=$rank
  done < <(tmux list-sessions -F '#{session_id}|#{session_name}|#{session_created}|#{session_last_attached}|#{@ez_codex_last_used}' 2>/dev/null)
}

ez_codex_session_accounts() {
  local instances session account index
  local -A by_session=()
  ez_codex_accounts=()
  if command -v codex-switcher >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    instances=$(codex-switcher instances 2>/dev/null) || instances=''
    while IFS=$'\t' read -r session account; do
      [[ -n $session && -n $account ]] && by_session["$session"]=$account
    done < <(jq -r '.[] | select(.inactive == false) | [.tmux_session, .account] | @tsv' <<< "$instances" 2>/dev/null)
  fi
  for ((index=0; index<${#ez_codex_names[@]}; index++)); do
    session=${ez_codex_names[index]}
    [[ $session == codex ]] || session=codex-$session
    ez_codex_accounts[index]=${by_session[$session]:-unknown}
  done
}

ez_menu_has_codex() { ez_codex_scan; (( ${#ez_codex_ids[@]} > 0 )); }
ez_menu_codex_label() {
  ez_codex_scan
  printf 'Codex: Resume'
  (( ${#ez_codex_ids[@]} )) && printf ' (%s)' "${ez_codex_names[0]}"
  return 0
}
ez_codex_attach() {
  tmux has-session -t "$1" 2>/dev/null || { printf 'Codex session is no longer available.\n' >&2; return 1; }
  local now
  printf -v now '%(%s)T' -1
  tmux set-option -t "$1" @ez_codex_last_used "$now" || return
  if [[ -n ${TMUX:-} ]]; then
    tmux switch-client -t "$1"
    return $?
  fi
  (( ${ez_menu_shared_screen:-0} )) && printf '\033[?1004l\033[0m\033[?25h\033[?1049l' >&2
  tmux attach-session -t "$1"
  local result=$?
  (( ${ez_menu_shared_screen:-0} )) && printf '\033[?1049h\033[?25l' >&2
  return "$result"
}
ez_menu_codex() {
  ez_codex_scan
  (( ${#ez_codex_ids[@]} )) || return 0
  ez_codex_attach "${ez_codex_ids[0]}"
}
ez_codex_duration() {
  local seconds=$1 days hours minutes
  (( seconds < 0 )) && seconds=0
  days=$((seconds/86400)) hours=$((seconds/3600%24)) minutes=$((seconds/60%60)) seconds=$((seconds%60))
  if (( days )); then printf '%d:%02d:%02d:%02d' "$days" "$hours" "$minutes" "$seconds"
  elif (( hours )); then printf '%d:%02d:%02d' "$hours" "$minutes" "$seconds"
  else printf '%d:%02d' "$minutes" "$seconds"; fi
}
ez_codex_valid_name() {
  local candidate=$1 except=${2-} i
  [[ $candidate != switcher ]] || return 1
  ez_codex_name_chars "$candidate" || return 1
  ez_codex_scan
  for ((i=0;i<${#ez_codex_ids[@]};i++)); do
    [[ ${ez_codex_names[i]} == "$candidate" && ${ez_codex_ids[i]} != "$except" ]] && return 1
  done
  return 0
}

# Expand only variable references and the current user's tilde, never eval.
ez_codex_expand_dir() {
  local rest=$1 expanded='' variable char value
  case $rest in '~') rest=$HOME;; '~/'*) rest=$HOME/${rest:2};; esac
  while [[ -n $rest ]]; do
    char=${rest:0:1}; rest=${rest:1}
    if [[ $char == $'\\' && ${rest:0:1} == '$' ]]; then
      expanded+='$'; rest=${rest:1}
    elif [[ $char == '$' ]]; then
      if [[ $rest =~ ^\{([a-zA-Z_][a-zA-Z0-9_]*)\} ]]; then
        variable=${BASH_REMATCH[1]}
        if [[ -v $variable ]]; then
          value=${!variable}; expanded+=$value; rest=${rest:${#BASH_REMATCH[0]}}
        else expanded+='$'; fi
      elif [[ $rest =~ ^([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
        variable=${BASH_REMATCH[1]}
        if [[ -v $variable ]]; then
          value=${!variable}; expanded+=$value; rest=${rest:${#variable}}
        else expanded+='$'; fi
      else expanded+='$'; fi
    else expanded+=$char; fi
  done
  [[ -n $expanded ]] || return 1
  [[ $expanded == /* ]] || expanded=${ez_codex_start_dir:-$PWD}/$expanded
  REPLY=$expanded
}
ez_codex_resolve_dir() {
  local REPLY
  ez_codex_expand_dir "$1" || return 1
  ez_codex_resolve_expanded_dir "$REPLY"
}
ez_codex_resolve_expanded_dir() {
  local physical
  physical=$(CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P) || return 1
  # Bash may preserve a double leading slash even after resolving the path.
  while [[ $physical == //* ]]; do physical=${physical#/}; done
  printf '%s\n' "$physical"
}
ez_codex_new_dir_target() {
  local REPLY expanded parent name physical target
  ez_codex_expand_dir "$1" || return 1
  expanded=$REPLY
  while [[ $expanded == */ && $expanded != / ]]; do expanded=${expanded%/}; done
  name=${expanded##*/}
  [[ -n $name ]] || return 1
  parent=${expanded%/*}
  [[ -n $parent ]] || parent=/
  physical=$(CDPATH='' cd -P -- "$parent" 2>/dev/null && pwd -P) || return 1
  while [[ $physical == //* ]]; do physical=${physical#/}; done
  [[ -w $physical && -x $physical ]] || return 1
  target=${physical%/}/$name
  [[ ! -e $target && ! -L $target ]] || return 1
  printf '%s\n' "$target"
}
ez_codex_new_dir_name_target() {
  local parent=$1 name=$2 target
  [[ -n $name && $name != */* && -d $parent && -w $parent && -x $parent ]] || return 1
  target=${parent%/}/$name
  [[ ! -e $target && ! -L $target ]] || return 1
  printf '%s\n' "$target"
}

ez_codex_input_line() {
  local input=$1 kind=$2 valid=$3 width=$4 cursor=${5:-${#1}} shown hint color start position before under after
  hint='Type a unique session name'
  [[ $kind == 'Start directory' ]] && hint='Type or navigate to a directory'
  [[ $kind == 'New directory name' ]] && hint='Type a new directory name'
  color=$C_RED; (( valid )) && color=$C_WHITE
  shown=${input//[[:cntrl:]]/?}
  (( width < 4 )) && width=4
  if [[ -n $shown ]]; then
    start=$((cursor-width+4))
    (( start < 0 )) && start=0
    shown=${shown:start:width-3}
    position=$((cursor-start))
    before=${shown:0:position} under=${shown:position:1} after=${shown:position+1}
    [[ -n $under ]] || under=' '
    printf '\033[2K%s> %s\033[48;2;255;255;255m\033[38;2;0;0;0m%s\033[0m%s%s' "$color" "$before" "$under" "$color" "$after"
  else
    hint=${hint:0:width-2}
    printf '\033[2K%s> \033[48;2;255;255;255m\033[38;2;0;0;0m%s\033[0m%s%s%s' \
      "$color" "${hint:0:1}" "$C_DISABLED" "${hint:1}" "$C_RESET"
  fi
}

# Both form fields own a subshell so every exit restores the exact tty modes.
# Up/down selects suggestions; right/Tab enters one, left opens its parent.
ez_codex_field() (
  local kind=$1 input=$2 except=${3-} key seq state valid resolved creatable create_target create_parent path_input base prefix path search_base cursor=${#2} parent
  local selected=0 first=0 rows cols size i display dirty=1 layout_dirty=1 frame_dirty=1 direction attempts candidate found
  local menu_has_back=0 menu_back_focused=0 last_back_focus=0 answer
  local count visible available_rows marker_width label_width option_block_width option_left option_right read_status old_first geometry_changed option_frame
  local frame banner new_geometry geometry='' elapsed status_line='' status_seen='' status_token status_output='' last_tick=-1
  local header_line='' header_seen='' header_token header_output=''
  local stars_now stars_origin stars_next stars_period stars_duration stars_step stars_cache_cycle
  local stars_travel stars_rise stars_tail stars_render_cycle stars_was_sweeping stars_frame_started stars_delay
  local stars_sat_max stars_accent_offset stars_white stars_color_cycle stars_hue_spread stars_sweep_bottom stars_bar_bg
  local stars_sub_bar_bg stars_sub_bar_from stars_sub_bar_to stars_sub_bar_target_bg
  local stars_top stars_bottom stars_eased stars_r stars_g stars_b stars_output stars_rgb_value
  local stars_rotation_seed stars_rotation_state stars_rotation_cycle stars_rotation_value stars_pair_epoch
  local stars_bar_cycle stars_bar_from stars_bar_to stars_bar_target_bg
  local stars_spawn_weight stars_twinkle_advance stars_twinkle_rate stars_twinkle_delay stars_density_max
  local stars_horizon_delay stars_horizon_next stars_geometry_key
  local stars_work_ready stars_work_dirty stars_last_elapsed stars_last_phase
  local stars_prefetch_cycle stars_prefetch_cursor stars_prefetch_budget
  local stars_density_percent stars_replace_head stars_replace_tail
  local stars_repair_active stars_repair_index stars_repair_last stars_repair_spaces stars_emit_limit
  local ez_stars_animated=1 ez_menu_draw_cached=1 input_timeout=0.05
  local COLUMNS=${COLUMNS:-80} LINES=${LINES:-24}
  local -a choices=() labels=() fitted_rows=() hint_rows=() title_rows=() menu_enabled=() menu_disabled_notes=()
  local -a stars_rotation stars_flash stars_arrival_cell stars_settled stars_text_settled
  local -a stars_star_band stars_text_band stars_text_dirty stars_color_pair stars_prefetch_cells
  local -a stars_peak stars_replenish stars_replace_queue stars_star_dirty stars_band_member stars_replacement_birth
  local -a stars_twinkle_curve stars_twinkle_glyph stars_replacement_curve stars_baseline_blocked stars_clear_pending
  local -a stars_cells stars_fade stars_density stars_hue stars_sat stars_value stars_sweep_arrival stars_repair_cells
  local -A stars_char stars_palette stars_saturation stars_birth stars_seen stars_rgb_cache
  local -A stars_text_char stars_text_style stars_text_fade stars_text_seen stars_text_flash stars_occluded
  local -A stars_hue_offset stars_cell_render stars_text_palette
  [[ $kind == 'Start directory' ]] && menu_has_back=1
  if [[ ! -t 0 || ! -t 2 || ${TERM:-dumb} == dumb ]]; then
    while :; do
      printf '%s > ' "$kind" >&2
      IFS= read -r input || return 130
      if [[ $kind == 'Session name' ]]; then
        ez_codex_valid_name "$input" "$except" && { printf '%s' "$input"; return; }
      else
        resolved=$(ez_codex_resolve_dir "$input") && { printf '%s' "$resolved"; return; }
        if create_target=$(ez_codex_new_dir_target "$input"); then
          printf 'Create directory %s? [y/N] ' "$create_target" >&2
          IFS= read -r answer || return 130
          if [[ $answer == [yY] || $answer == [yY][eE][sS] ]] && mkdir -- "$create_target" 2>/dev/null; then
            ez_codex_resolve_expanded_dir "$create_target"
            return
          fi
        fi
      fi
      printf 'Invalid %s. Please try again.\n' "$kind" >&2
    done
  fi
  state=$(stty -g) || return 130
  if (( ${ez_menu_shared_screen:-0} )); then
    trap 'stty "$state"; printf "\033[0m" >&2' EXIT
  else
    trap 'stty "$state"; printf "\033[0m\033[?25h\033[?1049l" >&2' EXIT
  fi
  trap 'exit 130' INT
  trap 'exit 143' HUP TERM
  trap 'dirty=1; layout_dirty=1; frame_dirty=1' WINCH
  stty -echo -icanon min 1 time 0
  if (( ${ez_menu_shared_screen:-0} )); then
    printf '\033[?25l' >&2
  else
    printf '\033[?1049h\033[?25l' >&2
  fi
  ez_stars_init
  while :; do
    ez_stars_now
    stars_frame_started=$stars_now
    if (( dirty )); then
      valid=0 creatable=0 resolved='' create_target=''
      if [[ $kind == 'Session name' ]]; then
        ez_codex_valid_name "$input" "$except" && valid=1
      elif [[ $kind == 'New directory name' ]]; then
        create_target=$(ez_codex_new_dir_name_target "$create_parent" "$input") && valid=1
      else
        resolved=$(ez_codex_resolve_dir "$input") && valid=1
        if (( ! valid )); then
          create_target=$(ez_codex_new_dir_target "$input") && creatable=1
        fi
        choices=() selected=0 first=0
        if (( valid )); then base=$resolved prefix=''
        else
          base=${input%/*} prefix=${input##*/}
          [[ $input == */* ]] || base=${ez_codex_start_dir:-$PWD}
          [[ -n $base ]] || base=/
          base=$(ez_codex_resolve_dir "$base") || base=''
        fi
        if [[ -n $input && -n $base ]]; then
          # Subshell options cannot leak into the caller. Include hidden dirs.
          shopt -s nullglob dotglob
          search_base=${base%/}
          for path in "$search_base"/"$prefix"*/; do
            [[ -d $path && -x $path ]] && choices+=("${path%/}")
          done
        fi
      fi
      dirty=0
    fi
    if (( frame_dirty || SECONDS != last_tick )); then
      (( frame_dirty )) && [[ $frame != selection ]] && frame=dirty
      size=$(stty size); read -r rows cols <<< "$size"
      (( rows > 0 )) || rows=24
      (( cols > 0 )) || cols=80
      (( rows != LINES || cols != COLUMNS )) && layout_dirty=1
      LINES=$rows COLUMNS=$cols
      labels=()
      if [[ $kind == 'Session name' ]]; then
        labels=('Continue')
      elif [[ $kind == 'New directory name' ]]; then
        labels=('Create directory')
      else
        labels=('Use this directory' 'Add new directory')
        for path in "${choices[@]}"; do
          display=${path##*/}
          display=${display//[[:cntrl:]]/?}
          labels+=("$display/")
        done
      fi
      count=${#labels[@]}
      menu_enabled=()
      for ((i=0;i<count;i++)); do menu_enabled[i]=1; done
      (( valid )) || menu_enabled[0]=0
      if [[ $kind == 'Start directory' ]]; then
        (( valid || creatable )) || menu_enabled[1]=0
      fi
      (( selected >= count )) && selected=0
      if (( ! menu_enabled[selected] )); then
        for ((i=0;i<count;i++)); do
          if (( menu_enabled[i] )); then selected=$i; break; fi
        done
      fi
      if [[ $kind == 'Session name' || $kind == 'New directory name' ]]; then
        mapfile -t hint_rows < <(ez_menu_hint_lines name 1 "$valid")
      else
        mapfile -t hint_rows < <(ez_menu_hint_lines directory "$count" "$((valid || creatable))")
      fi
      # The field occupies its own row between the heading and the choices.
      banner=$(ez_menu_screen_banner "$kind" 2)
      mapfile -t fitted_rows <<< "$banner"
      available_rows=$((LINES - ${#fitted_rows[@]} - ${#hint_rows[@]} - 4))
      (( available_rows < 1 )) && available_rows=1
      visible=$count
      (( visible > available_rows )) && visible=$available_rows
      old_first=$first
      (( selected < first )) && first=$selected
      (( selected >= first+visible )) && first=$((selected-visible+1))
      read -r marker_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "${labels[@]}")
      new_geometry="$COLUMNS:$LINES:$visible:$option_left:$option_right:${#hint_rows[@]}"
      geometry_changed=0
      if [[ $new_geometry != "$geometry" || $layout_dirty == 1 ]]; then
        geometry_changed=1
        ez_stars_layout "${#fitted_rows[@]}" 1 "$COLUMNS" 1 "$count" "$first" "${labels[@]}"
        geometry=$new_geometry layout_dirty=0
      fi
      if [[ $frame == selection && $old_first == "$first" && $geometry_changed == 0 ]]; then
        if (( menu_back_focused != last_back_focus )); then
          ez_stars_text_layout "${#fitted_rows[@]}" "$COLUMNS" 1 0 "$first" "$selected" "${labels[@]}"
          ez_stars_build_work
        else
          ez_stars_select "$first" "$selected" "${#fitted_rows[@]}"
        fi
      else
        frame=dirty
        ez_stars_text_layout "${#fitted_rows[@]}" "$COLUMNS" 1 0 "$first" "$selected" "${labels[@]}"
        ez_stars_build_work
      fi
      last_back_focus=$menu_back_focused
      status_line=$(ez_menu_status_text)
      frame_dirty=0 last_tick=$SECONDS
    fi
    ez_stars_now
    elapsed=$((stars_now-stars_origin))
    stars_emit_limit=-1
    if [[ $frame == selection ]]; then
      stars_emit_limit=$(( (${#fitted_rows[@]}+2)*COLUMNS ))
    elif [[ $frame != ready ]]; then
      stars_emit_limit=0
    fi
    ez_stars_tick "$elapsed" "$stars_emit_limit"
    ez_stars_bar_color "$elapsed"
    status_output=''
    status_token="$stars_bar_bg:$status_line"
    if [[ $status_token != "$status_seen" || $frame != ready ]]; then
      printf -v status_output '\033[1;1H%s%s%s%s' "$stars_bar_bg" "$C_WHITE" "$status_line" "$C_RESET"
      status_seen=$status_token
    fi
    header_output=''
    header_token="$stars_sub_bar_bg:$COLUMNS:$kind"
    if [[ $header_token != "$header_seen" || $frame != ready ]]; then
      ez_menu_screen_header "$kind" "$stars_sub_bar_bg" header_line
      printf -v header_output '\033[2;1H%s' "$header_line"
      header_seen=$header_token
    fi
    if [[ -z $frame || $frame == dirty ]]; then
      frame=$(
        ez_stars_prepare_repair
        printf '\033[H%s%s%s%s\r\n' "$stars_bar_bg" "$C_WHITE" "$status_line" "$C_RESET"
        for ((i=2;i<=${#fitted_rows[@]}+2;i++)); do
          if (( i == 2 )); then printf '%s' "$header_line"
          elif (( i == 4 )); then ez_codex_input_line "$input" "$kind" "$((valid || creatable))" "$COLUMNS" "$cursor"
          else ez_stars_render_span "$i" 0 "$COLUMNS"; fi
          printf '\r\n'
        done
        ez_menu_draw "$selected" "$first" "$visible" "${labels[@]}"
        printf '\r\033[J'
      )
      printf '%s' "$frame" >&2
      frame=ready stars_output=''
    elif [[ $frame == selection ]]; then
      option_frame=$(
        ez_stars_prepare_repair "$(( (${#fitted_rows[@]}+2)*COLUMNS ))"
        printf '\033[%d;1H' "$(( ${#fitted_rows[@]}+3 ))"
        ez_menu_draw "$selected" "$first" "$visible" "${labels[@]}"
      )
      printf '%s%s%s%s' "$status_output" "$header_output" "$option_frame" "$stars_output" >&2
      frame=ready
    else
      printf '%s%s%s' "$status_output" "$header_output" "$stars_output" >&2
    fi
    ez_stars_now
    stars_delay=$((50-(stars_now-stars_frame_started)))
    (( stars_delay < 1 )) && stars_delay=1
    printf -v input_timeout '0.%03d' "$stars_delay"
    if IFS= read -rsN1 -t "$input_timeout" key; then
      :
    else
      read_status=$?
      (( read_status > 128 )) && continue
      return 130
    fi
    [[ $key == $'\014' ]] && continue
    frame=dirty frame_dirty=1
    if [[ $key == $'\e' ]]; then
      seq=''
      if IFS= read -rsN1 -t 0.08 seq; then
        if [[ $seq == '[' || $seq == O ]]; then
          IFS= read -rsN1 -t 0.08 key || continue
          case $key in
            A|B) direction=1; [[ $key == A ]] && direction=-1
                 found=0
                 for ((attempts=1;attempts<=count;attempts++)); do
                   candidate=$(( (selected + direction*attempts + count*attempts) % count ))
                   if (( menu_enabled[candidate] )); then
                     selected=$candidate; found=1; break
                   fi
                 done
                 (( found )) && menu_back_focused=0
                 frame=selection;;
            C) if (( menu_back_focused )); then
                 menu_back_focused=0; frame=selection
               elif [[ $kind == 'Session name' || $kind == 'New directory name' ]]; then
                 (( cursor < ${#input} )) && cursor=$((cursor+1))
               elif (( ${#choices[@]} )); then
                 (( selected<2 )) && selected=2
                 input=$(ez_codex_resolve_dir "${choices[selected-2]}") || continue
                 cursor=${#input} dirty=1
               fi;;
            D) if [[ $kind == 'Session name' || $kind == 'New directory name' ]]; then
                 (( cursor > 0 )) && cursor=$((cursor-1))
               elif (( menu_back_focused )); then
                 frame=selection
               elif (( selected < 2 )); then
                 menu_back_focused=1; frame=selection
               else
                 parent=${resolved:-$base}
                 [[ -n $parent ]] || parent=/
                 [[ $parent == / ]] || parent=${parent%/*}
                 [[ -n $parent ]] || parent=/
                 input=$parent cursor=${#input} dirty=1
               fi;;
          esac
        fi
      else
        if [[ $kind == 'New directory name' ]]; then
          kind='Start directory' input=$path_input cursor=${#path_input} menu_has_back=1
          selected=0 first=0 dirty=1 layout_dirty=1 menu_back_focused=0
          continue
        fi
        return 130
      fi
      continue
    fi
    case $key in
      $'\n'|$'\r')
        (( menu_back_focused )) && return 130
        if (( valid || creatable || (selected>1 && ${#choices[@]}>=selected-1) )); then
          if [[ $kind == 'Session name' ]]; then printf '%s' "$input"
          elif [[ $kind == 'New directory name' ]]; then
            if mkdir -- "$create_target" 2>/dev/null; then
              ez_codex_resolve_expanded_dir "$create_target"
            else dirty=1; continue; fi
          elif (( selected==0 && valid )); then printf '%s' "$resolved"
          elif (( selected==1 )); then
            if (( valid )); then
              create_parent=$resolved; path_input=$input; input=''
            elif (( creatable )); then
              create_parent=${create_target%/*}; path_input=$input; input=${create_target##*/}
            else continue; fi
            kind='New directory name' cursor=${#input} menu_has_back=0
            selected=0 first=0 dirty=1 layout_dirty=1 menu_back_focused=0
            continue
          elif (( selected>1 )); then ez_codex_resolve_dir "${choices[selected-2]}"
          else continue; fi
          return
        fi;;
      $'\t') if [[ $kind == 'Start directory' ]] && (( ${#choices[@]} )); then menu_back_focused=0; (( selected<2 )) && selected=2; input=$(ez_codex_resolve_dir "${choices[selected-2]}") || continue; cursor=${#input} dirty=1; fi;;
      $'\177'|$'\b') if (( cursor > 0 )); then menu_back_focused=0; input=${input:0:cursor-1}${input:cursor}; cursor=$((cursor-1)); dirty=1; fi;;
      $'\025') menu_back_focused=0 input='' cursor=0 dirty=1;;
      $'\004') return 130;;
      *) [[ $key != [[:cntrl:]] ]] && { menu_back_focused=0; input=${input:0:cursor}$key${input:cursor}; cursor=$((cursor+1)); dirty=1; };;
    esac
  done
)

ez_codex_new() {
  local name dir id
  name=$(ez_codex_field 'Session name' '') || return 0
  dir=$(ez_codex_field 'Start directory' "${ez_codex_start_dir:-$PWD}") || return 0
  ez_codex_valid_name "$name" || { printf 'Session name is already in use.\n' >&2; return 0; }
  local -a environment pane_command
  ez_menu_launch_environment
  ez_menu_pane_command 1 codex --dangerously-bypass-approvals-and-sandbox
  # Keep failures visible before exec, without a waiting parent process: the
  # switcher's manual move needs the pane PID to be the Codex process itself.
  # Multiple command arguments bypass tmux's default shell and preserve quoting.
  id=$(tmux new-session -d -P -F '#{session_id}' -s "codex-$name" -c "$dir" "${environment[@]}" "${pane_command[@]}") || return
  ez_codex_new_id=$id
  ez_codex_attach "$id"
}
ez_codex_actions() {
  local id=$1 name=$2 created=$3 account=${4:-unknown} selected replacement
  selected=$(ez_menu_choose 0 '' --screen-title "$name [$account]" --live-duration 0 "$created" ' (active for ' always -- Resume Rename Terminate) || return 0
  case $selected in
    0) ez_codex_attach "$id";;
    1) replacement=$(ez_codex_field 'Session name' "$name" "$id") || return 0
       ez_codex_valid_name "$replacement" "$id" && tmux rename-session -t "$id" "codex-$replacement";;
    2) tmux kill-session -t "$id";;
  esac
}
ez_menu_codex_sessions() {
  local selected=0 index selected_id=''
  local -a ez_codex_ids ez_codex_names ez_codex_created ez_codex_rank ez_codex_accounts uptime_args session_labels
  while :; do
    ez_codex_scan
    if [[ -n $selected_id ]]; then
      selected=0
      for ((index=0;index<${#ez_codex_ids[@]};index++)); do
        if [[ ${ez_codex_ids[index]} == "$selected_id" ]]; then
          selected=$((index+1))
          break
        fi
      done
    fi
    (( selected > ${#ez_codex_ids[@]} )) && selected=0
    ez_codex_session_accounts
    uptime_args=() session_labels=()
    for ((index=0;index<${#ez_codex_ids[@]};index++)); do
      uptime_args+=(--live-duration "$((index+1))" "${ez_codex_created[index]}" ' (' selected)
      uptime_args+=(--accent-suffix "$((index+1))" " [${ez_codex_accounts[index]}]")
      session_labels+=("${ez_codex_names[index]} [${ez_codex_accounts[index]}]")
    done
    selected=$(ez_menu_choose "$selected" '' --screen-title 'Codex: Sessions' "${uptime_args[@]}" -- '[new session]' "${session_labels[@]}") || return 0
    if (( selected==0 )); then
      ez_codex_new_id=''
      ez_codex_new
      selected_id=$ez_codex_new_id
    else
      index=$((selected-1))
      selected_id=${ez_codex_ids[index]}
      ez_codex_actions "${ez_codex_ids[index]}" "${ez_codex_names[index]}" "${ez_codex_created[index]}" "${ez_codex_accounts[index]}"
    fi
  done
}
