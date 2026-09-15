#!/usr/bin/env bash
# Main menu definition: customize menu_items below.

function ez_select() {
  local selected=0 label action behavior status banner entry enabled_when disabled_indices disabled_note
  local -a menu_items menu_labels menu_actions menu_behaviors menu_availability menu_choice_args
  banner=$(ez_menu_banner)
  while :; do
    # CUSTOMIZE HERE: 'Label|action_function|close_or_stay|optional_enabled_check|optional_disabled_note'.
    # Add/reorder/remove rows; numbering, alignment, scrolling, and star fade
    # adjust automatically. No option counts or widths need updating elsewhere.
    # Use command substitution for labels that depend on current state.
    menu_items=(
      'New Terminal|ez_menu_terminal|close'
      "$(ez_menu_codex_label)|ez_menu_codex|close"
      'Jobs|ez_menu_jobs|stay|ez_menu_has_stopped_jobs|(no stopped jobs)'
      'Exit|exit|close'
    )
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
      printf '\n'
      return
    fi
    label=${menu_labels[selected]}
    action=${menu_actions[selected]}
    behavior=${menu_behaviors[selected]}
    enabled_when=${menu_availability[selected]}
    # A job may have finished or resumed while the selector was open.
    if [[ -n $enabled_when ]] && ! "$enabled_when"; then continue; fi
    printf '\n'
    if "$action"; then
      [[ $behavior == close ]] && return 0
    else
      status=$?
      (( status == 130 )) && return 0
      printf '  %s%s failed (status %d). Please try again.%s\n\n' "$C_RED" "$label" "$status" "$C_RESET" >&2
    fi
  done
}
