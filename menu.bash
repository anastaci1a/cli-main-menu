#!/usr/bin/env bash
# Main menu definition: customize menu_items below.

function ez_select() {
  local ez_codex_start_dir=$PWD
  local ez_menu_shared_screen=0
  local selected=0 label action behavior status banner entry enabled_when disabled_indices disabled_note
  local -a menu_items menu_labels menu_actions menu_behaviors menu_availability menu_choice_args
  if [[ -t 0 && -t 2 && ${TERM:-dumb} != dumb ]]; then
    ez_menu_shared_screen=1
    printf '\033[?1049h\033[?25l' >&2
  fi
  banner=$(ez_menu_banner)
  while :; do
    # CUSTOMIZE HERE: 'Label|action_function|close_or_stay|optional_enabled_check|optional_disabled_note'.
    # Add/reorder/remove rows; numbering, alignment, scrolling, and star fade
    # adjust automatically. No option counts or widths need updating elsewhere.
    # Use command substitution for labels that depend on current state.
    menu_items=('New Terminal|ez_menu_terminal|close')
    if ez_menu_has_codex; then
      menu_items+=("$(ez_menu_codex_label)|ez_menu_codex|stay" 'Codex: Sessions|ez_menu_codex_sessions|stay')
    else
      menu_items+=('Codex: New Session|ez_codex_new|stay')
    fi
    menu_items+=('Codex Switcher: Dashboard|ez_menu_codex_monitor|stay|ez_menu_codex_monitor_available|(unavailable)')
    if command -v codex-switcher >/dev/null 2>&1 && ! ez_menu_codex_switching_available; then
      menu_items+=('Automatic Account Switching|:|stay|ez_menu_unavailable|(unavailable)')
    fi
    menu_items+=('Jobs|ez_menu_jobs|stay|ez_menu_has_stopped_jobs|(no stopped jobs)' 'Exit|exit|close')
    menu_labels=() menu_actions=() menu_behaviors=() menu_availability=() menu_choice_args=()
    disabled_indices=''
    for entry in "${menu_items[@]}"; do
      IFS='|' read -r label action behavior enabled_when disabled_note <<< "$entry"
      if [[ -n $enabled_when ]] && ! "$enabled_when"; then
        disabled_indices+="${#menu_labels[@]} "
        if [[ -n $disabled_note ]]; then
          menu_choice_args+=(--disabled-note "${#menu_labels[@]}" "$disabled_note")
        fi
      fi
      menu_labels+=("$label")
      menu_actions+=("$action")
      menu_behaviors+=("$behavior")
      menu_availability+=("$enabled_when")
    done
    if ! selected=$(ez_menu_choose "$selected" "$banner" --disabled "$disabled_indices" "${menu_choice_args[@]}" -- "${menu_labels[@]}"); then
      (( ez_menu_shared_screen )) && printf '\033[?1004l\033[0m\033[?25h\033[?1049l' >&2
      printf '\n'
      return
    fi
    label=${menu_labels[selected]}
    action=${menu_actions[selected]}
    behavior=${menu_behaviors[selected]}
    enabled_when=${menu_availability[selected]}
    # A job may have finished or resumed while the selector was open.
    if [[ -n $enabled_when ]] && ! "$enabled_when"; then continue; fi
    if [[ $action == exit ]]; then
      (( ez_menu_shared_screen )) && printf '\033[?1004l\033[0m\033[?25h\033[?1049l' >&2
      exit
    fi
    if [[ $behavior == close && $ez_menu_shared_screen == 1 ]]; then
      printf '\033[?1004l\033[0m\033[?25h\033[?1049l' >&2
      ez_menu_shared_screen=0
    fi
    printf '\n'
    if "$action"; then
      if [[ $behavior == close ]]; then
        return 0
      fi
    else
      status=$?
      if [[ $behavior == close && $ez_menu_shared_screen == 0 && -t 0 && -t 2 && ${TERM:-dumb} != dumb ]]; then
        ez_menu_shared_screen=1
        printf '\033[?1049h\033[?25l' >&2
      fi
      if (( status == 130 )); then
        (( ez_menu_shared_screen )) && printf '\033[?1004l\033[0m\033[?25h\033[?1049l' >&2
        return 0
      fi
      printf '  %s%s failed (status %d). Please try again.%s\n\n' "$C_RED" "$label" "$status" "$C_RESET" >&2
    fi
  done
}
