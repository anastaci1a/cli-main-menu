#!/usr/bin/env bash
set -euo pipefail

cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bashrc_path=${1:-"$cli_dir/../../.bashrc"}
bashrc_path=$(CDPATH='' cd -- "$(dirname -- "$bashrc_path")" && printf '%s/%s' "$PWD" "${bashrc_path##*/}")
for module in "$cli_dir/"*.bash "$bashrc_path"; do bash -n "$module"; done

test_root=$(mktemp -d /tmp/satellite-cli-smoke.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
fixture="$test_root/relocated home"
mkdir -p "$fixture/scripts/cli" "$test_root/unrelated cwd"
cp -- "$bashrc_path" "$fixture/.bashrc"
cp -- "$cli_dir/"*.bash "$fixture/scripts/cli/"

for profile in "$bashrc_path" "$fixture/.bashrc"; do
  (
    cd -- "$test_root/unrelated cwd"
    bash --noprofile --norc -O expand_aliases -s -- "$profile" <<'BASH'
set -eo pipefail
starting_directory=$PWD
source -- "$1"
source -- "$1"
[[ $PWD == "$starting_directory" ]]
for name in ez_select ez_menu_choose ez_menu_banner ez_menu_status ez_menu_draw \
  ez_menu_codex ez_menu_jobs ez_menu_has_stopped_jobs; do
  declare -F "$name" >/dev/null
done
[[ $(alias startup) == "alias startup='clear && ez_select'" ]]
[[ -n $C_RESET && -n $C_STAR_BLUE && -n $C_DISABLED_NUMBER ]]
if declare -F _ez_cli_load >/dev/null; then exit 1; fi
clear() { :; }
tmux() { [[ $1 == has-session ]] && return 1; return 99; }
output=$(eval startup <<< 1 2>&1)
[[ $output == *'Ready when you are.'* ]]
printf 'PASS source/reload/startup: %s\n' "$1"
BASH
  )
done
