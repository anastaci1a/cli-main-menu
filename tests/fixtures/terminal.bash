#!/usr/bin/env bash
shopt -s expand_aliases
source -- "$EZ_CLI_BASHRC"
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
    has-session) [[ ${TEST_SESSION:-absent} == present ]] ;;
    attach) printf 'ATTACHED_CODEX\n' ;;
    new-session) printf 'CREATED:'; printf '<%s>' "$@"; printf '\n' ;;
  esac
}
case $1 in
  menu)
    ez_select
    ;;
  chooser|static)
    [[ $1 == static ]] && EZ_MENU_ANIMATE_STARS=0
    selected=$(ez_menu_choose 0 "$(ez_menu_banner)" One Two Three)
    printf 'SELECTED=%s STATUS=%s\n' "$selected" "$?"
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
