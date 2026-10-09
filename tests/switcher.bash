#!/usr/bin/env bash
set -euo pipefail

cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d /tmp/satellite-switcher-test.XXXXXX)
trap '/usr/bin/rm -rf -- "$test_root"' EXIT
switcher_log=$test_root/switcher.log
tmux_log=$test_root/tmux.log
monitor_file=$test_root/monitor
: > "$switcher_log"
: > "$tmux_log"

switch_ready=1
codex-switcher() {
  printf '<%s>' "$@" >> "$switcher_log"
  printf '\n' >> "$switcher_log"
  [[ $1 == ready ]] || return 99
  return "$switch_ready"
}
tmux() {
  local argument
  printf '%s' "$1" >> "$tmux_log"
  for argument in "${@:2}"; do printf '<%s>' "$argument" >> "$tmux_log"; done
  printf '\n' >> "$tmux_log"
  case $1 in
    has-session) [[ $3 == '=codex-switcher' ]] && [[ -s $monitor_file ]] || [[ $3 == '$0' ]] ;;
    new-session)
      if [[ " $* " == *' -s codex-switcher '* ]]; then
        printf 'active\n' > "$monitor_file"
      else
        printf '$0\n'
      fi
      ;;
    list-sessions)
      [[ ! -s $monitor_file ]] || printf '$9|codex-switcher|100|200|\n'
      ;;
    attach-session|switch-client|set-option) : ;;
    *) return 99 ;;
  esac
}

source -- "$cli_dir/init.bash"
source -- "$cli_dir/init.bash"
[[ ! -s $switcher_log && ! -s $tmux_log ]]
if ez_codex_valid_name switcher; then exit 1; fi
printf 'PASS repeated sourcing starts no switcher or tmux process\n'

if command -v jq >/dev/null 2>&1; then
  codex-switcher() {
    [[ $1 == instances ]] || return 99
    printf '[{"inactive":false,"tmux_session":"codex-Alpha","account":"external","display_account":"personal"},{"inactive":false,"tmux_session":"codex-Beta","account":"work","display_account":"work"},{"inactive":false,"tmux_session":"codex-Gamma","account":"external","display_account":null},{"inactive":false,"tmux_session":"codex-Delta","account":"work"},{"inactive":true,"tmux_session":"codex-Epsilon","account":"personal","display_account":"personal"}]\n'
  }
  ez_codex_names=(Alpha Beta Gamma Delta Epsilon)
  ez_codex_session_accounts
  [[ ${ez_codex_accounts[*]} == 'personal work external work unknown' ]]
  unset -f codex-switcher
fi
printf 'PASS session labels prefer identity nickname and fall back to account provenance\n'

codex-switcher() {
  printf '<%s>' "$@" >> "$switcher_log"
  printf '\n' >> "$switcher_log"
  [[ $1 == ready ]] || return 99
  return "$switch_ready"
}

PATH='/tmp/path with spaces'
TMUX=''
unset CODEX_HOME
CODEX_SWITCHER_HOME="$test_root/state with spaces"
export CODEX_SWITCHER_HOME
ez_menu_codex_monitor_available
if ez_menu_codex_switching_available; then exit 1; fi
[[ $(< "$switcher_log") == '<ready>' ]]
ez_menu_codex_monitor >/dev/null 2>&1
ez_menu_codex_monitor >/dev/null 2>&1
[[ -s $monitor_file ]]
if ez_menu_has_codex; then exit 1; fi
tmux_output=$(< "$tmux_log")
[[ $tmux_output == *'new-session<-d><-s><codex-switcher><-e><PATH=/tmp/path with spaces><-e><CODEX_SWITCHER_HOME='* ]]
[[ $tmux_output == *'<codex-switcher><ui>'* ]]
new_count=0
while IFS= read -r line; do [[ $line != new-session* ]] || new_count=$((new_count+1)); done <<< "$tmux_output"
[[ $new_count == 1 ]]
[[ $tmux_output == *'attach-session<-t><=codex-switcher>'* ]]
TMUX='test-client'
ez_menu_codex_monitor >/dev/null 2>&1
tmux_output=$(< "$tmux_log")
[[ $tmux_output == *'switch-client<-t><=codex-switcher>'* ]]
new_count=0
while IFS= read -r line; do [[ $line != new-session* ]] || new_count=$((new_count+1)); done <<< "$tmux_output"
[[ $new_count == 1 ]]
printf 'PASS monitor session reuses tmux and switches clients without nesting\n'

switch_ready=0
ez_menu_codex_switching_available
test_dir="$test_root/"'path with spaces;$(printf hijack)'
/usr/bin/mkdir -p -- "$test_dir"
ez_codex_field() {
  if [[ $1 == 'Session name' ]]; then printf 'test-name'
  else printf '%s' "$test_dir"; fi
}
ez_codex_new >/dev/null 2>&1
tmux_output=$(< "$tmux_log")
[[ $tmux_output == *"new-session<-d><-P><-F><#{session_id}><-s><codex-test-name><-c><$test_dir><-e><PATH=/tmp/path with spaces>"* ]]
[[ $tmux_output == *'<satellite-codex><codex><--dangerously-bypass-approvals-and-sandbox>'* ]]
[[ $tmux_output == *'switch-client<-t><$0>'* ]]
[[ $(< "$switcher_log") != *'<run>'* ]]
printf 'PASS readiness does not change direct Codex launch or quoted arguments\n'

TMUX=''
ez_codex_new >/dev/null 2>&1
[[ $(< "$tmux_log") == *'attach-session<-t><$0>'* ]]
printf 'PASS Codex attaches outside tmux and switches clients inside tmux\n'

PATH=''
unset -f tmux
if ez_menu_codex_monitor_available; then exit 1; fi
unset -f codex-switcher
if ez_menu_codex_monitor_available || ez_menu_codex_switching_available; then exit 1; fi
printf 'PASS missing binaries disable the dashboard action\n'
