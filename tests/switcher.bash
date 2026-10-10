#!/usr/bin/env bash
set -euo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export XDG_STATE_HOME=$test_root/state
source "$cli_dir/init.bash"
source "$cli_dir/init.bash"
codex-switcher() {
  printf '%s\0' "$@" > "$test_root/args"
  case $1 in
    status) printf '{"schema_version":1,"daemon":{"running":true},"accounts":[{"name":"personal","eligible":false},{"name":"work","eligible":true}]}' ;;
    open) printf '{"schema_version":1,"session":{"pane":"%%7","tmux_session":"codex-project"}}' ;;
    *) return 99 ;;
  esac
}
tmux() {
  printf '<%s>' "$@" >> "$test_root/tmux"
  case $1 in
    has-session) [[ -f $test_root/monitor ]] ;;
    new-session) touch "$test_root/monitor" ;;
    attach-session|switch-client|set-option|select-window|select-pane) : ;;
    *) return 99 ;;
  esac
}
TMUX=''
ez_menu_codex_monitor >/dev/null
TMUX=test-client
ez_menu_codex_monitor >/dev/null
[[ $(< "$test_root/tmux") == *'<codex-switcher><ui>'* ]]
[[ $(< "$test_root/tmux") == *'<switch-client><-t><=codex-switcher>'* ]]
[[ ! -e $test_root/args ]]
ez_menu_choose() { printf '%s\0' "$@" > "$test_root/choices"; printf '1'; }
[[ $(ez_codex_choose_account) == work ]]
mapfile -d '' -t options < "$test_root/choices"
[[ " ${options[*]} " != *' --disabled 0 '* && " ${options[*]} " == *'personal (check capacity)'* ]]
ez_codex_attach() { printf '%s\0' "$@" > "$test_root/attach"; }
ez_codex_valid_name() { return 0; }
thread=12345678-1234-1234-1234-123456789abc
row=$(jq -nc --arg thread "$thread" '{id:("thread:"+$thread),thread_id:$thread,name:"project",cwd:"/tmp/path with spaces;$(literal)",account:"work",display_account:"personal",lifecycle:"inactive"}')
ez_codex_open "$row"
mapfile -d '' -t args < "$test_root/args"
[[ ${args[*]} == "open --session thread:$thread" ]]
mapfile -d '' -t args < "$test_root/attach"
[[ ${args[0]} == =codex-project && ${args[1]} == %7 ]]
ez_codex_document() { return 0; }
ez_codex_account_move() { printf 'move\n' > "$test_root/external"; }
ez_codex_open "$(jq '.account="external"' <<< "$row")"
[[ ! -f $test_root/external ]]
mapfile -d '' -t args < "$test_root/args"
[[ ${args[0]} == open && ${args[2]} == "thread:$thread" ]]
# Busy live sessions (including ones with pending jobs) open directly too.
ez_codex_open "$(jq '.id="pane:%7" | .lifecycle="live" | .activity="busy" | .move_id="pending"' <<< "$row")"
mapfile -d '' -t args < "$test_root/args"
[[ ${args[*]} == 'open --session pane:%7' ]]
printf 'PASS dashboard reuse, capacity warnings, original-home backend opening and attachment\n'
