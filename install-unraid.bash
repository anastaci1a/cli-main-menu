#!/bin/bash
# Install persistent startup hooks without launching a UI in this shell.
set -euo pipefail
[[ $EUID == 0 && -f /etc/unraid-version ]] || {
  printf 'Run this installer as root on Unraid.\n' >&2; exit 1;
}
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
switcher_bin=${CODEX_SWITCHER_BIN:-/mnt/user/live/packages/codex-switcher/bin}
switcher_home=${CODEX_SWITCHER_HOME:-/mnt/user/appdata/codex-switcher}
herdr_bin=${HERDR_BIN_DIR:-/mnt/user/live/packages/herdr/bin}
herdr_data=${HERDR_DATA_DIR:-/mnt/user/appdata/herdr}
[[ $cli_dir == /mnt/* && $switcher_bin == /mnt/* && $switcher_home == /mnt/* ]] || {
  printf 'Use persistent absolute /mnt paths for the menu, binary, and data.\n' >&2; exit 1;
}
[[ $herdr_bin == /mnt/* && $herdr_data == /mnt/* ]] || {
  printf 'Use persistent absolute /mnt paths for Herdr binary and data.\n' >&2; exit 1;
}
destination=/boot/config/cli-main-menu
install -d -m 700 "$destination"
install -d -m 700 "$herdr_data"
for file in go; do
  [[ -f $destination/$file.before-install ]] || cp -p "/boot/config/$file" "$destination/$file.before-install"
done
for file in .bashrc .bash_profile; do
  [[ -f $destination/$file.before-install ]] || cp -p "/root/$file" "$destination/$file.before-install"
done
for file in profile.sh login.bash restore.sh start-switcher.sh; do
  install -m 600 "$cli_dir/unraid/$file" "$destination/$file"
done
{
  printf 'CLI_MAIN_MENU_DIR=%q\n' "$cli_dir"
  printf 'CODEX_SWITCHER_BIN=%q\n' "$switcher_bin"
  printf 'CODEX_SWITCHER_HOME=%q\n' "$switcher_home"
  printf 'HERDR_BIN_DIR=%q\n' "$herdr_bin"
  printf 'HERDR_DATA_DIR=%q\n' "$herdr_data"
} > "$destination/settings.sh"
chmod 600 "$destination/settings.sh"
if ! grep -qF '# Persistent CLI main menu and Codex Switcher' /boot/config/go; then
  cat >> /boot/config/go <<'BOOT'

# Persistent CLI main menu and Codex Switcher
/bin/bash /boot/config/cli-main-menu/restore.sh
nohup /bin/bash /boot/config/cli-main-menu/start-switcher.sh >/dev/null 2>&1 &
BOOT
fi
/bin/bash "$destination/restore.sh"
printf 'Installed. Run source ~/.bashrc, then startup. Interactive logins open the menu automatically.\n'
