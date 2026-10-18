#!/bin/bash
set -e
. /boot/config/cli-main-menu/settings.sh
herdr_data_dir=${HERDR_DATA_DIR:-/mnt/user/appdata/herdr}
# The array may not be mounted yet at boot; restore the link without creating
# directories under /mnt/user before Unraid mounts the persistent storage.
install -d /root/.config
if [ ! -e /root/.config/herdr ] && [ ! -L /root/.config/herdr ]; then
  ln -s "$herdr_data_dir" /root/.config/herdr
fi
install -m 755 /boot/config/cli-main-menu/profile.sh /etc/profile.d/cli-main-menu.sh
if ! grep -qF '# BEGIN persistent CLI main menu login' /root/.bash_profile; then
  cat /boot/config/cli-main-menu/login.bash >> /root/.bash_profile
fi
# Interactive non-login shells also get the alias. This opens no UI.
if ! grep -qF '# Persistent CLI main menu environment' /root/.bashrc; then
  cat >> /root/.bashrc <<'BASHRC'

# Persistent CLI main menu environment
[ ! -r /etc/profile.d/cli-main-menu.sh ] || . /etc/profile.d/cli-main-menu.sh
BASHRC
fi
