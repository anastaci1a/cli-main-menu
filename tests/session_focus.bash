#!/usr/bin/env bash
set -euo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export XDG_STATE_HOME=$test_root/state
source "$cli_dir/init.bash"
codex-switcher() { [[ $1 == sessions && $2 == --all ]]; cat "$test_root/snapshot"; }
tmux() { [[ $1 == list-panes ]] && printf '%%1|100|300\n%%2|200|400\n' || return 99; }
cat > "$test_root/snapshot" <<'JSON'
{"schema_version":1,"observed_at":10,"sessions":[
{"id":"pane:%1","pane":"%1","thread_id":"12345678-1234-1234-1234-123456789abc","name":"codex-Alpha","cwd":"/tmp","account":"external","display_account":"work","lifecycle":"live","activity":"idle"},
{"id":"pane:%2","pane":"%2","name":"codex-Beta","cwd":"/tmp","account":"personal","display_account":"personal","lifecycle":"live","activity":"busy"},
{"id":"thread:12345678-1234-1234-1234-123456789def","thread_id":"12345678-1234-1234-1234-123456789def","name":"Saved","cwd":"/tmp","account":"work","lifecycle":"inactive"}]}
JSON
original_labels=(Refresh) menu_keys=() menu_threads=() duration_created=() duration_prefix=() duration_mode=()
specified_accent_suffix=() specified_gray_suffix=() busy_rows=() disabled_indices='' selected=0 description='' screen_title='Sessions'
ez_codex_sessions_refresh
[[ ${menu_keys[*]} == 'new pane:%2 pane:%1 thread:12345678-1234-1234-1234-123456789def jobs' ]]
[[ ${original_labels[1]} == 'Beta   [personal]' && ${original_labels[2]} == 'Alpha*     [work]' && ${original_labels[3]} == 'Saved      [work]' ]]
[[ ${busy_rows[*]} == 1 && $disabled_indices == '' ]]
[[ ${specified_gray_suffix[3]} == ' (inactive)' && ${duration_created[1]} == 200 ]]
# Move Beta behind Alpha while it is selected. Identity, not row number, wins.
selected=1 refresh_function=ez_codex_sessions_refresh
jq '.sessions[0].activity="busy" | .sessions[1].activity="idle"' "$test_root/snapshot" > "$test_root/next"
mv "$test_root/next" "$test_root/snapshot"
ez_menu_refresh_view
[[ $selected == 2 && ${menu_keys[selected]} == pane:%2 ]]
# Saved -> live changes the stable key, but the exact thread keeps focus.
selected=3
jq '.sessions[2] += {id:"pane:%3",pane:"%3",lifecycle:"live",activity:"unknown"}' "$test_root/snapshot" > "$test_root/next"
mv "$test_root/next" "$test_root/snapshot"
ez_menu_refresh_view
[[ ${menu_keys[selected]} == pane:%3 ]]
# A failed inventory is visible and never turns stale activity into idle/empty.
printf '{broken' > "$test_root/snapshot"
ez_menu_refresh_view
[[ $description == 'Discovery Disconnected:'* && ${#menu_keys[@]} == 6 && ${#busy_rows[@]} == 0 ]]
[[ ${specified_gray_suffix[selected]} == ' (unknown; disconnected)' ]]
printf 'PASS grouped inventory, aligned nicknames, busy selection, stable focus and disconnected state\n'
