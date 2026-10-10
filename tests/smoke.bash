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
# Never call the installed switcher while exercising the menu in tests.
PATH=/usr/bin:/bin
[[ $PWD == "$starting_directory" ]]
for name in ez_select ez_menu_choose ez_menu_banner ez_menu_status ez_menu_draw \
  ez_menu_codex ez_menu_jobs ez_menu_has_stopped_jobs; do
  declare -F "$name" >/dev/null
done

[[ $(alias startup) == "alias startup='clear && ez_select'" ]]
[[ -n $C_RESET && -n $C_STAR_BLUE && -n $C_DISABLED_NUMBER ]]
[[ $(ez_codex_resolve_dir //) == / ]]
[[ $(ez_codex_resolve_dir //tmp) == /tmp ]]
new_dir_name='new dir +-=~()[] $ !#'
[[ $(ez_codex_new_dir_target "$starting_directory/$new_dir_name") == "$starting_directory/$new_dir_name" ]]
literal_dollar_input="$starting_directory/"'literal\$HOME'
literal_dollar_expected="$starting_directory/"'literal$HOME'
[[ $(ez_codex_new_dir_target "$literal_dollar_input") == "$literal_dollar_expected" ]]
[[ $(ez_codex_new_dir_target "$starting_directory/missing/child" 2>/dev/null) == '' ]]
[[ $(ez_codex_new_dir_target "$starting_directory" 2>/dev/null) == '' ]]
[[ $(ez_codex_new_dir_name_target "$starting_directory" "$new_dir_name") == "$starting_directory/$new_dir_name" ]]
[[ $(ez_codex_new_dir_name_target "$starting_directory" 'literal$HOME') == "$literal_dollar_expected" ]]
[[ $(ez_codex_new_dir_name_target "$starting_directory" 'bad/name' 2>/dev/null) == '' ]]
[[ $(ez_codex_new_dir_name_target "$starting_directory" '' 2>/dev/null) == '' ]]
created_dir="$starting_directory/new directory from prompt"
[[ $(printf '%s\ny\n' "$created_dir" | ez_codex_field 'Start directory' '/' 2>/dev/null) == "$created_dir" ]]
[[ -d $created_dir ]]
for case in '0 0:00' '1 0:01' '59 0:59' '60 1:00' '3599 59:59' '3600 1:00:00' '86400 1:00:00:00'; do
  read -r elapsed expected <<< "$case"
  [[ $(ez_codex_duration "$elapsed") == "$expected" ]]
done
if declare -F _ez_cli_load >/dev/null; then exit 1; fi
clear() { :; }
tmux() { [[ $1 == has-session ]] && return 1; return 99; }
output=$(eval startup <<< 1 2>&1)
[[ $output == *'Ready when you are.'* ]]
[[ $output != *--exit-control* && $output != *--disabled* ]]
[[ $output == *'0  Exit'* && $output != *'Codex: Account Switcher'* && $output != *'no stopped jobs'* ]]
[[ $(printf '0\n' | ez_menu_choose 0 Test --exit-control --disabled '' -- One Two 2>/dev/null) == exit ]]
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
main_hints=$(ez_menu_hint_lines main 4)
name_hints=$(ez_menu_hint_lines name 1 0)
empty_directory_hints=$(ez_menu_hint_lines directory 1 0)
directory_hints=$(ez_menu_hint_lines directory 4 1)
[[ $main_hints == *'Esc: Exit'* && $main_hints == *'▲/▼: Move'* && $main_hints != *'Ctrl-L'* ]]
[[ $name_hints == *'Esc: Back'* && $name_hints != *'▲/▼'* && $name_hints != *'Enter:'* && $name_hints != *'Ctrl-L'* ]]
[[ $empty_directory_hints != *'▲/▼'* && $empty_directory_hints != *'▶/Tab'* && $empty_directory_hints != *'Enter:'* ]]
[[ $directory_hints == *'◀: Parent'* && $directory_hints == *'Esc: Back'* && $directory_hints != *'parent/Back'* ]]
for hint_set in "$main_hints" "$name_hints" "$empty_directory_hints" "$directory_hints"; do
  [[ ! $hint_set =~ :[[:space:]][[:lower:]] ]]
done
printf 'PASS config defaults/overrides/reload and responsive titles\n'
BASH
