#!/usr/bin/env bash
# Actions run in the calling shell so fg sees its actual jobs.

function ez_menu_terminal() {
  printf '  %sReady when you are.%s\n\n' "$C_GREEN" "$C_RESET"
}

function ez_menu_codex_label() {
  if tmux has-session -t '=codex' 2>/dev/null; then
    printf 'Resume Codex'
  else
    printf 'Start Codex'
  fi
}

function ez_menu_codex() {
  # Recheck in case the session changed while the menu was open.
  if tmux has-session -t '=codex' 2>/dev/null; then
    clear
    cxr
    return $?
  fi

  local start_dir resolved_dir
  local dir_prompt="  ${C_PINK}Start directory > ${C_RESET}"
  while :; do
    if ! IFS= read -e -r -p "$dir_prompt" start_dir; then
      printf '\n'
      return 130
    fi
    case $start_dir in
      '~') start_dir=$HOME ;;
      '~/'*) start_dir="$HOME/${start_dir:2}" ;;
    esac
    if [[ -z $start_dir ]] || ! resolved_dir=$(CDPATH='' cd -P -- "$start_dir" 2>/dev/null && pwd -P); then
      printf '\n  %sEnter an existing, accessible directory.%s\n\n' "$C_RED" "$C_RESET" >&2
      continue
    fi
    break
  done
  clear
  tmux new-session -A -s codex -c "$resolved_dir" 'codex --dangerously-bypass-approvals-and-sandbox'
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
  banner=$'\n'"  ${C_PINK}${C_BOLD}JOB $job_id${C_RESET}"$'\n'"  ${C_WHITE}${job_label:0:label_width}${C_RESET}"
  if ! selected=$(ez_menu_choose 0 "$banner" 'Switch to job' 'Terminate job' 'Back'); then
    return 0
  fi
  printf '\n'
  case $selected in
    0)
      # fg resumes suspended jobs and gives them control of this terminal.
      builtin fg "%$job_id" || :
      ;;
    1) ez_menu_terminate_job "$job_id" ;;
  esac
}

function ez_menu_jobs() {
  local selected=0 job_output line job_id banner
  local job_pattern='^\[([0-9]+)\][+-]?[[:space:]]+(.*)$'
  local -a job_ids job_labels
  banner=$'\n'"  ${C_PINK}${C_BOLD}SHELL JOBS${C_RESET}"
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
    job_labels+=('Terminate all jobs' 'Back')
    (( selected >= ${#job_labels[@]} )) && selected=0
    if ! selected=$(ez_menu_choose "$selected" "$banner" "${job_labels[@]}"); then
      return 0
    fi
    printf '\n'
    if (( selected < ${#job_ids[@]} )); then
      ez_menu_job_actions "${job_ids[selected]}" "${job_labels[selected]}"
    elif (( selected == ${#job_ids[@]} )); then
      for job_id in "${job_ids[@]}"; do
        ez_menu_terminate_job "$job_id"
      done
    else
      return 0
    fi
  done
}
