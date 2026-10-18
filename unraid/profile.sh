# Restored into /etc/profile.d on every Unraid boot. Sourcing never starts a UI.
if [ -r /boot/config/cli-main-menu/settings.sh ]; then
  . /boot/config/cli-main-menu/settings.sh
  HERDR_BIN_DIR="${HERDR_BIN_DIR:-/mnt/user/live/packages/herdr/bin}"
  HERDR_DATA_DIR="${HERDR_DATA_DIR:-/mnt/user/appdata/herdr}"
  HERDR_CONFIG_PATH="${HERDR_CONFIG_PATH:-$HERDR_DATA_DIR/config.toml}"
  case ":$PATH:" in
    *:"$HERDR_BIN_DIR":*) ;;
    *) PATH="$HERDR_BIN_DIR:$PATH" ;;
  esac
  case ":$PATH:" in
    *:"$CODEX_SWITCHER_BIN":*) ;;
    *) PATH="$CODEX_SWITCHER_BIN:$PATH" ;;
  esac
  export PATH CLI_MAIN_MENU_DIR CODEX_SWITCHER_HOME
  export HERDR_BIN_DIR HERDR_DATA_DIR HERDR_CONFIG_PATH
  export CODEX_HOME="${CODEX_HOME:-/mnt/user/appdata/codex/home}"
  if [ -n "${BASH_VERSION:-}" ] && [ -r "$CLI_MAIN_MENU_DIR/init.bash" ]; then
    . "$CLI_MAIN_MENU_DIR/init.bash"
  fi
fi
