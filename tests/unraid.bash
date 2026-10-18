#!/bin/bash
set -euo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture=$(mktemp -d /tmp/menu-unraid.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/boot/config/cli-main-menu" "$fixture/root" "$fixture/etc/profile.d" "$fixture/menu with spaces"
cp "$cli_dir/"*.bash "$fixture/menu with spaces/"
for file in restore.sh profile.sh login.bash; do
  sed "s|/boot/config|$fixture/boot/config|g; s|/etc/profile.d|$fixture/etc/profile.d|g; s|/root/|$fixture/root/|g" \
    "$cli_dir/unraid/$file" > "$fixture/boot/config/cli-main-menu/$file"
done
printf 'original_function() { :; }\n' > "$fixture/root/.bashrc"
printf '# Original login configuration\n' > "$fixture/root/.bash_profile"
{
  printf 'CLI_MAIN_MENU_DIR=%q\n' "$fixture/menu with spaces"
  printf 'CODEX_SWITCHER_BIN=%q\n' "$fixture/bin with spaces"
  printf 'CODEX_SWITCHER_HOME=%q\n' "$fixture/appdata/codex-switcher"
  printf 'HERDR_BIN_DIR=%q\n' "$fixture/herdr bin"
  printf 'HERDR_DATA_DIR=%q\n' "$fixture/appdata/herdr"
} > "$fixture/boot/config/cli-main-menu/settings.sh"
bash "$fixture/boot/config/cli-main-menu/restore.sh"
bash "$fixture/boot/config/cli-main-menu/restore.sh"
[[ $(grep -cF '# BEGIN persistent CLI main menu login' "$fixture/root/.bash_profile") == 1 ]]
[[ $(grep -cF '# Persistent CLI main menu environment' "$fixture/root/.bashrc") == 1 ]]
bash --noprofile --norc -s -- "$fixture" <<'BASH'
fixture=$1
before=$PWD
options=$(set +o)
source "$fixture/root/.bashrc"
source "$fixture/root/.bashrc"
[[ $PWD == "$before" && $(set +o) == "$options" ]] || exit 1
declare -F original_function ez_select >/dev/null || exit 1
[[ $(alias startup) == "alias startup='clear && ez_select'" ]] || exit 1
[[ $CODEX_SWITCHER_HOME == "$fixture/appdata/codex-switcher" ]] || exit 1
[[ $HERDR_CONFIG_PATH == "$fixture/appdata/herdr/config.toml" ]] || exit 1
[[ $(readlink "$fixture/root/.config/herdr") == "$fixture/appdata/herdr" ]] || exit 1
[[ $PATH == *":$fixture/herdr bin:"* ]] || exit 1
[[ $PATH != *"$fixture/herdr bin:"*"$fixture/herdr bin:"* ]] || exit 1
[[ $PATH == "$fixture/bin with spaces:"* ]] || exit 1
[[ $PATH != *"$fixture/bin with spaces:"*"$fixture/bin with spaces:"* ]] || exit 1
ez_select() { echo 'Unexpected UI launch' >&2; return 99; }
source "$fixture/root/.bash_profile"
BASH
printf 'PASS boot-hook restoration, idempotence, paths with spaces and source-only loading\n'
