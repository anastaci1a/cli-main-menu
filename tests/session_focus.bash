#!/usr/bin/env bash
# Exercise menu selection across a reorder without touching live tmux sessions.
set -euo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d /tmp/satellite-session-focus.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
source -- "$cli_dir/init.bash"

ez_codex_scan() {
  case $scenario:$state in
    existing:before)
      ez_codex_ids=('$1' '$2') ez_codex_names=(Alpha Beta)
      ;;
    existing:after)
      ez_codex_ids=('$2' '$1') ez_codex_names=(Beta Alpha)
      ;;
    new:before|gone:after)
      ez_codex_ids=() ez_codex_names=()
      ;;
    new:after|gone:before)
      ez_codex_ids=('$2') ez_codex_names=(Beta)
      ;;
  esac
  ez_codex_created=(100 100)
}
ez_codex_session_accounts() {
  ez_codex_accounts=()
  for ((i=0;i<${#ez_codex_ids[@]};i++)); do ez_codex_accounts[i]=personal; done
}
ez_codex_inactive_scan() { ez_inactive_ids=() ez_inactive_names=() ez_inactive_accounts=(); }
ez_codex_session_idle() { return 1; }
ez_menu_choose() {
  printf '%s\n' "$1" >> "$selection_file"
  local count
  count=$(< "$choice_file")
  printf '%d\n' "$((count+1))" > "$choice_file"
  (( count == 0 )) || return 130
  case $scenario in existing) printf '2';; new) printf '0';; gone) printf '1';; esac
}
ez_codex_actions() {
  action_id=$1
  state=after
}
ez_codex_new() {
  ez_codex_new_id='$2'
  state=after
}

for scenario in existing new gone; do
  state=before action_id=''
  selection_file=$test_root/$scenario.selections
  choice_file=$test_root/$scenario.choice
  printf '0\n' > "$choice_file"
  ez_menu_codex_sessions
  mapfile -t selections < "$selection_file"
  case $scenario in
    existing)
      [[ $action_id == '$2' && ${selections[*]} == '0 1' ]]
      ;;
    new)
      [[ ${selections[*]} == '0 1' ]]
      ;;
    gone)
      [[ $action_id == '$2' && ${selections[*]} == '0 0' ]]
      ;;
  esac
done
printf 'PASS session focus follows the tmux ID after reorder or creation and resets after removal\n'

ez_codex_session_idle() { [[ $1 == '$1' ]]; }
ez_codex_inactive_scan() {
  ez_inactive_ids=(12345678-1234-1234-1234-123456789abc)
  ez_inactive_names=(Saved)
  ez_inactive_accounts=(work)
}
ez_menu_choose() {
  printf '%s\0' "$@" > "$test_root/ordered-args"
  return 130
}
scenario=existing state=before
ez_menu_codex_sessions
mapfile -d '' -t ordered < "$test_root/ordered-args"
labels=()
found=0
for entry in "${ordered[@]}"; do
  if (( found )); then labels+=("$entry"); fi
  [[ $entry == -- ]] && found=1
done
[[ ${labels[0]} == '[new session]' && ${labels[1]} == 'Beta   [personal]' &&
   ${labels[2]} == 'Alpha* [personal]' && ${labels[3]} == 'Saved  [work]' ]]
[[ " ${ordered[*]} " == *' --gray-suffix 3  (inactive) '* ]]
printf 'PASS Sessions orders running, idle, then inactive and marks idle tmux sessions\n'
