#!/usr/bin/env bash
shopt -s expand_aliases
source -- "$EZ_CLI_BASHRC"
# The installed switcher must never be contacted by terminal tests.
PATH=/usr/bin:/bin
[[ $1 == switcher_tmux ]] || TMUX=''
if [[ $1 == switcher_menu || $1 == switcher_ready || $1 == switcher_tmux ]]; then
  codex-switcher() {
    case $1 in
      ready)
        printf 'READY\n' >> "$TEST_SWITCHER_LOG"
        return "${TEST_SWITCHER_READY:-1}"
        ;;
      *) printf 'UNEXPECTED_SWITCHER_COMMAND:%s\n' "$1" >> "$TEST_SWITCHER_LOG"; return 99 ;;
    esac
  }
fi
# Keep visual expectations independent of personal configuration.
EZ_MENU_TITLE=SATELLITE
EZ_MENU_ANIMATE_STARS=1
EZ_MENU_SWEEP_INTERVAL_MS=4000 EZ_MENU_SWEEP_DURATION_MS=1000 EZ_MENU_SWEEP_HUE_STEP=70
EZ_MENU_STAR_SATURATION_MAX=800 EZ_MENU_SWEEP_ACCENT_OFFSET=180
EZ_MENU_STAR_HUE_SPREAD=60
COLUMNS=80
LINES=24
clear() { :; }
tmux() {
  case $1 in
    list-sessions)
      if [[ -n ${TEST_MONITOR_FILE:-} && -s $TEST_MONITOR_FILE ]]; then
        printf '$9|codex-switcher|100|200|\n'
      fi
      if [[ -n ${TEST_SESSION_FILE:-} && -s $TEST_SESSION_FILE ]]; then
        IFS= read -r test_name < "$TEST_SESSION_FILE"
        printf '$0|%s|100|200|\n' "$test_name"
      fi
      ;;
    has-session)
      if [[ ${3-} == '=codex-switcher' ]]; then
        [[ -n ${TEST_MONITOR_FILE:-} && -s $TEST_MONITOR_FILE ]]
      else
        [[ -n ${TEST_SESSION_FILE:-} && -s $TEST_SESSION_FILE ]]
      fi
      ;;
    set-option) : ;;
    attach-session)
      if [[ ${3-} == '=codex-switcher' ]]; then printf 'MONITOR_ATTACHED\n'
      else printf 'ATTACHED_CODEX\n'; fi
      ;;
    switch-client) printf 'MONITOR_SWITCHED\n' ;;
    new-session)
      printf 'CREATED:' >&2; printf '<%s>' "$@" >&2; printf '\n' >&2
      local arg prev='' name=''
      for arg in "$@"; do
        [[ $prev == -s ]] && name=$arg
        prev=$arg
      done
      if [[ $name == codex-switcher ]]; then
        printf '%s\n' "$name" > "$TEST_MONITOR_FILE"
        printf 'MONITOR_CREATED\n'
        return
      fi
      printf '%s\n' "$name" > "$TEST_SESSION_FILE"
      printf '$0\n'
      ;;
  esac
}
case $1 in
  menu|switcher_menu|switcher_ready|switcher_tmux)
    ez_select
    ;;
  chooser|static|input_echo)
    [[ $1 == static ]] && EZ_MENU_ANIMATE_STARS=0
    if [[ $1 == input_echo ]]; then
      # Give the PTY driver a deterministic interval outside Bash's read -s.
      ez_menu_status_text() {
        printf 'INPUT_WINDOW\n' >&2
        sleep 0.25
        printf 'Input echo test'
      }
    fi
    saved_modes=$(stty -g)
    selected=$(ez_menu_choose 0 "$(ez_menu_banner)" One Two Three)
    printf 'SELECTED=%s STATUS=%s\n' "$selected" "$?"
    [[ $(stty -g) == "$saved_modes" ]] || { printf 'TTY_MODE_MISMATCH\n'; exit 1; }
    printf 'TTY_RESTORED\n'
    ;;
  submenu_geometry)
    EZ_MENU_ANIMATE_STARS=0
    selected=$(ez_menu_choose 0 '' --screen-title 'GEOMETRY' -- Short 'A considerably longer option')
    printf 'SELECTED=%s STATUS=%s\n' "$selected" "$?"
    ;;
  main_geometry)
    EZ_MENU_ANIMATE_STARS=0
    selected=$(ez_menu_choose 0 "$(ez_menu_banner)" --disabled '3' --disabled-note 3 '(no stopped jobs)' -- \
      'New Terminal' 'Codex: Resume (This is a longer session)' 'Codex: Sessions' Jobs Exit)
    printf 'SELECTED=%s STATUS=%s\n' "$selected" "$?"
    ;;
  duration)
    now=$(printf '%(%s)T' -1)
    selected=$(ez_menu_choose 1 '' --screen-title 'Codex: Sessions' --live-duration 1 "$((now-5))" ' (' selected -- '[new session]' Alpha)
    printf 'SELECTED=%s STATUS=%s\n' "$selected" "$?"
    ;;
  duration_static)
    EZ_MENU_ANIMATE_STARS=0
    now=$(printf '%(%s)T' -1)
    selected=$(ez_menu_choose 1 '' --screen-title 'Codex: Sessions' --live-duration 1 "$((now-5))" ' (' selected -- '[new session]' Alpha)
    printf 'SELECTED=%s STATUS=%s\n' "$selected" "$?"
    ;;
  name_cursor)
    name=$(ez_codex_field 'Session name' '')
    printf 'NAME=%s STATUS=%s\n' "$name" "$?"
    ;;
  path_root)
    path=$(ez_codex_field 'Start directory' '/')
    printf 'PATH=%s STATUS=%s\n' "$path" "$?"
    ;;
  path_root_child)
    path=$(ez_codex_field 'Start directory' '/tm')
    status=$?
    [[ $path == /tmp && -d $path ]] && valid=1 || valid=0
    printf 'PATH=%s STATUS=%s VALID=%s\n' "$path" "$status" "$valid"
    ;;
  path_create)
    path=$(ez_codex_field 'Start directory' "$TEST_PATH_INPUT")
    status=$?
    [[ -d $path ]] && exists=1 || exists=0
    printf 'PATH=%s STATUS=%s EXISTS=%s\n' "$path" "$status" "$exists"
    ;;
  many)
    LINES=12
    items=()
    for ((n=1;n<=30;n++)); do items+=("Option $n"); done
    selected=$(ez_menu_choose 0 "$(ez_menu_banner)" "${items[@]}")
    printf 'SELECTED=%s STATUS=%s\n' "$selected" "$?"
    ;;
  jobs)
    sleep 120 &
    first_pid=$!
    sleep 120 &
    second_pid=$!
    kill -STOP %1 %2
    sleep 0.1
    trap 'kill -KILL "$first_pid" "$second_pid" 2>/dev/null; wait 2>/dev/null' EXIT
    ez_menu_jobs
    printf 'JOBS_AFTER:'
    jobs -r
    jobs -s
    ;;
  foreground)
    bash -c 'kill -STOP $$; printf "JOB_RESUMED_SUCCESSFULLY\n"' &
    first_pid=$!
    sleep 0.1
    trap 'kill -KILL "$first_pid" 2>/dev/null; wait 2>/dev/null' EXIT
    ez_menu_jobs
    ;;
esac
printf 'TEST_DONE\n'
