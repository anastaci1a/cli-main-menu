#!/usr/bin/env bash
# Actions run in the calling shell so fg sees its actual jobs.

function ez_menu_terminal() {
  printf '  %sReady when you are.%s\n\n' "$C_GREEN" "$C_RESET"
}

function ez_menu_codex_monitor_available() {
  command -v codex-switcher >/dev/null 2>&1 && command -v tmux >/dev/null 2>&1
}

function ez_menu_codex_switching_available() {
  command -v codex-switcher >/dev/null 2>&1 && codex-switcher ready >/dev/null 2>&1
}

function ez_menu_unavailable() { return 1; }

function ez_menu_codex_monitor() {
  ez_menu_codex_monitor_available || return 1
  local target='=codex-switcher' result
  local -a environment=(-e "PATH=$PATH")
  [[ ! ${CODEX_SWITCHER_HOME+x} ]] || environment+=(-e "CODEX_SWITCHER_HOME=$CODEX_SWITCHER_HOME")
  if ! tmux has-session -t "$target" 2>/dev/null; then
    tmux new-session -d -s codex-switcher "${environment[@]}" 'codex-switcher ui' ||
      tmux has-session -t "$target" 2>/dev/null || return 1
  fi
  if [[ -n ${TMUX:-} ]]; then
    tmux switch-client -t "$target"
  else
    (( ${ez_menu_shared_screen:-0} )) && printf '\033[?1004l\033[0m\033[?25h\033[?1049l' >&2
    tmux attach-session -t "$target"
    result=$?
    (( ${ez_menu_shared_screen:-0} )) && printf '\033[?1049h\033[?25l' >&2
    return "$result"
  fi
}

function ez_menu_has_stopped_jobs() {
  [[ -n $(jobs -sp) ]]
}

function ez_menu_terminate_job() {
  local job_spec="%$1"
  if builtin kill -TERM "$job_spec" 2>/dev/null; then
    # A stopped process must continue before it can handle SIGTERM.
    builtin kill -CONT "$job_spec" 2>/dev/null || :
    printf '  %sTermination requested for job %s.%s\n' "$C_ORANGE" "$job_spec" "$C_RESET"
  else
    printf '  %sJob %s has already finished or could not be terminated.%s\n' "$C_RED" "$job_spec" "$C_RESET" >&2
  fi
}

function ez_menu_job_actions() {
  local job_id=$1 job_label=$2 selected banner
  local label_width=$(( ${COLUMNS:-80} - 4 ))
  (( label_width < 1 )) && label_width=1
  job_label=${job_label#*] }
  banner="JOB $job_id: ${job_label:0:label_width}"
  if ! selected=$(ez_menu_choose 0 '' --screen-title "$banner" -- 'Switch to job' 'Terminate job'); then
    return 0
  fi
  printf '\n'
  case $selected in
    0)
      # fg resumes suspended jobs and gives them control of this terminal.
      (( ${ez_menu_shared_screen:-0} )) && printf '\033[?1004l\033[0m\033[?25h\033[?1049l' >&2
      builtin fg "%$job_id" || :
      (( ${ez_menu_shared_screen:-0} )) && printf '\033[?1049h\033[?25l' >&2
      ;;
    1) ez_menu_terminate_job "$job_id" ;;
  esac
}

function ez_menu_jobs() {
  local selected=0 job_output line job_id banner
  local job_pattern='^\[([0-9]+)\][+-]?[[:space:]]+(.*)$'
  local -a job_ids job_labels
  banner='SHELL JOBS'
  while :; do
    job_ids=() job_labels=()
    # Bash copies its job table into command substitutions; no external ps scan.
    job_output=$(jobs -r; jobs -s)
    while IFS= read -r line; do
      if [[ $line =~ $job_pattern ]]; then
        job_ids+=("${BASH_REMATCH[1]}")
        job_labels+=("[${BASH_REMATCH[1]}] ${BASH_REMATCH[2]}")
      fi
    done <<< "$job_output"
    if (( ${#job_ids[@]} == 0 )); then
      printf '  %sNo active jobs in this shell.%s\n\n' "$C_STAR_LAVENDER" "$C_RESET"
      return 0
    fi
    job_labels+=('Terminate all jobs')
    (( selected >= ${#job_labels[@]} )) && selected=0
    if ! selected=$(ez_menu_choose "$selected" '' --screen-title "$banner" -- "${job_labels[@]}"); then
      return 0
    fi
    printf '\n'
    if (( selected < ${#job_ids[@]} )); then
      ez_menu_job_actions "${job_ids[selected]}" "${job_labels[selected]}"
    elif (( selected == ${#job_ids[@]} )); then
      for job_id in "${job_ids[@]}"; do
        ez_menu_terminate_job "$job_id"
      done
    fi
  done
}
