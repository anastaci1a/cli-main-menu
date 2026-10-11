#!/bin/bash
# The array may not be mounted yet when /boot/config/go runs.
. /boot/config/cli-main-menu/settings.sh
export PATH="$CODEX_SWITCHER_BIN:$PATH"
export CODEX_HOME="${CODEX_HOME:-/mnt/user/appdata/codex/home}"
export CODEX_SWITCHER_HOME
for ((attempt=0; attempt<300; attempt++)); do
  if [[ -d /mnt/user/appdata && -x $CODEX_SWITCHER_BIN/codex-switcher &&
        -x /mnt/user/appdata/codex/bin/codex ]]; then
    "$CODEX_SWITCHER_BIN/codex-switcher" daemon start 2>&1 | logger -t codex-switcher-boot
    exit "${PIPESTATUS[0]}"
  fi
  sleep 2
done
logger -t codex-switcher-boot 'Array or installation unavailable; start with codex-switcher daemon start when ready.'
exit 1
