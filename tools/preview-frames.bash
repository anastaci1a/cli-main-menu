#!/usr/bin/env bash
# Feed terminal frames to render-preview.cjs. This uses the real renderer and
# simulated menu state; it never opens tmux, Codex, or the user's job table.
set -eo pipefail
# Bash's substring operations must count UTF-8 characters, not bytes: the
# shimmer addresses individual cells, including the arrow glyphs in the hints.
utf8_locale=''
while IFS= read -r locale_name; do
  case ${locale_name,,} in
    c.utf8|c.utf-8) utf8_locale=$locale_name; break ;;
    en_us.utf8|en_us.utf-8) utf8_locale=$locale_name ;;
  esac
done < <(LC_ALL=C locale -a)
if [[ -z $utf8_locale ]]; then
  printf 'Preview generation requires a UTF-8 locale.\n' >&2
  exit 1
fi
export LC_ALL=$utf8_locale
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source -- "$cli_dir/init.bash"
EZ_MENU_TITLE=SATELLITE
COLUMNS=80 LINES=24 ez_stars_animated=1 menu_has_back=1 menu_exit_control=1 menu_back_focused=0
RANDOM=1967
title_rows=()
mapfile -t title_rows < <(ez_menu_title_rows)
mapfile -t fitted_rows <<< "$(ez_menu_banner 0 2)"
# Simulate availability without touching tmux, Codex, or live shell jobs. Read
# labels from the same menu definition as startup, so the preview follows edits.
ez_menu_has_codex() { return 0; }
ez_menu_codex_label() { printf 'Codex: Resume (cli-main-menu)'; }
codex-switcher() { :; }
ez_menu_define_items
labels=() menu_enabled=() menu_disabled_notes=()
for entry in "${menu_items[@]}"; do
  IFS='|' read -r label action behavior enabled_when disabled_note <<< "$entry"
  labels+=("$label")
  if [[ -n $enabled_when ]] && ! "$enabled_when"; then
    menu_enabled+=(0)
    menu_disabled_notes[${#labels[@]}-1]=$disabled_note
  else
    menu_enabled+=(1)
  fi
done
menu_layout_labels=("${labels[@]}")
original_labels=("${labels[@]}")
menu_accent_suffix=([1]=' (cli-main-menu)')
menu_layout_labels[1]='Codex: Resume'
visible=${#labels[@]}
enabled_count=0
for enabled in "${menu_enabled[@]}"; do enabled_count=$((enabled_count + enabled)); done
mapfile -t hint_rows < <(ez_menu_hint_lines main "$enabled_count")
read -r marker_width label_width option_block_width option_left option_right < <(ez_menu_option_layout "${menu_layout_labels[@]}")
ez_menu_draw_cached=1

declare -a stars_cells stars_fade stars_hue stars_sat stars_value
declare -A stars_char stars_palette stars_saturation stars_birth stars_seen stars_rgb_cache
declare -A stars_text_char stars_text_style stars_text_fade stars_text_seen
declare -A stars_text_flash stars_occluded
declare -A stars_hue_offset stars_cell_render stars_text_palette
ez_stars_init
ez_stars_layout "${#fitted_rows[@]}" 5 "${#title_rows[0]}" 2 "${#labels[@]}" 0 "${menu_layout_labels[@]}"
ez_stars_text_layout "${#fitted_rows[@]}" "${#title_rows[0]}" 2 0 0 1 "${labels[@]}"
ez_stars_build_work
# Keep the sample status date fixed so regenerating on another day is stable.
status_date='Mon Jan 01'
# Match the live 20 FPS target so short white/bold peaks survive the preview.
for ((elapsed = 0; elapsed <= 10000; elapsed += 50)); do
  ez_stars_tick "$elapsed"
  ez_stars_bar_color "$elapsed"
  printf -v clock '%02d:%02d:%02d' 10 15 "$((elapsed / 1000 % 60))"
  printf -v status_line ' %s  %s | satellite | ~/projects' "$status_date" "$clock"
  printf -v status_line '%-80.80s' "$status_line"
  frame=$(
    printf '\033[H%s%s%s%s\r\n' "$stars_bar_bg" "$C_WHITE" "$status_line" "$C_RESET"
    for ((screen_row = 2; screen_row <= ${#fitted_rows[@]} + 2; screen_row++)); do
      ez_stars_render_span "$screen_row" 0 "$COLUMNS"
      printf '\r\n'
    done
    ez_menu_draw 1 0 "$visible" "${labels[@]}"
    printf '\r\033[J'
  )
  printf '%s\0' "$frame"
done
