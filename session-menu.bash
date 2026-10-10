#!/usr/bin/env bash
# Codex frontend. Backend JSON stays intact; only presentation fields are derived.

ez_codex_valid_name() {
  local candidate=$1 except=${2-}
  [[ $candidate != switcher ]] && ez_codex_name_chars "$candidate" || return 1
  # New sessions need a free tmux name.
  [[ -n $except ]] || ! tmux has-session -t "=codex-$candidate" 2>/dev/null
}

ez_codex_clean_text() {
  jq -r 'gsub("[\u0000-\u0008\u000b-\u001f\u007f]"; " ")' <<< "$1"
}

# Wrap full explanations into pages. Confirmation buttons appear only on the
# last page, so truncating a small terminal cannot hide consent information.
ez_codex_document() {
  local title=$1 text=$2 approve=${3:-Close} decline=${4-} page=0 choice size rows cols width per_page line
  local -a lines=() buttons=()
  size=$(stty size <&2 2>/dev/null) || size='24 80'
  read -r rows cols <<< "$size"
  (( rows > 0 )) || rows=24
  (( cols > 0 )) || cols=80
  width=$((cols-6)); (( width > 0 )) || width=1
  per_page=$((rows-13)); (( per_page > 0 )) || per_page=1
  text=$(ez_codex_clean_text "$(jq -Rn --arg text "$text" '$text')")
  while IFS= read -r line; do
    while (( ${#line} > width )); do lines+=("${line:0:width}"); line=${line:width}; done
    lines+=("$line")
  done <<< "$text"
  while :; do
    printf -v text '%s\n' "${lines[@]:page*per_page:per_page}"
    buttons=()
    if (( (page+1)*per_page < ${#lines[@]} )); then buttons=('Next Page')
    else buttons=("$approve"); [[ -z $decline ]] || buttons+=("$decline"); fi
    (( page == 0 )) || buttons+=('Previous Page')
    choice=$(ez_menu_choose 0 '' --screen-title "$title" --description "$text" -- "${buttons[@]}") || return 130
    if [[ ${buttons[choice]} == 'Next Page' ]]; then page=$((page+1))
    elif [[ ${buttons[choice]} == 'Previous Page' ]]; then page=$((page-1))
    elif (( choice == 0 )); then return 0
    else return 1; fi
  done
}

ez_codex_error() {
  ez_codex_document 'Codex: Attention' "${1:-${ez_switcher_error:-Operation failed.}}" || :
}

ez_codex_inventory() {
  ez_switcher_inventory || return
  ez_codex_snapshot=$ez_switcher_json
  ez_codex_rank_inventory || return
  ez_codex_snapshot_at=$SECONDS
}

# Switcher's last_accessed is the last open/attach time, in milliseconds.
# Preserve that precision within activity groups; tmux supplies only uptime.
ez_codex_rank_inventory() {
  local pane created metadata=''
  while IFS='|' read -r pane created; do
    [[ $pane =~ ^%[0-9]+$ && $created =~ ^[0-9]+$ ]] || continue
    metadata+="\"$pane\":$created,"
  done < <(tmux list-panes -a -F '#{pane_id}|#{session_created}' 2>/dev/null)
  ez_codex_snapshot=$(jq -c --argjson panes "{${metadata%,}}" '
    .sessions |= (map(.menu_created=$panes[.pane // ""]) |
      sort_by([(if .lifecycle == "inactive" then 2 elif .activity == "idle" then 1 else 0 end),
        -(.last_accessed // 0)]))
  ' <<< "$ez_codex_snapshot")
}

ez_menu_has_codex() {
  if [[ ${ez_codex_menu_active:-0} != 1 ]]; then
    ez_codex_inventory || return 1
  fi
  [[ -n ${ez_codex_snapshot:-} ]] || return 1
  [[ $(jq '.sessions | length' <<< "$ez_codex_snapshot") != 0 ]]
}

# One complete validated snapshot travels back to the calling menu. This avoids
# a second discovery scan after Back without persisting session data on disk.
ez_codex_menu_state() {
  printf '\n%s\n%s\n%s\n.' "${ez_codex_snapshot_at:--100}" "${ez_codex_snapshot:-}" "${ez_switcher_error:-}"
}

ez_codex_choose() {
  local result status state at snapshot
  if result=$(ez_menu_choose "$1" "$2" --return-state ez_codex_menu_state "${@:3}"); then status=0; else status=$?; fi
  ez_menu_choice=${result%%$'\n'*}
  if [[ $result == *$'\n'* ]]; then
    result=${result%$'\n.'}
    state=${result#*$'\n'} at=${state%%$'\n'*}
    state=${state#*$'\n'} snapshot=${state%%$'\n'*}
    if [[ $at =~ ^-?[0-9]+$ ]]; then
      ez_codex_snapshot_at=$at ez_codex_snapshot=$snapshot ez_switcher_error=${state#*$'\n'}
    fi
  fi
  return "$status"
}

# Home and Sessions consume the same inventory protocol and exchange their last
# complete snapshot. A cold chooser waits for the first complete watch result.
ez_codex_poll_inventory() {
  local status=0 pending continuation
  if [[ ! -t 0 || ! -t 2 || ${TERM:-dumb} == dumb ]]; then
    if ez_codex_inventory; then return 0; else return 2; fi
  fi
  if (( ! watch_started )); then
    watch_started=1 menu_cleanup=ez_switcher_watch_close
    if ! ez_switcher_watch_start; then
      watch_failed=1 ez_switcher_error='Could not start session discovery.'
      return 2
    fi
    if [[ -n ${ez_codex_snapshot:-} && ${ez_codex_snapshot_at:--100} != -100 ]]; then
      [[ -z ${ez_switcher_error:-} ]] || return 2
      return 0
    fi
    while :; do
      if ez_switcher_watch_read 0.05; then status=0; break; else status=$?; fi
      (( status == 1 )) || break
      # Escape remains Back while waiting, without exposing a partial screen.
      # Preserve queued arrows/Enter for the complete menu's normal key parser.
      if IFS= read -rsn1 -t 0.001 pending; then
        if [[ $pending == $'\e' ]]; then
          IFS= read -rsn1 -t 0.08 continuation || return 130
          pending+=$continuation
        elif [[ $pending == $'\004' ]]; then return 130; fi
        (( ${#menu_pending_input} >= 64 )) || menu_pending_input+=${pending:-$'\n'}
      fi
    done
  elif (( watch_failed )); then return 1
  elif ez_switcher_watch_read; then :
  else
    status=$?
    (( status == 1 )) && return 1
  fi
  if (( status == 2 )); then
    watch_failed=1
    # A stream can deliver its last valid snapshot and EOF in the same read.
    if [[ -n $watch_snapshot ]]; then
      ez_codex_snapshot=$watch_snapshot
      ez_codex_rank_inventory || return 2
      ez_codex_snapshot_at=$SECONDS
    fi
    return 2
  fi
  ez_codex_snapshot=$ez_switcher_json
  ez_codex_rank_inventory || return 2
  ez_codex_snapshot_at=$SECONDS ez_switcher_error=''
}

ez_codex_display_name() {
  jq -r '.name | sub("^codex-"; "") | gsub("[\u0000-\u001f\u007f]"; " ")' <<< "$1"
}

ez_menu_codex_label() {
  jq -r '.sessions[0] | (if .lifecycle == "live" then "Codex: Resume" else "Codex: Start" end) +
    " (" + (.name | sub("^codex-"; "") | gsub("[\u0000-\u001f\u007f]"; " ")) + ")"' <<< "$ez_codex_snapshot"
}

ez_codex_attach() {
  local target=$1 pane=${2-} result now
  tmux has-session -t "$target" 2>/dev/null || { ez_codex_error 'Session is no longer available.'; return 1; }
  printf -v now '%(%s)T' -1
  # set-option parses a window target, unlike has-session/attach-session.
  # The colon makes an exact session-name target resolve in that parser too.
  tmux set-option -t "$target:" @ez_codex_last_used "$now" || return
  if [[ -n $pane ]]; then
    tmux select-window -t "$pane" && tmux select-pane -t "$pane" || return
  fi
  if [[ -n ${TMUX:-} ]]; then tmux switch-client -t "$target"; return; fi
  (( ${ez_menu_shared_screen:-0} )) && printf '\033[?1004l\033[0m\033[?25h\033[?1049l' >&2
  tmux attach-session -t "$target"
  result=$?
  (( ${ez_menu_shared_screen:-0} )) && printf '\033[?1049h\033[?25l' >&2
  return "$result"
}

ez_codex_get_current() {
  local key=$1 thread=${2-}
  [[ -n $thread || $key != thread:* ]] || thread=${key#thread:}
  ez_codex_inventory || { ez_codex_error; return 1; }
  ez_switcher_find "$ez_codex_snapshot" "$key" "$thread" || { ez_codex_error 'This session is no longer in the inventory.'; return 1; }
}

# Account capacity is advisory; switcher owns launch authorization.
ez_codex_choose_account() {
  local selected name suffix disabled='' index=0 offset
  local enabled=0
  local -a names=() labels=() notes=() fields=()
  ez_switcher_accounts || { ez_codex_error; return 1; }
  mapfile -d '' -t fields < <(jq -jr '.accounts[] | [.name, (.enabled != false | tostring),
    (if .auth_required then " (login required)" elif .eligible != true then " (check capacity)" else "" end)] | .[] | .+"\u0000"' <<< "$ez_switcher_json")
  for ((offset=0;offset<${#fields[@]};offset+=3)); do
    name=${fields[offset]} suffix=''
    if [[ ${fields[offset+1]} == false ]]; then
      disabled+="$index " notes+=(--disabled-note "$index" '(unavailable)')
    else
      enabled=$((enabled+1))
      suffix=${fields[offset+2]}
    fi
    names+=("$name") labels+=("$name$suffix") index=$((index+1))
  done
  (( ${#names[@]} )) || { ez_codex_error 'No enrolled accounts are available. Open Session Manager.'; return 1; }
  (( enabled )) || { ez_codex_error 'No enabled accounts. Check account status in Session Manager.'; return 1; }
  selected=$(ez_menu_choose 0 '' --screen-title 'Choose Account' --disabled "$disabled" "${notes[@]}" -- "${labels[@]}") || return 130
  printf '%s' "${names[selected]}"
}

ez_codex_launch() {
  local name=$1 dir=$2 account=$3 thread=${4-} id
  local -a environment pane_command command=(codex-switcher run --account "$account")
  if [[ -n $thread ]]; then
    [[ $thread =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]] || return 1
    command+=(--thread "$thread")
  else command+=(-- --dangerously-bypass-approvals-and-sandbox); fi
  ez_menu_launch_environment
  ez_menu_pane_command 1 "${command[@]}"
  id=$(tmux new-session -d -P -F '#{session_id}' -s "codex-$name" -c "$dir" "${environment[@]}" "${pane_command[@]}") || return
  ez_codex_new_id=$id
  ez_codex_snapshot_at=-100
  ez_codex_attach "$id"
}

ez_codex_new() {
  local name dir account
  ez_switcher_available || { ez_codex_error 'Codex Switcher and jq are required.'; return 1; }
  name=$(ez_codex_field 'Session name' '') || return 0
  dir=$(ez_codex_field 'Start directory' "${ez_codex_start_dir:-$PWD}") || return 0
  account=$(ez_codex_choose_account) || return 0
  ez_codex_valid_name "$name" || { ez_codex_error 'Session name is already in use.'; return 1; }
  ez_codex_launch "$name" "$dir" "$account"
}

ez_menu_codex() {
  # Open the row shown on the home screen; open resolves its current state.
  if [[ -z ${ez_codex_snapshot:-} ]]; then
    ez_codex_inventory || { ez_codex_error; return 1; }
  fi
  local row
  row=$(jq -c '.sessions[0] // empty' <<< "$ez_codex_snapshot")
  [[ -n $row ]] || return 0
  ez_codex_open "$row"
}

ez_codex_open() {
  ez_codex_open_id "$(jq -r '.id' <<< "$1")"
}

ez_codex_open_id() {
  # Open resolves live/saved transitions, records recency, and preserves the
  # original account home. The display name is never an operational target.
  ez_switcher_request 'select(.schema_version == 1 and
    (.session.pane | type == "string" and test("^%[0-9]+$")) and
    (.session.id == null or (.session.id | type == "string" and length > 0)) and
    (.session.thread_id == null or (.session.thread_id | type == "string")) and
    (.session.tmux_session | type == "string" and length > 0))' \
    open --session "$1" || { ez_codex_error; return 1; }
  local -a opened
  mapfile -d '' -t opened < <(jq -jr '.session | [(.id // ("pane:"+.pane)), (.thread_id // ""), .tmux_session, .pane] | .[] | .+"\u0000"' <<< "$ez_switcher_json")
  ez_codex_opened_id=${opened[0]} ez_codex_opened_thread=${opened[1]}
  ez_codex_snapshot_at=-100
  ez_codex_attach "=${opened[2]}" "${opened[3]}"
}

# Presentation derives only labels, order and uptime. tmux metadata supplements
# backend-discovered panes; it never adds rows or determines Codex activity.
ez_codex_sessions_refresh() {
  local key thread name account activity lifecycle created offset index width=0 account_width=0 pad
  local -a fields=() names=() accounts=() activities=() lifecycles=() createds=()
  local status disconnected=''
  if ez_codex_poll_inventory; then :
  else
    status=$?
    (( status != 1 )) || return 1
    (( status != 130 )) || return 130
    disconnected="Discovery Disconnected: $ez_switcher_error"
    if [[ -n ${ez_codex_snapshot:-} ]]; then
      ez_codex_snapshot=$(jq -c '.sessions |= map(if .lifecycle == "live" then .activity="unknown" else . end)' <<< "$ez_codex_snapshot")
    else
      description=$disconnected
      original_labels=('Retry Discovery' '[new session]' '' 'Session Manager') menu_keys=(refresh new separator manager)
      menu_threads=('' '' '' '') menu_spacers=([2]=1) disabled_indices='2'
      ez_codex_restore_selection
      return 0
    fi
  fi
  description=$disconnected
  mapfile -d '' -t fields < <(jq -jr '.sessions[] | [.id, (.thread_id // ""), (.name | sub("^codex-"; "") | gsub("[\u0000-\u001f\u007f]"; " ")), ((.display_account // .account) | gsub("[\u0000-\u001f\u007f]"; " ")), .activity, .lifecycle, (.menu_created // "" | tostring)] | .[] | . + "\u0000"' <<< "$ez_codex_snapshot")
  original_labels=('[new session]') menu_keys=(new) menu_threads=('')
  specified_accent_suffix=() specified_gray_suffix=() duration_created=() busy_rows=() menu_spacers=() disabled_indices=''
  for ((offset=0;offset<${#fields[@]};offset+=7)); do
    key=${fields[offset]} thread=${fields[offset+1]} name=${fields[offset+2]} account=${fields[offset+3]}
    activity=${fields[offset+4]} lifecycle=${fields[offset+5]} created=${fields[offset+6]}
    names+=("$name") accounts+=("$account") activities+=("$activity") lifecycles+=("$lifecycle") createds+=("$created")
    menu_keys+=("$key") menu_threads+=("$thread")
    (( ${#name} <= width )) || width=${#name}
    (( ${#account} <= account_width )) || account_width=${#account}
  done
  for ((index=0;index<${#names[@]};index++)); do
    printf -v pad '%*s' "$((width-${#names[index]}+account_width-${#accounts[index]}))" ''
    original_labels+=("${names[index]}$pad [${accounts[index]}]")
    specified_accent_suffix[index+1]="$pad [${accounts[index]}]"
    if [[ ${lifecycles[index]} == inactive ]]; then specified_gray_suffix[index+1]=' (inactive)'
    else
      case ${activities[index]} in busy) busy_rows+=("$((index+1))");; unknown) specified_gray_suffix[index+1]=' (unknown)';; esac
      [[ -z $disconnected ]] || specified_gray_suffix[index+1]=' (unknown; disconnected)'
      if [[ -n ${createds[index]} ]]; then
        duration_created[index+1]=${createds[index]} duration_prefix[index+1]=' (' duration_mode[index+1]=selected
      fi
    fi
  done
  if [[ -n $disconnected ]]; then original_labels+=('Retry Discovery'); menu_keys+=(refresh); menu_threads+=(''); fi
  index=${#original_labels[@]}
  menu_spacers[index]=1 disabled_indices="$index"
  original_labels+=('' 'Session Manager') menu_keys+=(separator manager) menu_threads+=('' '')
  ez_codex_restore_selection
}

ez_codex_restore_selection() {
  local index
  if [[ -n ${session_selection:-} ]]; then
    for index in "${!menu_keys[@]}"; do
      if [[ ${menu_keys[index]} == "$session_selection" || ( -n ${session_selection_thread:-} && ${menu_threads[index]} == "$session_selection_thread" ) ]]; then
        selected=$index session_selection=''
        return 0
      fi
    done
    selected=0 session_selection=''
  fi
  return 0
}

ez_menu_codex_sessions() {
  local choice session_selection='' session_selection_thread=''
  while :; do
    ez_codex_choose 0 '' --screen-title 'Codex: Sessions' --refresh ez_codex_sessions_refresh -- 'Retry Discovery' || return 0
    choice=$ez_menu_choice
    case $choice in
      new) session_selection=new session_selection_thread=''; ez_codex_new ;;
      refresh) continue ;;
      manager) session_selection=manager session_selection_thread=''; ez_menu_codex_monitor; ez_codex_snapshot_at=-100 ;;
      *)
        session_selection=$choice session_selection_thread=''
        if ez_codex_open_id "$choice"; then
          session_selection=$ez_codex_opened_id session_selection_thread=$ez_codex_opened_thread
        fi
        ;;
    esac
  done
}
