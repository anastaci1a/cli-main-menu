#!/usr/bin/env bash
# A real tmux server on a private socket with a fake Codex executable.
set -euo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d /tmp/satellite-move-tmux.XXXXXXXX)
socket=$test_root/tmux.sock
tmux_binary=$(command -v tmux)
trap '"$tmux_binary" -S "$socket" kill-server 2>/dev/null || :; rm -rf -- "$test_root"' EXIT
tmux() { "$tmux_binary" -S "$socket" -f /dev/null "$@"; }
source -- "$cli_dir/init.bash"
test_thread=12345678-1234-1234-1234-123456789abc
test_source=$test_root/source\ folder
test_target=$test_root/new\ parent/renamed\ folder
test_current_dir=$test_source
test_rollout=$test_root/rollout.jsonl
test_home=$test_root/codex-home
test_binary=$test_root/codex
mkdir -p "$test_source" "$test_root/new parent" "$test_home"
printf 'project file\n' > "$test_source/file.txt"
printf '%s\n' 'while :; do IFS= read -r -t 1 input || :; done' > "$test_source/resume"
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_started"}}' \
  '{"type":"event_msg","payload":{"type":"task_complete"}}' > "$test_rollout"
cp /bin/bash "$test_binary"
chmod +x "$test_binary"
id=$(tmux new-session -d -P -F '#{session_id}' -s codex-Fixture -c "$test_source" \
  "$test_binary" resume "$test_thread" -C "$test_source")
pane=$(tmux display-message -p -t "$id" '#{pane_id}')
test_pane=$pane
for ((attempt=0;attempt<50;attempt++)); do
  [[ $(tmux display-message -p -t "$id" '#{pane_current_command}') == codex ]] && break
  sleep 0.1
done
[[ $(tmux display-message -p -t "$id" '#{pane_current_command}') == codex ]]
codex-switcher() {
  [[ $1 == instances ]] || return 99
  local pid statline parts start dead
  pid=$(tmux display-message -p -t "$id" '#{pane_pid}')
  dead=$(tmux display-message -p -t "$id" '#{pane_dead}')
  if [[ $dead == 1 ]]; then
    jq -nc --arg thread "$test_thread" --arg cwd "$test_current_dir" \
      --arg home "$test_home" --arg rollout "$test_rollout" --arg binary "$test_binary" \
      '[{inactive:true,thread_id:$thread,cwd:$cwd,home:$home,rollout:$rollout,binary:$binary,account:"external",display_account:"work",block_reason:null,resume_options:[]}]'
  else
    statline=$(< "/proc/$pid/stat")
    read -ra parts <<< "${statline#*) }"
    start=${parts[19]}
    jq -nc --arg thread "$test_thread" --arg cwd "$test_current_dir" \
      --arg home "$test_home" --arg rollout "$test_rollout" --arg binary "$test_binary" \
      --arg pane "$test_pane" --argjson pid "$pid" --argjson start "$start" \
      '[{inactive:false,tmux_session:"codex-Fixture",pane:$pane,pid:$pid,start_time:$start,thread_id:$thread,cwd:$cwd,home:$home,rollout:$rollout,binary:$binary,account:"external",display_account:"work",block_reason:null,resume_options:[]}]'
  fi
}
ez_codex_move_info "$id"
if ! ez_codex_move_execute "$id" "$test_source" "$test_target" 1 2> "$test_root/progress"; then
  cat "$test_root/progress" >&2
  exit 1
fi
[[ ! -e $test_source && -f $test_target/file.txt ]]
[[ $(tmux display-message -p -t "$id" '#{pane_current_path}') == "$test_target" ]]
[[ $(tmux display-message -p -t "$id" '#{pane_current_command}') == codex ]]
[[ $(< "$test_root/progress") == *'100%'* ]]
printf 'PASS real isolated tmux pane resumes the same thread in the moved directory\n'

test_current_dir=$test_target
ez_codex_terminate "$id"
if tmux has-session -t "$id" 2>/dev/null; then exit 1; fi
[[ -f $test_target/file.txt && -f $test_rollout ]]
printf 'PASS Terminate removes only the isolated tmux session after saved history is available\n'
