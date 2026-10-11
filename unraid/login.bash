# BEGIN persistent CLI main menu login
# .bashrc can source this file; only a direct interactive login opens the menu.
if [[ $- == *i* && -t 0 && -t 1 && -z ${TMUX:-} &&
      ${#BASH_SOURCE[@]} -eq 1 && -z ${CLI_MAIN_MENU_STARTED:-} ]] &&
   declare -F ez_select >/dev/null; then
  CLI_MAIN_MENU_STARTED=1
  clear
  ez_select
fi
# END persistent CLI main menu login
