#!/bin/bash
set -e
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
