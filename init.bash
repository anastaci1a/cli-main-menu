#!/usr/bin/env bash
# Source this entry point from .bashrc; sourcing defines commands but opens no UI.

_ez_cli_load() {
  local cli_dir
  cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || return
  source -- "$cli_dir/theme.bash" || return
  source -- "$cli_dir/config.example.bash" || return
  if [[ -f $cli_dir/config.bash ]]; then
    source -- "$cli_dir/config.bash" || return
  fi
  source -- "$cli_dir/font.bash" || return
  source -- "$cli_dir/render.bash" || return
  source -- "$cli_dir/stars.bash" || return
  source -- "$cli_dir/actions.bash" || return
  source -- "$cli_dir/select.bash" || return
  source -- "$cli_dir/menu.bash" || return
  alias startup='clear && ez_select'
}

if _ez_cli_load; then
  unset -f _ez_cli_load
else
  unset -f _ez_cli_load
  return 1
fi
