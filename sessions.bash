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
    done < <(jq -r '.[] | select(.inactive == false) | [.tmux_session, (.display_account // .account // "unknown")] | @tsv' <<< "$instances" 2>/dev/null)
  fi
  for ((index=0; index<${#ez_codex_names[@]}; index++)); do
    session=${ez_codex_names[index]}
    [[ $session == codex ]] || session=codex-$session
    ez_codex_accounts[index]=${by_session[$session]:-unknown}
  done
}

ez_codex_alias_file() {
  printf '%s/satellite-cli/session-names.tsv' "${XDG_STATE_HOME:-$HOME/.local/state}"
}
ez_codex_alias_read() {
  local wanted=$1 key alias file
  REPLY=''
  file=$(ez_codex_alias_file)
  [[ -f $file ]] || return 1
  while IFS=$'\t' read -r key alias; do
    if [[ $key == "$wanted" ]]; then REPLY=$alias; return 0; fi
  done < "$file"
  return 1
}
ez_codex_alias_save() {
  local wanted=$1 alias=$2 file dir temp key old
  file=$(ez_codex_alias_file); dir=${file%/*}
  (umask 077; mkdir -p -- "$dir") || return 1
  temp=$(umask 077; mktemp -- "$dir/.session-names.XXXXXXXX") || return 1
  if [[ -f $file ]]; then
    while IFS=$'\t' read -r key old; do
      [[ $key == "$wanted" ]] || printf '%s\t%s\n' "$key" "$old" >> "$temp"
    done < "$file"
  fi
  printf '%s\t%s\n' "$wanted" "$alias" >> "$temp"
  mv -f -- "$temp" "$file"
}
ez_codex_alias_delete() {
  local wanted=$1 file dir temp key old
  file=$(ez_codex_alias_file)
  [[ -f $file ]] || return 0
  dir=${file%/*}
  temp=$(umask 077; mktemp -- "$dir/.session-names.XXXXXXXX") || return 1
  while IFS=$'\t' read -r key old; do
    [[ $key == "$wanted" ]] || printf '%s\t%s\n' "$key" "$old" >> "$temp"
  done < "$file"
  mv -f -- "$temp" "$file"
}
ez_codex_inactive_scan() {
  local instances item thread cwd account home binary rollout reason name index fields i j temp
  local -a ez_inactive_rank=()
  ez_inactive_ids=() ez_inactive_names=() ez_inactive_accounts=() ez_inactive_cwds=()
  ez_inactive_homes=() ez_inactive_binaries=() ez_inactive_rollouts=() ez_inactive_reasons=() ez_inactive_json=()
  command -v codex-switcher >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
  instances=$(codex-switcher instances 2>/dev/null) || return 0
  jq -e 'type == "array"' <<< "$instances" >/dev/null 2>&1 || return 0
  while IFS= read -r item; do
    mapfile -d '' -t fields < <(jq -jr \
      '[.thread_id,.cwd,(.display_account // .account // "unknown"),.home,.binary,.rollout,(.block_reason // "")] | .[] | tostring + "\u0000"' <<< "$item")
    (( ${#fields[@]} == 7 )) || continue
    thread=${fields[0]} cwd=${fields[1]} account=${fields[2]} home=${fields[3]}
    binary=${fields[4]} rollout=${fields[5]} reason=${fields[6]}
    [[ $thread =~ ^[0-9a-fA-F-]{36}$ && $home == /* && -d $home ]] || continue
    name=${cwd##*/}; [[ -n $name ]] || name=/
    if ez_codex_alias_read "$thread"; then name=$REPLY
    else name="$name (${thread:0:8})"; fi
    index=${#ez_inactive_ids[@]}
    ez_inactive_ids[index]=$thread ez_inactive_names[index]=$name ez_inactive_accounts[index]=$account
    ez_inactive_cwds[index]=$cwd ez_inactive_homes[index]=$home ez_inactive_binaries[index]=$binary
    ez_inactive_rollouts[index]=$rollout ez_inactive_reasons[index]=$reason ez_inactive_json[index]=$item
    ez_inactive_rank[index]=$(stat -c %Y -- "$rollout" 2>/dev/null) || ez_inactive_rank[index]=0
  done < <(jq -c '.[] | select(.inactive == true)' <<< "$instances")
  # Saved conversations have no tmux attach timestamp; rollout mtime is their
  # most recent activity, and keeps the same newest-first ordering as tmux.
  for ((i=0;i<${#ez_inactive_ids[@]};i++)); do
    for ((j=i+1;j<${#ez_inactive_ids[@]};j++)); do
      if (( ez_inactive_rank[j] > ez_inactive_rank[i] )); then
        for name in ez_inactive_ids ez_inactive_names ez_inactive_accounts ez_inactive_cwds \
          ez_inactive_homes ez_inactive_binaries ez_inactive_rollouts ez_inactive_reasons \
          ez_inactive_json ez_inactive_rank; do
          local -n array=$name
          temp=${array[i]} array[i]=${array[j]} array[j]=$temp
          unset -n array
        done
      fi
    done
  done
}

ez_menu_has_codex() {
  ez_codex_scan
  (( ${#ez_codex_ids[@]} > 0 )) && return 0
  ez_codex_inactive_scan
  (( ${#ez_inactive_ids[@]} > 0 ))
}
ez_menu_codex_label() {
  ez_codex_scan
  if (( ${#ez_codex_ids[@]} )); then
    printf 'Codex: Resume (%s)' "${ez_codex_names[0]}"
  else
    ez_codex_inactive_scan
    printf 'Codex: Start'
    (( ${#ez_inactive_ids[@]} )) && printf ' (%s)' "${ez_inactive_names[0]}"
  fi
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
  if (( ${#ez_codex_ids[@]} )); then ez_codex_attach "${ez_codex_ids[0]}"
  else
    ez_codex_inactive_scan
    (( ${#ez_inactive_ids[@]} )) && ez_codex_resume_inactive "${ez_inactive_ids[0]}"
  fi
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
  local candidate=$1 except=${2-} i key alias file
  [[ $candidate != switcher ]] || return 1
  ez_codex_name_chars "$candidate" || return 1
  ez_codex_scan
  for ((i=0;i<${#ez_codex_ids[@]};i++)); do
    [[ ${ez_codex_names[i]} == "$candidate" && ${ez_codex_ids[i]} != "$except" ]] && return 1
  done
  file=$(ez_codex_alias_file)
  if [[ -f $file ]]; then
    while IFS=$'\t' read -r key alias; do
      [[ $alias == "$candidate" && $key != "$except" ]] && return 1
    done < "$file"
  fi
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
  [[ $kind == 'Move directory name' ]] && hint='Type the destination folder name'
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
  [[ $kind == 'Move directory name' ]] && create_parent=$except
  [[ $kind == 'Start directory' ]] && menu_has_back=1
  if [[ ! -t 0 || ! -t 2 || ${TERM:-dumb} == dumb ]]; then
    while :; do
      printf '%s > ' "$kind" >&2
      IFS= read -r input || return 130
      if [[ $kind == 'Session name' ]]; then
        ez_codex_valid_name "$input" "$except" && { printf '%s' "$input"; return; }
      elif [[ $kind == 'Move directory name' ]]; then
        if ez_codex_new_dir_name_target "$create_parent" "$input" >/dev/null; then
          printf '%s' "$input"
          return
        fi
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
      elif [[ $kind == 'New directory name' || $kind == 'Move directory name' ]]; then
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
      elif [[ $kind == 'New directory name' || $kind == 'Move directory name' ]]; then
        if [[ $kind == 'Move directory name' ]]; then labels=('Continue')
        else labels=('Create directory'); fi
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
      if [[ $kind == 'Session name' || $kind == 'New directory name' || $kind == 'Move directory name' ]]; then
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
               elif [[ $kind == 'Session name' || $kind == 'New directory name' || $kind == 'Move directory name' ]]; then
                 (( cursor < ${#input} )) && cursor=$((cursor+1))
               elif (( ${#choices[@]} )); then
                 (( selected<2 )) && selected=2
                 input=$(ez_codex_resolve_dir "${choices[selected-2]}") || continue
                 cursor=${#input} dirty=1
               fi;;
            D) if [[ $kind == 'Session name' || $kind == 'New directory name' || $kind == 'Move directory name' ]]; then
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
          elif [[ $kind == 'Move directory name' ]]; then printf '%s' "$input"
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

# Codex Switcher identifies the exact conversation and account home. A detached
# tmux client is not sufficient evidence of idleness: also require a completed
# rollout and no process owned by the Codex pane.
ez_codex_move_info() {
  local id=$1 session instances item pane_state panes events
  command -v codex-switcher >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 &&
    command -v pgrep >/dev/null 2>&1 || return 1
  session=$(tmux display-message -p -t "$id" '#{session_name}') || return 1
  instances=$(codex-switcher instances 2>/dev/null) || return 1
  item=$(jq -ec --arg session "$session" \
    '[.[] | select(.inactive == false and .tmux_session == $session and .block_reason == null)] | if length == 1 then .[0] else empty end' \
    <<< "$instances" 2>/dev/null) || return 1
  mapfile -d '' -t ez_move_fields < <(jq -jr \
    '[.pane,.pid,.start_time,.cwd,.thread_id,.rollout,.home,.binary] | .[] | tostring + "\u0000"' <<< "$item")
  (( ${#ez_move_fields[@]} == 8 )) || return 1
  [[ ${ez_move_fields[1]} =~ ^[0-9]+$ && ${ez_move_fields[2]} =~ ^[0-9]+$ &&
     ${ez_move_fields[4]} =~ ^[0-9a-fA-F-]{36}$ &&
     ${ez_move_fields[3]} == /* && ${ez_move_fields[5]} == /* &&
     ${ez_move_fields[6]} == /* && -f ${ez_move_fields[5]} &&
     -d ${ez_move_fields[6]} ]] || return 1
  mapfile -d '' -t ez_move_options < <(jq -jr '.resume_options[] | . + "\u0000"' <<< "$item")
  pane_state=$(tmux display-message -p -t "${ez_move_fields[0]}" \
    '#{session_id}|#{session_attached}|#{pane_dead}|#{pane_pid}|#{pane_current_command}') || return 1
  [[ $pane_state == "$id|0|0|${ez_move_fields[1]}|codex" ]] || return 1
  panes=$(tmux list-panes -s -t "$id" -F '#{pane_id}') || return 1
  [[ $panes == "${ez_move_fields[0]}" ]] || return 1
  [[ -r /proc/${ez_move_fields[1]}/stat ]] || return 1
  local proc_stat proc_fields
  proc_stat=$(< "/proc/${ez_move_fields[1]}/stat")
  read -ra proc_fields <<< "${proc_stat#*) }"
  [[ ${proc_fields[19]-} == "${ez_move_fields[2]}" ]] || return 1
  ez_codex_idle_children "${ez_move_fields[1]}" || return 1
  ez_codex_rollout_complete "${ez_move_fields[5]}" || return 1
  [[ -d ${ez_move_fields[3]} ]] || return 1
  return 0
}

ez_codex_session_idle() {
  local state pane process pid command
  state=$(tmux display-message -p -t "$1" '#{session_attached}|#{pane_dead}' 2>/dev/null) || return 1
  [[ $state == '0|1' ]] && return 0
  [[ $state == '0|0' ]] || return 1
  ez_codex_move_info "$1" && return 0
  # Codex Switcher cannot always match a fresh CLI pane to its rollout. A
  # detached pane at Codex's visible input prompt is still idle for display;
  # Move keeps requiring the stronger verified-thread check above.
  pane=$(tmux list-panes -s -t "$1" -F '#{pane_id}' 2>/dev/null) || return 1
  [[ $pane == %* && $pane != *$'\n'* ]] || return 1
  process=$(tmux display-message -p -t "$pane" '#{pane_pid}|#{pane_current_command}' 2>/dev/null) || return 1
  pid=${process%%|*} command=${process#*|}
  [[ $pid =~ ^[0-9]+$ && $command == codex ]] || return 1
  ez_codex_idle_children "$pid" || return 1
  tmux capture-pane -p -t "$pane" 2>/dev/null | rg -q '^› '
}

ez_codex_rollout_complete() {
  local events
  # Older rollouts may contain an invalid record from an interrupted write.
  # A later task_complete is decisive; an invalid final record is not.
  events=$(jq -Rr '
    try fromjson catch {type:"invalid"} |
    if .type == "invalid" then "invalid"
    elif .type == "event_msg" then
      .payload.type | select(. == "task_started" or . == "task_complete" or . == "turn_aborted")
    else empty end' "$1" 2>/dev/null) || return 1
  [[ ${events##*$'\n'} == task_complete ]]
}

# A resumed conversation should use its last recorded permissions. The
# switcher supplies other launch flags, but saved conversations have none.
ez_codex_build_resume_options() {
  local rollout=$1 recorded approval='' sandbox='' option value bypass=0
  shift
  ez_resume_options=()
  recorded=$(jq -Rr '
    fromjson? | select(.type == "turn_context") |
    [.payload.approval_policy, .payload.sandbox_policy.type] |
    select((.[0] == "never" or .[0] == "on-request") and
           (.[1] == "read-only" or .[1] == "workspace-write" or .[1] == "danger-full-access")) |
    @tsv' "$rollout" 2>/dev/null | tail -n 1) || return 1
  while (( $# )); do
    option=$1
    case $option in
      --dangerously-bypass-approvals-and-sandbox|--full-auto|--approve-for-me)
        bypass=1; shift ;;
      -a|--ask-for-approval)
        (( $# >= 2 )) || return 1
        approval=$2; shift 2 ;;
      -s|--sandbox)
        (( $# >= 2 )) || return 1
        sandbox=$2; shift 2 ;;
      -c|--config)
        (( $# >= 2 )) || return 1
        value=$2
        if [[ $value == approval_policy=* ]]; then approval=${value#*=}; approval=${approval//\"/}
        elif [[ $value == sandbox_mode=* ]]; then sandbox=${value#*=}; sandbox=${sandbox//\"/}
        else ez_resume_options+=("$option" "$value"); fi
        shift 2 ;;
      *) ez_resume_options+=("$option"); shift ;;
    esac
  done
  if [[ -n $recorded ]]; then
    IFS=$'\t' read -r approval sandbox <<< "$recorded"
  elif (( bypass )); then
    approval=never sandbox=danger-full-access
  fi
  [[ $approval == never || $approval == on-request ]] || approval=never
  [[ $sandbox == read-only || $sandbox == workspace-write || $sandbox == danger-full-access ]] || sandbox=danger-full-access
  ez_resume_options+=(--ask-for-approval "$approval" --sandbox "$sandbox")
}

ez_codex_idle_children() {
  local parent=$1 child command
  while IFS= read -r child; do
    [[ -r /proc/$child/cmdline ]] || return 1
    IFS= read -r -d '' command < "/proc/$child/cmdline" || return 1
    [[ ${command##*/} == codex-code-mode-host ]] || return 1
    ! pgrep -P "$child" >/dev/null 2>&1 || return 1
  done < <(pgrep -P "$parent" || :)
  return 0
}

ez_codex_process_start() {
  local line parts
  [[ -r /proc/$1/stat ]] || return 1
  line=$(< "/proc/$1/stat")
  read -ra parts <<< "${line#*) }"
  REPLY=${parts[19]-}
  [[ $REPLY =~ ^[0-9]+$ ]]
}

ez_codex_stop_idle_pane() {
  local pane=$1 pid=$2 rollout=$3 child start attempt dead command
  local -a helpers=() starts=()
  ez_codex_idle_children "$pid" && ez_codex_rollout_complete "$rollout" || return 1
  while IFS= read -r child; do
    ez_codex_process_start "$child" || return 1
    helpers+=("$child") starts+=("$REPLY")
  done < <(pgrep -P "$pid" || :)
  kill -TERM "$pid" || return 1
  dead=0
  for ((attempt=0;attempt<100;attempt++)); do
    [[ $(tmux display-message -p -t "$pane" '#{pane_dead}') == 1 ]] && { dead=1; break; }
    sleep 0.1
  done
  (( dead )) || return 1
  for ((attempt=0;attempt<${#helpers[@]};attempt++)); do
    child=${helpers[attempt]} start=${starts[attempt]}
    if ez_codex_process_start "$child" && [[ $REPLY == "$start" ]]; then
      IFS= read -r -d '' command < "/proc/$child/cmdline" || return 1
      [[ ${command##*/} == codex-code-mode-host ]] || return 1
      kill -TERM "$child" || return 1
    fi
  done
  for ((attempt=0;attempt<50;attempt++)); do
    local remaining=0 line parts
    for ((child=0;child<${#helpers[@]};child++)); do
      [[ -r /proc/${helpers[child]}/stat ]] || continue
      line=$(< "/proc/${helpers[child]}/stat")
      read -ra parts <<< "${line#*) }"
      [[ ${parts[19]-} != "${starts[child]}" || ${parts[0]-} == Z ]] || remaining=1
    done
    (( remaining )) || break
    sleep 0.1
  done
  (( remaining == 0 )) || return 1
  ez_codex_rollout_complete "$rollout"
}

ez_codex_movable_root() {
  local source=$1 parent
  [[ -d $source && ! -L $source && $source != / && $source != "$HOME" ]] || return 1
  parent=${source%/*}; [[ -n $parent ]] || parent=/
  [[ -w $parent && -x $parent ]] || return 1
  [[ $(stat -c %d -- "$source") == "$(stat -c %d -- "$parent")" ]] || return 1
  [[ $(ez_codex_resolve_expanded_dir "$source") == "$source" ]]
}

ez_codex_move_bar() {
  local percent=$1 label=$2 filled empty
  (( percent < 0 )) && percent=0
  (( percent > 100 )) && percent=100
  printf -v filled '%*s' "$((percent/5))" ''
  printf -v empty '%*s' "$((20-percent/5))" ''
  printf '\r\033[2K  %-24s [%s%s] %3d%%' "$label" "${filled// /█}" "${empty// /░}" "$percent" >&2
}

ez_codex_move_respawn() {
  local pane=$1 dir=$2 home=$3 binary=$4 thread=$5
  shift 5
  local CODEX_HOME=$home
  local -a environment pane_command
  ez_menu_launch_environment
  ez_menu_pane_command 1 "$binary" resume "$thread" -C "$dir" "$@"
  tmux respawn-pane -t "$pane" -c "$dir" "${environment[@]}" "${pane_command[@]}"
}

ez_codex_restore_remain_on_exit() {
  local pane=$1 previous=$2
  if [[ -n $previous ]]; then
    tmux set-option -p -t "$pane" remain-on-exit "$previous"
  else
    tmux set-option -pu -t "$pane" remain-on-exit
  fi
}

ez_codex_move_execute() {
  local id=$1 source=$2 target=$3 physical=$4
  local pane=${ez_move_fields[0]} pid=${ez_move_fields[1]} start=${ez_move_fields[2]}
  local thread=${ez_move_fields[4]} rollout=${ez_move_fields[5]} home=${ez_move_fields[6]} binary=${ez_move_fields[7]}
  local -a options=("${ez_move_options[@]}")
  local parent=${target%/*} stage='' source_device target_device size available status=0 old_remain target_created=0
  [[ -n $parent ]] || parent=/
  ez_codex_build_resume_options "$rollout" "${options[@]}" || return 1
  options=("${ez_resume_options[@]}")
  [[ -d $parent && -w $parent && -x $parent ]] || return 1
  (( physical )) || [[ -d $target && -w $target && -x $target ]] || return 1
  if (( physical )); then
    [[ ! -e $target && ! -L $target && $target != "$source" && $parent != "$source" && $parent != "$source/"* ]] || return 1
    ez_codex_movable_root "$source" || return 1
    source_device=$(stat -c %d -- "$source") || return 1
    target_device=$(stat -c %d -- "$parent") || return 1
    if [[ $source_device != "$target_device" ]]; then
      command -v rsync >/dev/null 2>&1 || return 1
      size=$(du -sb -- "$source" | cut -f1) || return 1
      available=$(df -B1 --output=avail -- "$parent" | tail -n 1) || return 1
      [[ $size =~ ^[0-9]+$ && $available =~ ^[0-9]+$ ]] || return 1
      (( available > size + size/20 + 1048576 )) || { printf 'Not enough space at destination.\n' >&2; return 1; }
    fi
  fi
  # Recheck after the user has picked a path. Refuse a changed pane or turn.
  ez_codex_move_info "$id" || return 1
  [[ ${ez_move_fields[0]} == "$pane" && ${ez_move_fields[1]} == "$pid" &&
     ${ez_move_fields[2]} == "$start" && ${ez_move_fields[4]} == "$thread" &&
     ${ez_move_fields[3]} == "$source" && ${ez_move_fields[5]} == "$rollout" &&
     ${ez_move_fields[6]} == "$home" ]] || return 1
  old_remain=$(tmux show-options -p -v -t "$pane" remain-on-exit 2>/dev/null) || return 1
  tmux set-option -p -t "$pane" remain-on-exit on || return 1
  printf '\033[H\033[2J  Moving session to %s\n\n' "$target" >&2
  ez_codex_move_bar 0 'Preparing session'
  if ! ez_codex_stop_idle_pane "$pane" "$pid" "$rollout"; then
    if [[ $(tmux display-message -p -t "$pane" '#{pane_dead}') == 1 ]]; then
      ez_codex_move_respawn "$pane" "$source" "$home" "$binary" "$thread" "${options[@]}"
    fi
    ez_codex_restore_remain_on_exit "$pane" "$old_remain"
    printf '\nCodex changed or could not stop; the original session remains available.\n' >&2
    return 1
  fi
  if (( physical )); then
    if [[ $source_device == "$target_device" ]]; then
      ez_codex_move_bar 40 'Moving folder'
      if mv -T -- "$source" "$target"; then target_created=1; else status=1; fi
    else
      stage=$(mktemp -d -- "$parent/.satellite-move.XXXXXXXX") || status=1
      if (( ! status )); then
        if (set -o pipefail
          rsync -aHAX --numeric-ids --info=progress2 --no-inc-recursive -- "$source/" "$stage/" 2>&1 |
            tr '\r' '\n' | while IFS= read -r line; do
              if [[ $line =~ ([0-9]{1,3})% ]]; then ez_codex_move_bar "${BASH_REMATCH[1]}" 'Copying files'; fi
            done
        ); then :; else status=1; fi
        if (( ! status )) && mv -T -- "$stage" "$target"; then
          target_created=1 stage=''
        else status=1; fi
      fi
    fi
  fi
  if (( ! status )); then
    ez_codex_move_bar 95 'Resuming conversation'
    ez_codex_move_respawn "$pane" "$target" "$home" "$binary" "$thread" "${options[@]}" || status=1
    if (( ! status )); then
      sleep 0.5
      [[ $(tmux display-message -p -t "$pane" '#{pane_dead}') == 0 ]] || status=1
    fi
  fi
  if (( status )); then
    if (( target_created )) && [[ -e $target ]]; then
      if [[ $source_device == "$target_device" ]]; then mv -T -- "$target" "$source"
      else rm -rf -- "$target"; fi
    fi
    [[ -z $stage ]] || rm -rf -- "$stage"
    [[ $(tmux display-message -p -t "$pane" '#{pane_dead}') == 1 ]] &&
      ez_codex_move_respawn "$pane" "$source" "$home" "$binary" "$thread" "${options[@]}"
    ez_codex_restore_remain_on_exit "$pane" "$old_remain"
    printf '\nMove failed. The original directory and conversation were restored.\n' >&2
    return 1
  fi
  if (( physical )) && [[ $source_device != "$target_device" ]]; then
    rm -rf -- "$source" || { printf '\nSession moved, but the original folder could not be removed: %s\n' "$source" >&2; return 1; }
  fi
  ez_codex_restore_remain_on_exit "$pane" "$old_remain"
  ez_codex_move_bar 100 'Move complete'
  printf '\n' >&2
}

ez_codex_choose_move_target() {
  local source=$1 mode parent name
  ez_move_physical=0 ez_move_target=''
  if ez_codex_movable_root "$source"; then
    mode=$(ez_menu_choose 0 '' --screen-title 'Move Session' -- 'Redefine root directory' 'Move root folder') || return 130
  else
    mode=$(ez_menu_choose 0 '' --screen-title 'Move Session' --disabled '1' -- 'Redefine root directory' 'Move root folder') || return 130
  fi
  if (( mode == 0 )); then
    ez_move_target=$(ez_codex_field 'Start directory' "$source") || return 130
    [[ $ez_move_target != "$source" && -w $ez_move_target ]] || return 130
  else
    ez_move_physical=1
    parent=${source%/*}; [[ -n $parent ]] || parent=/
    parent=$(ez_codex_field 'Start directory' "$parent") || return 130
    name=$(ez_codex_field 'Move directory name' "${source##*/}" "$parent") || return 130
    ez_move_target=$(ez_codex_new_dir_name_target "$parent" "$name") || return 1
  fi
}
ez_codex_move() {
  local id=$1 source
  ez_codex_move_info "$id" || return 1
  source=$(ez_codex_resolve_expanded_dir "${ez_move_fields[3]}") || return 1
  ez_codex_choose_move_target "$source" || return 0
  ez_codex_move_execute "$id" "$source" "$ez_move_target" "$ez_move_physical"
}

ez_codex_inactive_info() {
  local thread=$1 index
  ez_codex_inactive_scan
  for ((index=0;index<${#ez_inactive_ids[@]};index++)); do
    if [[ ${ez_inactive_ids[index]} == "$thread" ]]; then
      ez_inactive_selected=$index
      return 0
    fi
  done
  return 1
}

ez_codex_resume_inactive() {
  local thread=$1 dir=${2-} attach=${3:-1} allow_relocated=${4:-0} index name id item binary home
  local CODEX_HOME
  local -a environment pane_command options
  ez_codex_inactive_info "$thread" || return 1
  index=$ez_inactive_selected
  [[ ( -z ${ez_inactive_reasons[index]} || $allow_relocated == 1 ) && -f ${ez_inactive_rollouts[index]} ]] || return 1
  ez_codex_rollout_complete "${ez_inactive_rollouts[index]}" || return 1
  [[ -n $dir ]] || dir=${ez_inactive_cwds[index]}
  [[ -d $dir && -w $dir && -x $dir ]] || return 1
  home=${ez_inactive_homes[index]} binary=${ez_inactive_binaries[index]}
  [[ -n $binary ]] || binary=codex
  item=${ez_inactive_json[index]}
  mapfile -d '' -t options < <(jq -jr '.resume_options[]? | . + "\u0000"' <<< "$item")
  ez_codex_build_resume_options "${ez_inactive_rollouts[index]}" "${options[@]}" || return 1
  options=("${ez_resume_options[@]}")
  if ez_codex_alias_read "$thread" && ez_codex_name_chars "$REPLY"; then name=$REPLY
  else name=$thread; fi
  if tmux has-session -t "=codex-$name" 2>/dev/null; then name=$thread; fi
  tmux has-session -t "=codex-$name" 2>/dev/null && return 1
  CODEX_HOME=$home
  ez_menu_launch_environment
  ez_menu_pane_command 1 "$binary" resume "$thread" -C "$dir" "${options[@]}"
  id=$(tmux new-session -d -P -F '#{session_id}' -s "codex-$name" -c "$dir" \
    "${environment[@]}" "${pane_command[@]}") || return 1
  ez_codex_new_id=$id
  sleep 0.5
  if [[ $(tmux display-message -p -t "$id" '#{pane_dead}') == 1 ]]; then
    (( attach )) && ez_codex_attach "$id"
    return 1
  fi
  (( attach )) && ez_codex_attach "$id"
  return 0
}

ez_codex_move_inactive_execute() {
  local thread=$1 source=$2 target=$3 physical=$4
  local parent=${target%/*} source_device='' target_device='' size available stage='' status=0 target_created=0
  local original_id='' original_rollout original_home
  [[ -n $parent ]] || parent=/
  [[ -d $parent && -w $parent && -x $parent ]] || return 1
  if (( physical )); then
    ez_codex_movable_root "$source" || return 1
    [[ ! -e $target && ! -L $target && $target != "$source" && $parent != "$source" && $parent != "$source/"* ]] || return 1
    source_device=$(stat -c %d -- "$source") || return 1
    target_device=$(stat -c %d -- "$parent") || return 1
    if [[ $source_device != "$target_device" ]]; then
      command -v rsync >/dev/null 2>&1 || return 1
      size=$(du -sb -- "$source" | cut -f1) || return 1
      available=$(df -B1 --output=avail -- "$parent" | tail -n 1) || return 1
      [[ $size =~ ^[0-9]+$ && $available =~ ^[0-9]+$ ]] || return 1
      (( available > size + size/20 + 1048576 )) || { printf 'Not enough space at destination.\n' >&2; return 1; }
    fi
  else
    [[ -d $target && -w $target && -x $target ]] || return 1
  fi
  ez_codex_inactive_info "$thread" || return 1
  [[ -z ${ez_inactive_reasons[ez_inactive_selected]} &&
     ${ez_inactive_cwds[ez_inactive_selected]} == "$source" ]] || return 1
  original_rollout=${ez_inactive_rollouts[ez_inactive_selected]}
  original_home=${ez_inactive_homes[ez_inactive_selected]}
  ez_codex_rollout_complete "$original_rollout" || return 1
  printf '\033[H\033[2J  Moving saved conversation to %s\n\n' "$target" >&2
  ez_codex_move_bar 0 'Preparing session'
  if (( physical )); then
    if [[ $source_device == "$target_device" ]]; then
      ez_codex_move_bar 40 'Moving folder'
      if mv -T -- "$source" "$target"; then target_created=1; else status=1; fi
    else
      stage=$(mktemp -d -- "$parent/.satellite-move.XXXXXXXX") || status=1
      if (( ! status )); then
        if (set -o pipefail
          rsync -aHAX --numeric-ids --info=progress2 --no-inc-recursive -- "$source/" "$stage/" 2>&1 |
            tr '\r' '\n' | while IFS= read -r line; do
              if [[ $line =~ ([0-9]{1,3})% ]]; then ez_codex_move_bar "${BASH_REMATCH[1]}" 'Copying files'; fi
            done
        ); then :; else status=1; fi
        if (( ! status )) && mv -T -- "$stage" "$target"; then
          target_created=1 stage=''
        else status=1; fi
      fi
    fi
  fi
  if (( ! status )); then
    ez_codex_move_bar 95 'Starting conversation'
    ez_codex_new_id=''
    ez_codex_resume_inactive "$thread" "$target" 0 1 || status=1
    original_id=${ez_codex_new_id:-}
  fi
  if (( status )); then
    [[ -z $original_id ]] || tmux kill-session -t "$original_id" 2>/dev/null || :
    if (( target_created )) && [[ -e $target ]]; then
      if [[ $source_device == "$target_device" ]]; then mv -T -- "$target" "$source"
      else rm -rf -- "$target"; fi
    fi
    [[ -z $stage ]] || rm -rf -- "$stage"
    printf '\nMove failed. The saved conversation and original directory remain available.\n' >&2
    return 1
  fi
  if (( physical )) && [[ $source_device != "$target_device" ]]; then
    rm -rf -- "$source" || { printf '\nConversation started, but the original folder could not be removed: %s\n' "$source" >&2; return 1; }
  fi
  ez_codex_move_bar 100 'Move complete'
  printf '\n' >&2
  ez_codex_attach "$original_id"
}

ez_codex_move_inactive() {
  local thread=$1 source
  ez_codex_inactive_info "$thread" || return 1
  source=${ez_inactive_cwds[ez_inactive_selected]}
  [[ $source == /* && -z ${ez_inactive_reasons[ez_inactive_selected]} ]] || return 1
  ez_codex_choose_move_target "$source" || return 0
  ez_codex_move_inactive_execute "$thread" "$source" "$ez_move_target" "$ez_move_physical"
}

ez_codex_inactive_actions() {
  local thread=$1 name=$2 account=$3 selected replacement
  local -a disabled=()
  ez_codex_inactive_info "$thread" || return 0
  if [[ -n ${ez_inactive_reasons[ez_inactive_selected]} ]] ||
     ! ez_codex_rollout_complete "${ez_inactive_rollouts[ez_inactive_selected]}"; then
    disabled=(--disabled '0 2' --disabled-note 0 '(unavailable)' --disabled-note 2 '(unavailable)')
  fi
  [[ ${ez_inactive_reasons[ez_inactive_selected]} == busy ]] && disabled+=(--disabled '3' --disabled-note 3 '(busy)')
  selected=$(ez_menu_choose 0 '' --screen-title "$name [$account] (inactive)" "${disabled[@]}" -- Start Rename Move Delete) || return 0
  case $selected in
    0) ez_codex_new_id=''; ez_codex_resume_inactive "$thread";;
    1) replacement=$(ez_codex_field 'Session name' "$name" "$thread") || return 0
       ez_codex_valid_name "$replacement" "$thread" && ez_codex_alias_save "$thread" "$replacement";;
    2) ez_codex_move_inactive "$thread";;
    3) ez_codex_delete_inactive "$thread" "$name";;
  esac
}

ez_codex_delete_inactive() {
  local thread=$1 name=$2 choice home
  choice=$(ez_menu_choose 0 '' --screen-title "Delete $name?" -- 'Delete conversation') || return 0
  (( choice == 0 )) || return 0
  ez_codex_inactive_info "$thread" || return 1
  [[ ${ez_inactive_reasons[ez_inactive_selected]} != busy ]] || return 1
  home=${ez_inactive_homes[ez_inactive_selected]}
  CODEX_HOME=$home codex delete --force "$thread" || return 1
  ez_codex_alias_delete "$thread"
}

ez_codex_terminate() {
  local id=$1 pane pid rollout source home binary thread old_remain instances
  local -a options=()
  ez_codex_move_info "$id" || return 1
  pane=${ez_move_fields[0]} pid=${ez_move_fields[1]} source=${ez_move_fields[3]}
  thread=${ez_move_fields[4]} rollout=${ez_move_fields[5]}
  home=${ez_move_fields[6]} binary=${ez_move_fields[7]}
  options=("${ez_move_options[@]}")
  ez_codex_build_resume_options "$rollout" "${options[@]}" || return 1
  options=("${ez_resume_options[@]}")
  old_remain=$(tmux show-options -p -v -t "$pane" remain-on-exit 2>/dev/null) || return 1
  tmux set-option -p -t "$pane" remain-on-exit on || return 1
  if ! ez_codex_stop_idle_pane "$pane" "$pid" "$rollout"; then
    if [[ $(tmux display-message -p -t "$pane" '#{pane_dead}') == 1 ]]; then
      ez_codex_move_respawn "$pane" "$source" "$home" "$binary" "$thread" "${options[@]}"
    fi
    ez_codex_restore_remain_on_exit "$pane" "$old_remain"
    return 1
  fi
  instances=$(codex-switcher instances 2>/dev/null) || instances=''
  if ! jq -e --arg thread "$thread" \
    'any(.[]; .inactive == true and .thread_id == $thread)' <<< "$instances" >/dev/null 2>&1; then
    ez_codex_move_respawn "$pane" "$source" "$home" "$binary" "$thread" "${options[@]}"
    ez_codex_restore_remain_on_exit "$pane" "$old_remain"
    printf 'Conversation did not become inactive; the tmux session was restored.\n' >&2
    return 1
  fi
  tmux kill-session -t "$id"
}

ez_codex_actions() {
  local id=$1 name=$2 created=$3 account=${4:-unknown} selected replacement title
  local -a move_args=()
  title="$name [$account]"
  ez_codex_session_idle "$id" && title="$name* [$account]"
  ez_codex_move_info "$id" || move_args=(--disabled '2 3' --disabled-note 2 '(active or unavailable)' --disabled-note 3 '(active or unavailable)')
  selected=$(ez_menu_choose 0 '' --screen-title "$title" --live-duration 0 "$created" ' (active for ' always "${move_args[@]}" -- Resume Rename Move Terminate) || return 0
  case $selected in
    0) ez_codex_attach "$id";;
    1) replacement=$(ez_codex_field 'Session name' "$name" "$id") || return 0
       ez_codex_valid_name "$replacement" "$id" && tmux rename-session -t "$id" "codex-$replacement";;
    2) ez_codex_move "$id";;
    3) ez_codex_terminate "$id";;
  esac
}
ez_menu_codex_sessions() {
  local selected=0 index position live_count chosen selected_key='' thread name account_pad account_column=0
  local -a ez_codex_ids ez_codex_names ez_codex_created ez_codex_rank ez_codex_accounts uptime_args session_labels
  local -a ez_inactive_ids ez_inactive_names ez_inactive_accounts ez_inactive_cwds ez_inactive_homes
  local -a ez_inactive_binaries ez_inactive_rollouts ez_inactive_reasons ez_inactive_json
  local -a live_order=() live_idle=() running_order=() idle_order=()
  while :; do
    ez_codex_scan
    live_count=${#ez_codex_ids[@]}
    running_order=() idle_order=() live_idle=()
    for ((index=0;index<live_count;index++)); do
      if ez_codex_session_idle "${ez_codex_ids[index]}"; then
        live_idle[index]=1
        idle_order+=("$index")
      else
        live_idle[index]=0
        running_order+=("$index")
      fi
    done
    live_order=("${running_order[@]}" "${idle_order[@]}")
    ez_codex_inactive_scan
    if [[ -n $selected_key ]]; then
      selected=0
      if [[ $selected_key == t:* ]]; then
        for ((position=0;position<live_count;position++)); do
          index=${live_order[position]}
          if [[ ${ez_codex_ids[index]} == "${selected_key#t:}" ]]; then
            selected=$((position+1)); break
          fi
        done
      else
        for ((index=0;index<${#ez_inactive_ids[@]};index++)); do
          if [[ ${ez_inactive_ids[index]} == "${selected_key#i:}" ]]; then
            selected=$((live_count+index+1)); break
          fi
        done
      fi
    fi
    (( selected > live_count + ${#ez_inactive_ids[@]} )) && selected=0
    ez_codex_session_accounts
    account_column=0
    for ((position=0;position<live_count;position++)); do
      index=${live_order[position]}
      name=${ez_codex_names[index]}
      (( live_idle[index] )) && name+='*'
      (( ${#name} > account_column )) && account_column=${#name}
    done
    for name in "${ez_inactive_names[@]}"; do
      (( ${#name} > account_column )) && account_column=${#name}
    done
    uptime_args=() session_labels=()
    for ((position=0;position<live_count;position++)); do
      index=${live_order[position]}
      name=${ez_codex_names[index]}
      (( live_idle[index] )) && name+='*'
      printf -v account_pad '%*s' "$((account_column - ${#name}))" ''
      uptime_args+=(--live-duration "$((position+1))" "${ez_codex_created[index]}" ' (' selected)
      uptime_args+=(--accent-suffix "$((position+1))" "$account_pad [${ez_codex_accounts[index]}]")
      session_labels+=("$name$account_pad [${ez_codex_accounts[index]}]")
    done
    for ((index=0;index<${#ez_inactive_ids[@]};index++)); do
      name=${ez_inactive_names[index]}
      printf -v account_pad '%*s' "$((account_column - ${#name}))" ''
      uptime_args+=(--accent-suffix "$((live_count+index+1))" "$account_pad [${ez_inactive_accounts[index]}]")
      uptime_args+=(--gray-suffix "$((live_count+index+1))" ' (inactive)')
      session_labels+=("$name$account_pad [${ez_inactive_accounts[index]}]")
    done
    selected=$(ez_menu_choose "$selected" '' --screen-title 'Codex: Sessions' "${uptime_args[@]}" -- '[new session]' "${session_labels[@]}") || return 0
    if (( selected==0 )); then
      ez_codex_new_id=''
      ez_codex_new
      selected_key=t:$ez_codex_new_id
    elif (( selected <= live_count )); then
      index=${live_order[selected-1]}
      selected_key=t:${ez_codex_ids[index]}
      ez_codex_actions "${ez_codex_ids[index]}" "${ez_codex_names[index]}" "${ez_codex_created[index]}" "${ez_codex_accounts[index]}"
    else
      index=$((selected-live_count-1))
      thread=${ez_inactive_ids[index]}
      selected_key=i:$thread
      ez_codex_new_id=''
      ez_codex_inactive_actions "$thread" "${ez_inactive_names[index]}" "${ez_inactive_accounts[index]}"
      [[ -n $ez_codex_new_id ]] && selected_key=t:$ez_codex_new_id
    fi
  done
}
