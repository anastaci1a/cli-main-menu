#!/usr/bin/env bash
# JSON boundary to Codex Switcher. Never inspect account homes or conversation files.

ez_switcher_available() {
  command -v codex-switcher >/dev/null 2>&1 && command -v jq >/dev/null 2>&1
}

ez_switcher_request() {
  local filter=$1 output errors status
  shift
  ez_switcher_json='' ez_switcher_error=''
  ez_switcher_available || { ez_switcher_error='Codex Switcher and jq are required.'; return 1; }
  errors=$(mktemp) || return 1
  if output=$(codex-switcher "$@" 2>"$errors"); then status=0; else status=$?; fi
  ez_switcher_error=$(< "$errors")
  rm -f -- "$errors"
  if (( status )); then
    [[ -n $ez_switcher_error ]] || ez_switcher_error="Codex Switcher $1 failed (status $status)."
    return 1
  fi
  if ! ez_switcher_json=$(jq -ces "if length == 1 then .[0] | $filter else error(\"expected one JSON result\") end" <<< "$output" 2>/dev/null); then
    ez_switcher_error="Codex Switcher $1 returned an invalid response."
    return 1
  fi
  ez_switcher_error=''
}

ez_switcher_inventory_filter='
    select(type == "object" and .schema_version == 1 and (.observed_at | type == "number")) |
    select(.sessions | type == "array") |
    select(all(.sessions[];
      (.id | type == "string" and length > 0) and
      (.name | type == "string") and (.cwd | type == "string") and
      (.account | type == "string") and
      (.display_account == null or (.display_account | type == "string")) and
      (.lifecycle == "live" or .lifecycle == "inactive") and
      (if .lifecycle == "live" then (.pane | type == "string" and test("^%[0-9]+$"))
       else (.thread_id | type == "string" and test("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")) end))) |
    select(([.sessions[].id] | unique | length) == (.sessions | length)) |
    .sessions |= map(.activity = (if .lifecycle == "inactive" then "inactive"
      elif .activity == "busy" or .activity == "idle" then .activity else "unknown" end))
  '
ez_switcher_inventory() {
  ez_switcher_request "$ez_switcher_inventory_filter" sessions --all
}

# The chooser owns this read-only stream and closes it on every exit path.
# Only the watcher process is stopped; durable operation workers are backend-owned.
ez_switcher_watch_start() {
  watch_errors=$(mktemp) || return 1
  coproc EZ_CODEX_WATCH { exec codex-switcher sessions --all --watch --interval 2 2>"$watch_errors"; }
  watch_pid=$EZ_CODEX_WATCH_PID
  exec {watch_fd}<&"${EZ_CODEX_WATCH[0]}"
  exec {EZ_CODEX_WATCH[1]}>&-
  watch_partial=''
}

ez_switcher_watch_close() {
  if [[ -n ${watch_pid:-} ]]; then
    kill "$watch_pid" 2>/dev/null || :
    wait "$watch_pid" 2>/dev/null || :
  fi
  [[ -z ${watch_fd:-} ]] || exec {watch_fd}<&-
  [[ -z ${watch_errors:-} ]] || rm -f -- "$watch_errors"
  watch_pid='' watch_fd='' watch_errors=''
}

# 0: a new complete snapshot; 1: no change; 2: disconnected/malformed.
# Timed reads can return a partial JSON line. Preserve it until its newline.
ez_switcher_watch_read() {
  local part result status=1 attempt
  for ((attempt=0;attempt<8;attempt++)); do
    IFS= read -r -t 0 -u "$watch_fd" || return "$status"
    part=''
    if IFS= read -r -t 0.01 -u "$watch_fd" part; then result=0; else result=$?; fi
    watch_partial+=$part
    if (( result == 0 )); then
      if ! ez_switcher_json=$(jq -cse "if length == 1 then .[0] | $ez_switcher_inventory_filter else empty end" <<< "$watch_partial" 2>/dev/null); then
        ez_switcher_error='Session discovery returned an invalid snapshot.'; return 2
      fi
      watch_snapshot=$ez_switcher_json watch_partial='' status=0
    elif (( result > 128 )); then return "$status"
    else
      ez_switcher_error="Session discovery disconnected. $(< "$watch_errors")"
      return 2
    fi
  done
  return "$status"
}

ez_switcher_accounts() {
  ez_switcher_request '
    select(type == "object" and .schema_version == 1 and (.accounts | type == "array")) |
    select(all(.accounts[]; (.name | type == "string" and length > 0)))
  ' status --json || return
  if [[ $(jq -r '.daemon.running' <<< "$ez_switcher_json") != true ]]; then
    ez_switcher_error='Codex Switcher supervisor is unavailable.'
    return 1
  fi
}

ez_switcher_job_filter='select(type == "object" and (.id | type == "string" and length > 0) and
  (.phase | type == "string" and length > 0) and (.detail | type == "string"))'

ez_switcher_jobs() {
  ez_switcher_request "select(type == \"array\") | select(all(.[]; [$ez_switcher_job_filter] | length == 1))" moves
}

ez_switcher_queue() {
  ez_switcher_request "$ez_switcher_job_filter" "$@"
}

ez_switcher_respond() {
  local id=$1 answer=$2 sequence=$3
  [[ $answer == yes || $answer == no ]] && [[ $sequence =~ ^[0-9]+$ ]] || {
    ez_switcher_error='This confirmation has no valid sequence number. Refresh the job.'; return 1;
  }
  # Never retry with a newer sequence: the user approved only the displayed dialog.
  ez_switcher_request 'select(type == "object")' move-response "$id" "$answer" --sequence "$sequence"
}

ez_switcher_terminal_phase() {
  case $1 in complete|failed|cancelled|recovered) return 0;; *) return 1;; esac
}

# Select by the backend key, with exact-thread fallback after a saved row goes live.
ez_switcher_find() {
  local snapshot=$1 key=$2 thread=${3-}
  ez_switcher_row=$(jq -ce --arg key "$key" --arg thread "$thread" '
    ([.sessions[] | select(.id == $key and ($thread == "" or .thread_id == $thread))][0] //
     (if $thread != "" then [.sessions[] | select(.thread_id == $thread)][0] else null end)) // empty
  ' <<< "$snapshot")
}

# Operations use pane/thread provenance, never a display nickname or tmux title.
ez_switcher_source() {
  local row=$1 lifecycle pane thread
  lifecycle=$(jq -r '.lifecycle' <<< "$row")
  if [[ $lifecycle == live ]]; then
    pane=$(jq -r '.pane' <<< "$row")
    [[ $pane =~ ^%[0-9]+$ ]] || return 1
    ez_switcher_source_args=(--pane "$pane")
  else
    thread=$(jq -r '.thread_id' <<< "$row")
    [[ $thread =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]] || return 1
    ez_switcher_source_args=(--thread "$thread")
  fi
}
