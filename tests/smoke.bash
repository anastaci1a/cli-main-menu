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

# Exercise config precedence in the temporary installation, never the user's file.
rm -f -- "$fixture/scripts/cli/config.bash"
bash --noprofile --norc -s -- "$fixture/.bashrc" "$fixture/scripts/cli" <<'BASH'
set -eo pipefail
source -- "$1"
[[ $EZ_MENU_TITLE == 'MAIN MENU' ]]
default_color=$C_PINK
printf "EZ_MENU_TITLE='ORBIT 7'\nC_PINK='custom color'\n" > "$2/config.bash"
source -- "$1"
[[ $EZ_MENU_TITLE == 'ORBIT 7' && $C_PINK == 'custom color' ]]
rm -- "$2/config.bash"
source -- "$1"
[[ $EZ_MENU_TITLE == 'MAIN MENU' && $C_PINK == "$default_color" ]]

# Every title row must fill the screen, with centered text at compact sizes.
for EZ_MENU_TITLE in 'MAIN MENU' SATELLITE X 'A MUCH LONGER TITLE 123' 'Menu!'; do
  for COLUMNS in 5 20 56 80 160; do
    output=$(ez_menu_banner | sed $'s/\033\\[[0-9;]*m//g')
    while IFS= read -r row; do
      [[ -z $row || ${#row} == "$COLUMNS" ]]
    done <<< "$output"
    output=$(ez_menu_banner 1 0 | sed $'s/\033\\[[0-9;]*m//g')
    mapfile -t lines <<< "$output"
    title=${EZ_MENU_TITLE:0:COLUMNS}
    offset=$(( (COLUMNS - ${#title}) / 2 ))
    [[ ${lines[1]:offset:${#title}} == "$title" ]]
  done
done
printf 'PASS config defaults/overrides/reload and responsive titles\n'
BASH
