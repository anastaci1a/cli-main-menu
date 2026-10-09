#!/usr/bin/env bash
# Isolated switcher/tmux fixtures; never inspect or stop the user's sessions.
set -euo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d /tmp/satellite-move-test.XXXXXXXX)
trap '[[ -z ${live_pid:-} ]] || builtin kill "$live_pid" 2>/dev/null || :; rm -rf -- "$test_root"' EXIT
export XDG_STATE_HOME=$test_root/state CODEX_SWITCHER_HOME=$test_root/switcher
source -- "$cli_dir/init.bash"
thread=12345678-1234-1234-1234-123456789abc
test_thread=$thread
mkdir -p "$test_root/home" "$test_root/source folder" "$test_root/other folder" "$test_root/destination"
source_dir=$test_root/source\ folder
other_dir=$test_root/other\ folder
target_dir=$test_root/destination/renamed\ folder
rollout=$test_root/rollout.jsonl
test_rollout=$rollout
printf '{"type":"session_meta","payload":{"id":"%s","source":"cli","cwd":"%s"}}\n' "$thread" "$source_dir" > "$rollout"
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_started"}}' '{"type":"event_msg","payload":{"type":"task_complete"}}' >> "$rollout"
printf '%s\n' '{"type":"turn_context","payload":{"approval_policy":"on-request","sandbox_policy":{"type":"workspace-write"}}}' >> "$rollout"
printf 'original data\n' > "$source_dir/file.txt"
instance_mode=inactive attached=0 pane_dead=0 fail_respawn=0 ready_prompt=1
codex-switcher() {
  [[ $1 == instances ]] || return 99
  if [[ $instance_mode == unknown ]]; then
    printf '[]\n'
  elif [[ $instance_mode == inactive ]]; then
    jq -nc --arg thread "$test_thread" --arg cwd "$source_dir" --arg home "$test_root/home" --arg rollout "$test_rollout" \
      --arg binary codex --arg reason "$([[ -d $source_dir ]] && printf '' || printf missing)" \
      '[{inactive:true,thread_id:$thread,cwd:$cwd,account:"external",display_account:"work",home:$home,binary:$binary,rollout:$rollout,block_reason:(if $reason=="" then null else $reason end),resume_options:[]}]'
  else
    jq -nc --arg thread "$test_thread" --arg cwd "$source_dir" --arg home "$test_root/home" --arg rollout "$test_rollout" \
      --argjson pid "$live_pid" --argjson start "$live_start" \
      '[{inactive:false,tmux_session:"codex-Focus",pane:"%9",pid:$pid,start_time:$start,cwd:$cwd,thread_id:$thread,rollout:$rollout,home:$home,binary:"codex",resume_options:["--dangerously-bypass-approvals-and-sandbox"],block_reason:null,account:"external",display_account:"work"}]'
  fi
}
tmux() {
  case $1 in
    list-sessions) [[ $instance_mode == live ]] && printf '$9|codex-Focus|100|200|\n' || : ;;
    display-message)
      case ${*: -1} in
        '#{session_name}') printf 'codex-Focus\n' ;;
        '#{session_id}|#{session_attached}|#{pane_dead}|#{pane_pid}|#{pane_current_command}')
          printf '$9|%s|%s|%s|codex\n' "$attached" "$pane_dead" "$live_pid" ;;
        '#{pane_dead}') printf '%s\n' "$pane_dead" ;;
        '#{session_attached}|#{pane_dead}') printf '%s|%s\n' "$attached" "$pane_dead" ;;
        '#{pane_pid}|#{pane_current_command}') printf '%s|codex\n' "$live_pid" ;;
      esac ;;
    list-panes) printf '%%9\n' ;;
    capture-pane) (( ready_prompt )) && printf '› Ask Codex to do anything\n' || printf 'Working...\n' ;;
    has-session) return 1 ;;
    new-session)
      printf '%s\0' "$@" > "$test_root/new-session.args"
      printf '$4\n' ;;
    respawn-pane)
      printf '%s\0' "$@" > "$test_root/respawn.args"
      (( fail_respawn )) && return 1
      pane_dead=0 ;;
    show-options) printf 'failed\n' ;;
    kill-session) printf '%s\0' "$@" > "$test_root/killed-session.args" ;;
    set-option|attach-session|switch-client) : ;;
    *) printf 'Unexpected tmux command: %s\n' "$1" >&2; return 99 ;;
  esac
}
ez_codex_attach() { attached_id=$1; }

ez_codex_inactive_scan
[[ ${ez_inactive_names[0]} == 'source folder (12345678)' && ${ez_inactive_accounts[0]} == work ]]
[[ $(ez_menu_codex_label) == 'Codex: Start (source folder (12345678))' ]]
ez_codex_alias_save "$thread" Focus
ez_codex_inactive_scan
[[ ${ez_inactive_names[0]} == Focus ]]
[[ $(ez_menu_codex_label) == 'Codex: Start (Focus)' ]]
printf 'PASS inactive sessions use switcher nickname, persistent alias, and Start label\n'

if ez_codex_new_dir_name_target "$test_root" 'source folder' >/dev/null; then exit 1; fi
[[ $(ez_codex_new_dir_name_target "$test_root/destination" 'renamed folder') == "$target_dir" ]]
[[ $(ez_codex_input_line 'source folder' 'Move directory name' 0 80) == *"$C_RED>"* ]]
printf 'PASS move folder name rejects duplicates and shows invalid input in red\n'

ez_codex_resume_inactive "$thread" "$other_dir" 0
mapfile -d '' -t args < "$test_root/new-session.args"
[[ " ${args[*]} " == *" CODEX_HOME=$test_root/home "* ]]
[[ " ${args[*]} " == *" CODEX_SWITCHER_HOME=$test_root/switcher "* ]]
[[ " ${args[*]} " == *" resume $thread -C $other_dir "* ]]
[[ " ${args[*]} " == *' --ask-for-approval on-request --sandbox workspace-write '* ]]
[[ " ${args[*]} " != *' --dangerously-bypass-approvals-and-sandbox '* ]]
[[ " ${args[*]} " == *' -s codex-Focus '* ]]
printf 'PASS saved conversation starts with exact thread, root, alias, and account home\n'

ez_codex_move_inactive_execute "$thread" "$source_dir" "$target_dir" 1 2> "$test_root/progress"
[[ ! -e $source_dir && $(< "$target_dir/file.txt") == 'original data' ]]
[[ $attached_id == '$4' ]]
[[ $(< "$test_root/progress") == *'100%'* ]]
printf 'PASS inactive folder move keeps the exact conversation and starts in its new root\n'

# A simulated failed launch rolls the renamed directory back without deleting data.
source_dir=$target_dir
rollback_target=$test_root/destination/second\ move
pane_dead=1
if ez_codex_move_inactive_execute "$thread" "$source_dir" "$rollback_target" 1 2> "$test_root/progress"; then exit 1; fi
[[ -f $source_dir/file.txt && ! -e $rollback_target ]]
printf 'PASS failed inactive restart restores the original folder\n'

mkdir -p "$test_root/live source"
printf 'live data\n' > "$test_root/live source/live.txt"
source_dir=$test_root/live\ source
live_target=$test_root/destination/live\ moved
sleep 60 & live_pid=$!
proc_stat=$(< "/proc/$live_pid/stat")
read -ra proc_fields <<< "${proc_stat#*) }"
live_start=${proc_fields[19]}
instance_mode=live pane_dead=0
ez_codex_move_info '$9'
attached=1
if ez_codex_move_info '$9'; then exit 1; fi
attached=0
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_started"}}' >> "$rollout"
if ez_codex_move_info '$9'; then exit 1; fi
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete"}}' >> "$rollout"
ez_codex_move_info '$9'
printf 'PASS live Move requires a detached pane with a completed turn\n'

instance_mode=unknown
ez_codex_session_idle '$9'
ready_prompt=0
if ez_codex_session_idle '$9'; then exit 1; fi
ready_prompt=1 attached=1
if ez_codex_session_idle '$9'; then exit 1; fi
attached=0 instance_mode=live
printf 'PASS detached unidentified Codex pane shows idle only at its input prompt\n'

kill() { builtin kill "$@"; pane_dead=1; }
ez_codex_move_execute '$9' "$source_dir" "$live_target" 1 2> "$test_root/progress"
[[ ! -e $source_dir && $(< "$live_target/live.txt") == 'live data' ]]
mapfile -d '' -t args < "$test_root/respawn.args"
[[ " ${args[*]} " == *" CODEX_HOME=$test_root/home "* ]]
[[ " ${args[*]} " == *" resume $thread -C $live_target "* ]]
[[ " ${args[*]} " == *' --ask-for-approval on-request --sandbox workspace-write '* ]]
printf 'PASS idle tmux Move restarts the exact thread in place with its account home\n'

if [[ -w /dev/shm && $(stat -c %d -- /dev/shm) != "$(stat -c %d -- "$test_root")" ]]; then
  cross_root=$(mktemp -d /dev/shm/satellite-move-test.XXXXXXXX)
  trap '[[ -z ${live_pid:-} ]] || builtin kill "$live_pid" 2>/dev/null || :; rm -rf -- "$test_root" "$cross_root"' EXIT
  mkdir -p "$test_root/cross source"
  printf 'cross-device data\n' > "$test_root/cross source/file.txt"
  source_dir=$test_root/cross\ source
  cross_target=$cross_root/cross\ target
  instance_mode=inactive pane_dead=0
  ez_codex_move_inactive_execute "$thread" "$source_dir" "$cross_target" 1 2> "$test_root/progress"
  [[ ! -e $source_dir && $(< "$cross_target/file.txt") == 'cross-device data' ]]
  [[ $(< "$test_root/progress") == *'100%'* ]]
  printf 'PASS cross-filesystem move copies files with progress and removes source after start\n'
fi

mkdir -p "$test_root/terminate source"
source_dir=$test_root/terminate\ source
sleep 60 & live_pid=$!
proc_stat=$(< "/proc/$live_pid/stat")
read -ra proc_fields <<< "${proc_stat#*) }"
live_start=${proc_fields[19]}
instance_mode=live pane_dead=0
kill() { builtin kill "$@"; pane_dead=1 instance_mode=inactive; }
ez_codex_terminate '$9'
[[ -d $source_dir && -f $test_root/killed-session.args ]]
mapfile -d '' -t args < "$test_root/killed-session.args"
[[ " ${args[*]} " == *' kill-session -t $9 '* ]]
printf 'PASS Terminate stops the tmux pane only after the conversation becomes inactive\n'

codex() { printf '%s\n' "$CODEX_HOME" "$@" > "$test_root/delete.args"; }
ez_menu_choose() { printf '%s\0' "$@" > "$test_root/delete-menu.args"; printf '0'; }
ez_codex_delete_inactive "$thread" Focus
mapfile -t args < "$test_root/delete.args"
[[ ${args[0]} == "$test_root/home" && ${args[1]} == delete &&
   ${args[2]} == --force && ${args[3]} == "$thread" ]]
mapfile -d '' -t args < "$test_root/delete-menu.args"
[[ ${args[*]} == *' -- Delete conversation' && ${args[*]} != *Cancel* ]]
if ez_codex_alias_read "$thread"; then exit 1; fi
printf 'PASS inactive Delete uses Codex in the source account and clears the display alias\n'

older_thread=22345678-1234-1234-1234-123456789abc
older_rollout=$test_root/older.jsonl
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete"}}' > "$older_rollout"
touch -t 202001010000 -- "$older_rollout"
codex-switcher() {
  [[ $1 == instances ]] || return 99
  jq -nc --arg older "$older_thread" --arg current "$test_thread" \
    --arg older_rollout "$older_rollout" --arg current_rollout "$test_rollout" \
    --arg home "$test_root/home" --arg cwd "$test_root/terminate source" \
    '[{inactive:true,thread_id:$older,cwd:$cwd,account:"external",display_account:"work",home:$home,binary:"codex",rollout:$older_rollout,block_reason:null,resume_options:[]},
      {inactive:true,thread_id:$current,cwd:$cwd,account:"external",display_account:"work",home:$home,binary:"codex",rollout:$current_rollout,block_reason:null,resume_options:[]}]'
}
ez_codex_inactive_scan
[[ ${ez_inactive_ids[0]} == "$thread" && ${ez_inactive_ids[1]} == "$older_thread" ]]
printf 'PASS inactive conversations sort newest first within their group\n'
