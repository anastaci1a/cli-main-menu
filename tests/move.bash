#!/usr/bin/env bash
# Only backend command fixtures: no histories, processes or project files are moved.
set -euo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
source "$cli_dir/init.bash"
thread=12345678-1234-1234-1234-123456789abc
job='{"id":"job-1","phase":"awaiting_pause_approval","confirmation_seq":4,"detail":"Pause the running turn?","source":{"thread_id":"12345678-1234-1234-1234-123456789abc"}}'
codex-switcher() {
  printf '%s\n' "$1" >> "$test_root/calls"
  printf '%s\0' "$@" > "$test_root/args"
  case $1 in
    moves) printf '[%s]\n' "$job" ;;
    status) printf '{"schema_version":1,"daemon":{"running":true},"accounts":[],"capabilities":{"session_pause":true,"session_termination":true}}' ;;
    move-response)
      [[ $5 == 4 ]] || return 1
      if [[ ${stale:-0} == 1 ]]; then printf 'stale confirmation\n' >&2; return 1; fi
      printf '{"response_recorded":true}' ;;
    cancel-move) printf '{"cancellation_requested":true}' ;;
    recover|move|restart|pause-session|terminate) printf '%s\n' "$job" ;;
    relocate)
      if [[ ${*: -1} == --dry-run ]]; then
        printf '{"schema_version":1,"detail":"Review other project users.","relocation":{"from":"/source","to":"/destination","move_files":true,"cross_filesystem":true},"other_sessions":["another conversation"]}'
      else printf '%s\n' "$job"; fi ;;
    *) return 99 ;;
  esac
}
tmux() { printf 'UNEXPECTED TMUX\n' >&2; return 99; }
ez_codex_error() { printf '%s\n' "${1:-$ez_switcher_error}" >> "$test_root/errors"; }
ez_menu_choose() {
  local choice
  choice=$(head -n 1 "$test_root/choices")
  tail -n +2 "$test_root/choices" > "$test_root/next"
  mv "$test_root/next" "$test_root/choices"
  [[ $choice != exit && -n $choice ]] || return 130
  printf '%s' "$choice"
}
ez_codex_document() {
  printf '%s\n%s\n' "$1" "$2" >> "$test_root/dialogs"
  return "${consent:-0}"
}
for phase in awaiting_pause_approval awaiting_background_approval awaiting_risk_acknowledgement; do
  job=$(jq -c --arg phase "$phase" '.phase=$phase' <<< "$job")
  printf 'respond\nexit\n' > "$test_root/choices"
  ez_codex_job job-1
  mapfile -d '' -t args < "$test_root/args"
  [[ ${args[*]} == 'move-response job-1 yes --sequence 4' ]]
done
consent=1
printf 'respond\nexit\n' > "$test_root/choices"
ez_codex_job job-1
mapfile -d '' -t args < "$test_root/args"
[[ ${args[*]} == 'move-response job-1 no --sequence 4' ]]
consent=130
before=$(wc -l < "$test_root/calls")
printf 'respond\nexit\n' > "$test_root/choices"
ez_codex_job job-1
[[ $(wc -l < "$test_root/calls") == $((before+1)) ]]
consent=0 stale=1
printf 'respond\nexit\n' > "$test_root/choices"
ez_codex_job job-1
[[ $(< "$test_root/errors") == *'stale confirmation'* ]]
[[ $(tail -n 1 "$test_root/calls") == move-response ]]
stale=0
for operation in cancel recover; do
  printf '%s\nexit\n' "$operation" > "$test_root/choices"
  ez_codex_job job-1
  [[ $(tail -n 1 "$test_root/calls") == ${operation/cancel/cancel-move} ]]
done
# Relocation review precedes queueing, with a literal destination argument.
ez_codex_field() { printf '%s' '/destination with spaces;$(literal)'; }
ez_codex_job() { [[ $1 == job-1 ]]; }
row=$(jq -nc --arg thread "$thread" '{id:("thread:"+$thread),thread_id:$thread,lifecycle:"inactive",cwd:"/source",account:"personal"}')
printf '0\n' > "$test_root/choices"
ez_codex_relocate "$row"
mapfile -d '' -t args < "$test_root/args"
[[ ${args[0]} == relocate && ${args[1]} == --thread && ${args[2]} == "$thread" && ${args[4]} == '/destination with spaces;$(literal)' ]]
[[ $(< "$test_root/dialogs") == *'another conversation'* ]]
[[ $(tail -n 2 "$test_root/calls") == $'relocate\nrelocate' ]]
consent=130
printf '0\n' > "$test_root/choices"
before=$(wc -l < "$test_root/calls")
ez_codex_relocate "$row"
[[ $(wc -l < "$test_root/calls") == $((before+1)) ]]
ez_codex_choose_account() { printf work; }
ez_codex_account_move "$(jq '.account="external" | .display_account="personal"' <<< "$row")"
mapfile -d '' -t args < "$test_root/args"
[[ ${args[*]} == "move --thread $thread --to work" ]]
consent=0
live_row=$(jq -c '.id="pane:%8" | .pane="%8" | .lifecycle="live" | .activity="busy"' <<< "$row")
ez_codex_get_current() { ez_switcher_row=$live_row; }
for operation in restart pause-session terminate; do
  printf '%s\nexit\n' "$operation" > "$test_root/choices"
  ez_codex_actions 'pane:%8' "$thread"
  mapfile -d '' -t args < "$test_root/args"
  [[ ${args[*]} == "$operation --pane %8" ]]
done
job_id=job-1
job=$(jq -c '.kind="terminate" | .phase="complete"' <<< "$job")
ez_codex_job_refresh
[[ ${original_labels[*]} == *'Start Saved Conversation'* && ${original_labels[*]} != *Recover* ]]
job=$(jq -c '.kind="directory" | .phase="failed" | .relocation={from:"/source",to:"/target",retained_source:"/backup",retained_destination:"/failed-copy",backend_note:"shared server preserved"}' <<< "$job")
details=$(ez_codex_job_details "$job")
[[ $details == *'Retained Source: /backup'* && $details == *'Retained Destination: /failed-copy'* && $details == *'shared server preserved'* ]]
printf 'PASS busy restart/pause/termination delegate without preapproval; completed termination and retained-path details\n'
printf 'PASS pause/background/risk consent, stale rejection, cancel/recovery, relocation review and quoting\n'
