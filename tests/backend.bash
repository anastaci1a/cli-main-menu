#!/usr/bin/env bash
set -euo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
source "$cli_dir/init.bash"
codex-switcher() {
  printf '%s\0' "$@" > "$test_root/args"
  [[ ${fail:-0} == 0 ]] || { printf 'fixture disconnected\n' >&2; return 7; }
  printf '%s\n' "$response"
}
response='{"schema_version":1,"observed_at":10,"sessions":[{"id":"pane:%7","pane":"%7","name":"unmanaged","cwd":"/tmp","account":"external","display_account":"work","lifecycle":"live"}]}'
ez_switcher_inventory
[[ $(jq -r '.sessions[0].activity' <<< "$ez_switcher_json") == unknown ]]
ez_switcher_find "$ez_switcher_json" 'pane:%7'
[[ $(jq -r '.account' <<< "$ez_switcher_row") == external ]]
for response in '' '[]' '{}' '{bad' '{"schema_version":2,"observed_at":10,"sessions":[]}' '{"schema_version":1,"observed_at":10,"sessions":[{}]}'; do
  if ez_switcher_inventory; then exit 1; fi
  [[ -n $ez_switcher_error ]]
done
response='{"schema_version":1,"observed_at":10,"sessions":[]}' fail=1
if ez_switcher_inventory; then exit 1; fi
[[ $ez_switcher_error == 'fixture disconnected' ]]
fail=0
ez_switcher_inventory
[[ $(jq '.sessions | length' <<< "$ez_switcher_json") == 0 ]]
response='{"schema_version":1,"daemon":{"running":false},"accounts":[]}'
if ez_switcher_accounts; then exit 1; fi
ez_codex_error() { :; }
ez_codex_attach() { touch "$test_root/attached"; }
for response in '{}' '{"schema_version":1,"session":{"pane":"bad","tmux_session":"valid"}}' '{"schema_version":1,"session":{"pane":"%1","tmux_session":""}}'; do
  if ez_codex_open '{"id":"pane:%7"}'; then exit 1; fi
  [[ ! -f $test_root/attached && -n $ez_switcher_error ]]
done
printf 'PASS backend schema, unknown activity, provenance, offline errors and invalid attachment targets\n'
