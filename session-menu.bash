#!/usr/bin/env bash
# Codex frontend. Backend JSON stays intact; only presentation fields are derived.

ez_codex_valid_name() {
  local candidate=$1 except=${2-}
  [[ $candidate != switcher ]] && ez_codex_name_chars "$candidate" || return 1
  # Renames are local display aliases. Creation also needs a free tmux name.
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
  ez_codex_rank_inventory
}

ez_codex_recency_file() {
  printf '%s/satellite-cli/session-recency.tsv' "${XDG_STATE_HOME:-$HOME/.local/state}"
}
ez_codex_touch() {
  local key=$1 file temp saved rank now
  file=$(ez_codex_recency_file)
  (umask 077; mkdir -p -- "${file%/*}") || return 1
  temp=$(umask 077; mktemp -- "${file%/*}/.recency.XXXXXXXX") || return 1
  if [[ -f $file ]]; then
    while IFS=$'\t' read -r saved rank; do [[ $saved == "$key" ]] || printf '%s\t%s\n' "$saved" "$rank" >> "$temp"; done < "$file"
  fi
  printf -v now '%(%s)T' -1
  printf '%s\t%s\n' "$key" "$now" >> "$temp"
  mv -f -- "$temp" "$file"
}

ez_codex_rank_inventory() {
  local pane created rank attached metadata='' recency='' file key
  while IFS='|' read -r pane created rank attached; do
    [[ $pane =~ ^%[0-9]+$ && $created =~ ^[0-9]+$ ]] || continue
    [[ $rank =~ ^[0-9]+$ ]] || rank=$created
    [[ $attached =~ ^[0-9]+$ ]] && (( attached > rank )) && rank=$attached
    metadata+="\"$pane\":{\"created\":$created,\"rank\":$rank},"
  done < <(tmux list-panes -a -F '#{pane_id}|#{session_created}|#{@ez_codex_last_used}|#{session_last_attached}' 2>/dev/null)
  file=$(ez_codex_recency_file)
  if [[ -f $file ]]; then
    while IFS=$'\t' read -r key rank; do
      [[ $key =~ ^(pane:%[0-9]+|[0-9a-fA-F-]{36})$ && $rank =~ ^[0-9]+$ ]] || continue
      recency+="\"$key\":$rank,"
    done < "$file"
  fi
  ez_codex_snapshot=$(jq -c --argjson panes "{${metadata%,}}" --argjson recent "{${recency%,}}" '
    .sessions |= (map(.menu_created=$panes[.pane // ""].created |
      .menu_rank=([$panes[.pane // ""].rank // 0, $recent[.thread_id // .id] // 0, .updated_at // 0] | max)) |
      sort_by([(if .lifecycle == "inactive" then 2 elif .activity == "idle" then 1 else 0 end), -.menu_rank]))
  ' <<< "$ez_codex_snapshot")
}

ez_menu_has_codex() {
  ez_codex_inventory || return 1
  [[ $(jq '.sessions | length' <<< "$ez_codex_snapshot") != 0 ]]
}

ez_codex_display_name() {
  local row=$1 thread name
  thread=$(jq -r '.thread_id // ""' <<< "$row")
  name=$(jq -r '.name | gsub("[\u0000-\u001f\u007f]"; " ")' <<< "$row")
  [[ $name != codex-* ]] || name=${name#codex-}
  if ez_codex_alias_read "${thread:-$(jq -r '.id' <<< "$row")}"; then name=$REPLY; fi
  printf '%s' "$name"
}

ez_menu_codex_label() {
  local row name
  row=$(jq -c '.sessions[0]' <<< "$ez_codex_snapshot")
  name=$(ez_codex_display_name "$row")
  if [[ $(jq -r '.lifecycle' <<< "$row") == live ]]; then printf 'Codex: Resume (%s)' "$name"
  else printf 'Codex: Start (%s)' "$name"; fi
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
  ez_codex_inventory || { ez_codex_error; return 1; }
  ez_switcher_find "$ez_codex_snapshot" "$1" "${2-}" || { ez_codex_error 'This session is no longer in the inventory.'; return 1; }
}

# All destinations remain selectable for moves except the actual current home.
# Capacity/auth warnings belong in switcher's durable confirmation workflow.
ez_codex_choose_account() {
  local mode=$1 current=${2-} selected row name suffix disabled='' index=0
  local enabled=0
  local -a names=() labels=() notes=()
  ez_switcher_accounts || { ez_codex_error; return 1; }
  while IFS= read -r row; do
    name=$(jq -r '.name' <<< "$row")
    suffix=''
    if [[ $mode == move && $name == "$current" ]]; then
      disabled+="$index " notes+=(--disabled-note "$index" '(current home)')
    elif [[ $mode == launch && $(jq -r '.enabled' <<< "$row") == false ]]; then
      disabled+="$index " notes+=(--disabled-note "$index" '(unavailable)')
    else
      enabled=$((enabled+1))
      suffix=$(jq -r 'if .auth_required then " (login required)" elif .enabled == false then " (disabled)" elif .eligible != true then " (check capacity)" else "" end' <<< "$row")
    fi
    names+=("$name") labels+=("$name$suffix") index=$((index+1))
  done < <(jq -c '.accounts[]' <<< "$ez_switcher_json")
  (( ${#names[@]} )) || { ez_codex_error 'No enrolled accounts are available. Open Codex: Account Switcher.'; return 1; }
  (( enabled )) || { ez_codex_error 'No available destination accounts. Check account status in Codex: Account Switcher.'; return 1; }
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
  ez_codex_attach "$id"
}

ez_codex_new() {
  local name dir account
  ez_switcher_available || { ez_codex_error 'Codex Switcher and jq are required.'; return 1; }
  name=$(ez_codex_field 'Session name' '') || return 0
  dir=$(ez_codex_field 'Start directory' "${ez_codex_start_dir:-$PWD}") || return 0
  account=$(ez_codex_choose_account launch) || return 0
  ez_codex_valid_name "$name" || { ez_codex_error 'Session name is already in use.'; return 1; }
  ez_codex_launch "$name" "$dir" "$account"
}

ez_codex_start() {
  local row=$1 name
  name=$(ez_codex_display_name "$row")
  if ! ez_codex_valid_name "$name"; then name=$(ez_codex_field 'Session name' "$name") || return 0; fi
  # The backend owns exact-history selection and original-home resumption,
  # including external homes. A display nickname is never a launch destination.
  ez_switcher_request 'select(.schema_version == 1 and (.session.pane | type == "string") and (.session.tmux_session | type == "string"))' open --session "$(jq -r '.id' <<< "$row")" --name "codex-$name" || { ez_codex_error; return 1; }
  ez_codex_attach "=$(jq -r '.session.tmux_session' <<< "$ez_switcher_json")" "$(jq -r '.session.pane' <<< "$ez_switcher_json")"
}

ez_menu_codex() {
  ez_codex_inventory || { ez_codex_error; return 1; }
  local row
  row=$(jq -c '.sessions[0] // empty' <<< "$ez_codex_snapshot")
  [[ -n $row ]] || return 0
  ez_codex_open "$row"
}

ez_codex_open() {
  local row=$1
  ez_codex_touch "$(jq -r 'if (.thread_id // "") != "" then .thread_id else .id end' <<< "$row")" || :
  if [[ $(jq -r '.lifecycle' <<< "$row") == live ]]; then
    ez_codex_attach "=$(jq -r '.tmux_session' <<< "$row")" "$(jq -r '.pane' <<< "$row")"
  else ez_codex_start "$row"; fi
}

ez_codex_session_details() {
  jq -r '"Conversation: " + (.thread_id // "Unidentified"), "Project: " + .cwd,
    "Account Home: " + .account, "Identity: " + (.display_account // "Unknown"),
    "Activity: " + .activity, (.detail // ""), (.warnings // [])[]' <<< "$1"
}

ez_codex_account_move() {
  local row=$1 account
  account=$(ez_codex_choose_account move "$(jq -r '.account' <<< "$row")") || return 0
  local -a ez_switcher_source_args
  ez_switcher_source "$row" || return 1
  ez_switcher_queue move "${ez_switcher_source_args[@]}" --to "$account" || { ez_codex_error; return 1; }
  ez_codex_job "$(jq -r '.id' <<< "$ez_switcher_json")"
}

ez_codex_relocate() {
  local row=$1 source mode parent name target review
  local -a ez_switcher_source_args args
  source=$(jq -r '.cwd' <<< "$row")
  mode=$(ez_menu_choose 0 '' --screen-title 'Relocate Project' -- 'Change Root Directory' 'Move Root Folder') || return 0
  if (( mode == 0 )); then target=$(ez_codex_field 'Start directory' "$source") || return 0
  else
    parent=${source%/*}; [[ -n $parent ]] || parent=/
    parent=$(ez_codex_field 'Start directory' "$parent") || return 0
    name=$(ez_codex_field 'Move directory name' "${source##*/}" "$parent") || return 0
    target=$(ez_codex_new_dir_name_target "$parent" "$name") || return 1
  fi
  ez_switcher_source "$row" || return 1
  args=(relocate "${ez_switcher_source_args[@]}" --to "$target")
  (( mode == 0 )) || args+=(--move-files)
  ez_switcher_request 'select(.schema_version == 1 and (.detail | type == "string") and (.relocation | type == "object") and (.other_sessions | type == "array"))' "${args[@]}" --dry-run || { ez_codex_error; return 1; }
  review=$(jq -r '.detail, "From: " + .relocation.from, "To: " + .relocation.to,
    "Move Files: " + (.relocation.move_files | tostring),
    "Cross Filesystem: " + (.relocation.cross_filesystem | tostring),
    "Other Sessions: ", (.other_sessions[] | if type == "string" then . else tojson end)' <<< "$ez_switcher_json")
  ez_codex_document 'Review Project Relocation' "$review" 'Queue Relocation' 'Go Back' || return 0
  ez_switcher_queue "${args[@]}" || { ez_codex_error; return 1; }
  ez_codex_job "$(jq -r '.id' <<< "$ez_switcher_json")"
}

ez_codex_job_details() {
  jq -r '"Job: " + .id, "Kind: " + (.kind // "account"), "Phase: " + .phase, .detail,
    (if .relocation then .relocation | "From: " + .from, "To: " + .to,
      (.backend_note // empty), (if .stage then "Stage: " + .stage else empty end),
      (if .retained_source then "Retained Source: " + .retained_source else empty end),
      (if .retained_destination then "Retained Destination: " + .retained_destination else empty end)
     else empty end)' <<< "$1"
}

ez_codex_phase_label() {
  local word label=''
  local -a words
  read -ra words <<< "${1//_/ }"
  for word in "${words[@]}"; do label+="${word^} "; done
  printf '%s' "${label% }"
}

ez_codex_job_fetch() {
  ez_switcher_jobs || return
  ez_codex_job_json=$(jq -ce --arg id "$1" '.[] | select(.id == $id)' <<< "$ez_switcher_json") || {
    ez_switcher_error='Job is no longer available in Codex Switcher.'; return 1;
  }
}

ez_codex_job_refresh() {
  local phase kind
  original_labels=('Refresh') menu_keys=(refresh) disabled_indices='' busy_rows=()
  specified_gray_suffix=() specified_accent_suffix=() duration_created=()
  if ! ez_codex_job_fetch "$job_id"; then description=$ez_switcher_error; return 0; fi
  phase=$(jq -r '.phase' <<< "$ez_codex_job_json")
  kind=$(jq -r '.kind // "account"' <<< "$ez_codex_job_json")
  screen_title="Codex Job: $(ez_codex_phase_label "$phase")"
  description=$(jq -r '.detail | gsub("[\u0000-\u001f\u007f]"; " ")' <<< "$ez_codex_job_json")
  # Full explanations and retained-path details are available without clipping.
  original_labels=('View Full Details') menu_keys=(details)
  if [[ $phase == awaiting_* ]]; then
    original_labels+=('Review Confirmation') menu_keys+=(respond)
  elif ! ez_switcher_terminal_phase "$phase"; then busy_rows=(0); fi
  if ! ez_switcher_terminal_phase "$phase"; then
    original_labels+=('Open Session') menu_keys+=(open)
    original_labels+=('Cancel Job') menu_keys+=(cancel)
    original_labels+=('Recover Interrupted Job') menu_keys+=(recover)
  elif [[ $phase == failed ]]; then
    original_labels+=('Recover Original Session') menu_keys+=(recover)
  elif [[ $phase == complete || $phase == recovered ]]; then
    if [[ $kind == terminate ]]; then original_labels+=('Start Saved Conversation')
    else original_labels+=('Open Session'); fi
    menu_keys+=(open)
  fi
  original_labels+=('Refresh') menu_keys+=(refresh)
}

ez_codex_job() {
  local job_id=$1 selected phase sequence answer details thread
  local ez_codex_job_json=''
  while :; do
    selected=$(ez_menu_choose 0 '' --screen-title 'Codex Job' --refresh ez_codex_job_refresh -- Refresh) || return 0
    [[ $selected != refresh ]] || continue
    ez_codex_job_fetch "$job_id" || { ez_codex_error; continue; }
    case $selected in
      details) ez_codex_document 'Job Details' "$(ez_codex_job_details "$ez_codex_job_json")" || : ;;
      respond)
        phase=$(jq -r '.phase' <<< "$ez_codex_job_json")
        [[ $phase == awaiting_* ]] || continue
        sequence=$(jq -r '.confirmation_seq // empty' <<< "$ez_codex_job_json")
        details=$(ez_codex_job_details "$ez_codex_job_json")
        details+=$'\n'"Confirmation: $sequence. This response applies only to this numbered prompt."
        if ez_codex_document "Confirm: $(ez_codex_phase_label "${phase#awaiting_}")" "$details" 'Yes, Approve This Request' 'No, Decline This Request'; then answer=yes
        else
          [[ $? == 1 ]] || continue
          answer=no
        fi
        ez_switcher_respond "$job_id" "$answer" "$sequence" || ez_codex_error
        ;;
      cancel)
        ez_codex_document 'Cancel Job?' 'Request cancellation before the restart boundary. An already accepted pause message cannot be retracted. Closing this screen alone leaves the job running.' 'Request Cancellation' 'Keep Running' || continue
        ez_switcher_request 'select(.cancellation_requested == true)' cancel-move "$job_id" || ez_codex_error
        ;;
      recover)
        ez_codex_document 'Recover Original Session?' "$(ez_codex_job_details "$ez_codex_job_json")" 'Request Recovery' 'Go Back' || continue
        ez_switcher_queue recover "$job_id" || ez_codex_error
        ;;
      open)
        thread=$(jq -r '.source.thread_id // ""' <<< "$ez_codex_job_json")
        ez_codex_get_current "pane:$(jq -r '.source.pane // ""' <<< "$ez_codex_job_json")" "$thread" || continue
        ez_codex_open "$ez_switcher_row"
        ;;
    esac
  done
}

ez_codex_jobs() {
  local selected row
  local -a ids labels
  while :; do
    ez_switcher_jobs || { ez_codex_error; return 0; }
    ids=() labels=()
    while IFS= read -r row; do
      ids+=("$(jq -r '.id' <<< "$row")")
      labels+=("$(jq -r '((.kind // "account") + ": " + (.source.tmux_session // .source.thread_id // .id) + " (" + .phase + ")") | gsub("[\u0000-\u001f\u007f]"; " ")' <<< "$row")")
    done < <(jq -c 'sort_by(.created_at // 0) | reverse | .[]' <<< "$ez_switcher_json")
    (( ${#ids[@]} )) || { ez_codex_document 'Codex Jobs' 'There are no durable jobs.' || :; return 0; }
    selected=$(ez_menu_choose 0 '' --screen-title 'Codex Jobs' -- "${labels[@]}") || return 0
    ez_codex_job "${ids[selected]}"
  done
}

ez_codex_actions_refresh() {
  local name account lifecycle activity move created
  original_labels=('Refresh') menu_keys=(refresh) disabled_indices='' busy_rows=()
  duration_created=() specified_accent_suffix=() specified_gray_suffix=()
  if ! ez_codex_inventory; then description=$ez_switcher_error; return 0; fi
  if ! ez_switcher_find "$ez_codex_snapshot" "$session_key" "$session_thread"; then
    description='This session is no longer in the inventory.'; return 0
  fi
  name=$(ez_codex_display_name "$ez_switcher_row")
  account=$(jq -r '(.display_account // .account) | gsub("[\u0000-\u001f\u007f]"; " ")' <<< "$ez_switcher_row")
  lifecycle=$(jq -r '.lifecycle' <<< "$ez_switcher_row")
  activity=$(jq -r '.activity' <<< "$ez_switcher_row")
  [[ $activity != idle ]] || name+='*'
  screen_title="$name [$account]"
  description=$(jq -r '(.detail // "") | gsub("[\u0000-\u001f\u007f]"; " ")' <<< "$ez_switcher_row")
  if [[ $lifecycle == live ]]; then original_labels=(Resume); menu_keys=(open)
  else original_labels=(Start); menu_keys=(open); screen_title+=' (inactive)'; fi
  [[ $activity != busy ]] || busy_rows=(0)
  if [[ $lifecycle == live ]]; then
    created=$(tmux display-message -p -t "$(jq -r '.pane' <<< "$ez_switcher_row")" '#{session_created}' 2>/dev/null) || created=''
    if [[ $created =~ ^[0-9]+$ ]]; then duration_created[0]=$created duration_prefix[0]=' (active for ' duration_mode[0]=always; fi
  fi
  original_labels+=(Rename 'Move To Account' 'Relocate Project') menu_keys+=(rename move relocate)
  if [[ $lifecycle == live ]]; then original_labels+=(Restart); menu_keys+=(restart); fi
  if [[ $lifecycle == live ]] && (( ${session_pause_available:-0} )); then original_labels+=('Pause Session'); menu_keys+=(pause-session); fi
  if [[ $lifecycle == live ]] && (( ${session_termination_available:-0} )); then original_labels+=(Terminate); menu_keys+=(terminate); fi
  move=$(jq -r '.move_id // ""' <<< "$ez_switcher_row")
  if [[ -n $move ]]; then original_labels+=('View Pending Job'); menu_keys+=(job); fi
  original_labels+=('Session Details' 'All Jobs'); menu_keys+=(details jobs)
}

ez_codex_actions() {
  local session_key=$1 session_thread=${2-} selected row name replacement alias_key
  local session_pause_available=0 session_termination_available=0
  if ez_switcher_accounts; then
    [[ $(jq -r '.capabilities.session_pause // false' <<< "$ez_switcher_json") != true ]] || session_pause_available=1
    [[ $(jq -r '.capabilities.session_termination // false' <<< "$ez_switcher_json") != true ]] || session_termination_available=1
  fi
  while :; do
    selected=$(ez_menu_choose 0 '' --screen-title 'Codex Session' --refresh ez_codex_actions_refresh -- Refresh) || return 0
    [[ $selected != refresh ]] || continue
    [[ $selected != jobs ]] || { ez_codex_jobs; continue; }
    ez_codex_get_current "$session_key" "$session_thread" || return 0
    row=$ez_switcher_row
    session_key=$(jq -r '.id' <<< "$row") session_thread=$(jq -r '.thread_id // ""' <<< "$row")
    case $selected in
      open) ez_codex_open "$row" ;;
      rename)
        name=$(ez_codex_display_name "$row")
        alias_key=${session_thread:-$session_key}
        replacement=$(ez_codex_field 'Session name' "$name" "$alias_key") || continue
        ez_codex_alias_save "$alias_key" "$replacement" || ez_codex_error 'Could not save the display name.' ;;
      move) ez_codex_account_move "$row" ;;
      relocate) ez_codex_relocate "$row" ;;
      restart|pause-session|terminate)
        [[ $(jq -r '.lifecycle' <<< "$row") == live ]] || continue
        if [[ $selected == terminate ]]; then
          ez_codex_document 'Terminate Session?' 'Codex Switcher will stop this conversation safely and retain its history for Start. Other sessions stay running. Pause and background-task requests require their own numbered approvals.' 'Queue Termination' 'Go Back' || continue
        fi
        ez_switcher_queue "$selected" --pane "$(jq -r '.pane' <<< "$row")" || { ez_codex_error; continue; }
        ez_codex_job "$(jq -r '.id' <<< "$ez_switcher_json")" ;;
      job) ez_codex_job "$(jq -r '.move_id' <<< "$row")" ;;
      details) ez_codex_document 'Session Details' "$(ez_codex_session_details "$row")" || : ;;
    esac
  done
}

# Presentation derives only labels, order and uptime. tmux metadata supplements
# backend-discovered panes; it never adds rows or determines Codex activity.
ez_codex_sessions_refresh() {
  local key thread name account activity lifecycle created offset index width=0 account_width=0 pad
  local -a fields=() names=() accounts=() activities=() lifecycles=() createds=()
  local inventory_ok=0 watch_status=0 disconnected=''
  if [[ -t 0 && -t 2 && ${TERM:-dumb} != dumb ]]; then
    if (( ! watch_started )); then
      watch_started=1 menu_cleanup=ez_switcher_watch_close
      if ez_codex_inventory; then inventory_ok=1; fi
      ez_switcher_watch_start || watch_failed=1
    elif (( ! watch_failed )); then
      if ez_switcher_watch_read; then ez_codex_snapshot=$ez_switcher_json; ez_codex_rank_inventory; inventory_ok=1
      else
        watch_status=$?
        (( watch_status != 1 )) || return 0
        watch_failed=1
        if [[ -n $watch_snapshot ]]; then ez_codex_snapshot=$watch_snapshot; ez_codex_rank_inventory; fi
      fi
    fi
  elif ez_codex_inventory; then inventory_ok=1; fi
  if (( ! inventory_ok )); then
    disconnected="Discovery Disconnected: $ez_switcher_error"
    if [[ -n ${ez_codex_snapshot:-} ]]; then
      ez_codex_snapshot=$(jq -c '.sessions |= map(if .lifecycle == "live" then .activity="unknown" else . end)' <<< "$ez_codex_snapshot")
    else
      description=$disconnected
      original_labels=('Retry Discovery' '[new session]' 'Codex Jobs') menu_keys=(refresh new jobs)
      return 0
    fi
  fi
  description=$disconnected
  mapfile -d '' -t fields < <(jq -jr '.sessions[] | [.id, (.thread_id // ""), (.name | gsub("[\u0000-\u001f\u007f]"; " ")), ((.display_account // .account) | gsub("[\u0000-\u001f\u007f]"; " ")), .activity, .lifecycle, (.menu_created // "" | tostring)] | .[] | . + "\u0000"' <<< "$ez_codex_snapshot")
  original_labels=('[new session]') menu_keys=(new) menu_threads=('')
  specified_accent_suffix=() specified_gray_suffix=() duration_created=() busy_rows=() disabled_indices=''
  for ((offset=0;offset<${#fields[@]};offset+=7)); do
    key=${fields[offset]} thread=${fields[offset+1]} name=${fields[offset+2]} account=${fields[offset+3]}
    activity=${fields[offset+4]} lifecycle=${fields[offset+5]} created=${fields[offset+6]}
    [[ $name != codex-* ]] || name=${name#codex-}
    if ez_codex_alias_read "${thread:-$key}"; then name=$REPLY; fi
    [[ $activity != idle ]] || name+='*'
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
  original_labels+=('Codex Jobs') menu_keys+=(jobs) menu_threads+=('')
  if [[ -n $disconnected ]]; then original_labels+=('Retry Discovery'); menu_keys+=(refresh); menu_threads+=(''); fi
  if [[ -n ${session_selection:-} ]]; then
    selected=0
    for index in "${!menu_keys[@]}"; do
      if [[ ${menu_keys[index]} == "$session_selection" || ( -n ${session_selection_thread:-} && ${menu_threads[index]} == "$session_selection_thread" ) ]]; then selected=$index; break; fi
    done
    session_selection=''
  fi
}

ez_menu_codex_sessions() {
  local choice session_selection='' session_selection_thread=''
  while :; do
    choice=$(ez_menu_choose 0 '' --screen-title 'Codex: Sessions' --refresh ez_codex_sessions_refresh -- 'Retry Discovery') || return 0
    case $choice in
      new) ez_codex_new ;;
      refresh) continue ;;
      jobs) ez_codex_jobs ;;
      *)
        ez_codex_get_current "$choice" || continue
        session_selection=$choice session_selection_thread=$(jq -r '.thread_id // ""' <<< "$ez_switcher_row")
        local move
        move=$(jq -r '.move_id // ""' <<< "$ez_switcher_row")
        if [[ -n $move ]]; then ez_codex_job "$move"
        else ez_codex_actions "$choice" "$session_selection_thread"; fi
        ;;
    esac
  done
}
