#!/usr/bin/env bash
# Five-row block lettering. Unmapped characters use a plain-text title.

function ez_menu_title_text() {
  local title=${EZ_MENU_TITLE:-MAIN MENU}
  # A title occupies one logical line and must not inject terminal controls.
  title=${title//[[:cntrl:]]/ }
  printf '%s' "$title"
}

function ez_menu_title_rows() {
  local title char glyph row index
  title=$(ez_menu_title_text)
  title=${title^^}
  local -a rows=('' '' '' '' '') parts
  local -A font=(
    [A]=' ### |#   #|#####|#   #|#   #'
    [B]='#### |#   #|#### |#   #|#### '
    [C]=' ####|#    |#    |#    | ####'
    [D]='#### |#   #|#   #|#   #|#### '
    [E]='#####|#    |#### |#    |#####'
    [F]='#####|#    |#### |#    |#    '
    [G]=' ####|#    |# ###|#   #| ####'
    [H]='#   #|#   #|#####|#   #|#   #'
    [I]='#####|  #  |  #  |  #  |#####'
    [J]='#####|   # |   # |#  # | ##  '
    [K]='#   #|#  # |###  |#  # |#   #'
    [L]='#    |#    |#    |#    |#####'
    [M]='#   #|## ##|# # #|#   #|#   #'
    [N]='#   #|##  #|# # #|#  ##|#   #'
    [O]=' ### |#   #|#   #|#   #| ### '
    [P]='#### |#   #|#### |#    |#    '
    [Q]=' ### |#   #|#   #|#  ##| ####'
    [R]='#### |#   #|#### |#  # |#   #'
    [S]='#####|#    |#####|    #|#####'
    [T]='#####|  #  |  #  |  #  |  #  '
    [U]='#   #|#   #|#   #|#   #| ### '
    [V]='#   #|#   #|#   #| # # |  #  '
    [W]='#   #|#   #|# # #|## ##|#   #'
    [X]='#   #| # # |  #  | # # |#   #'
    [Y]='#   #| # # |  #  |  #  |  #  '
    [Z]='#####|   # |  #  | #   |#####'
    [0]=' ### |#  ##|# # #|##  #| ### '
    [1]='  #  | ##  |  #  |  #  |#####'
    [2]='#### |    #| ### |#    |#####'
    [3]='#### |    #| ### |    #|#### '
    [4]='#   #|#   #|#####|    #|    #'
    [5]='#####|#    |#### |    #|#### '
    [6]=' ### |#    |#### |#   #| ### '
    [7]='#####|    #|   # |  #  |  #  '
    [8]=' ### |#   #| ### |#   #| ### '
    [9]=' ### |#   #| ####|    #| ### '
    [' ']='   |   |   |   |   '
    ['-']='     |     |#####|     |     '
  )
  for ((index = 0; index < ${#title}; index++)); do
    char=${title:index:1}
    glyph=${font[$char]-}
    if [[ -z $glyph ]]; then
      ez_menu_title_text
      printf '\n'
      return
    fi
    IFS='|' read -r -a parts <<< "$glyph"
    for ((row = 0; row < 5; row++)); do
      (( index > 0 )) && rows[row]+=' '
      rows[row]+=${parts[row]}
    done
  done
  printf '%s\n' "${rows[@]}"
}
