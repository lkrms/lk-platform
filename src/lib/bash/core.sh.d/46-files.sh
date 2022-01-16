#!/bin/bash

# lk_dir_is_empty [DIR]
#
# Return true if DIR is empty.
function lk_dir_is_empty() {
  ! lk_sudo ls -A "$1" 2>/dev/null | grep . >/dev/null &&
    [ "${PIPESTATUS[0]}${PIPESTATUS[1]}" = 01 ]
}

# lk_file_maybe_move OLD_PATH CURRENT_PATH
#
# If OLD_PATH exists and CURRENT_PATH doesn't, move OLD_PATH to CURRENT_PATH.
function lk_file_maybe_move() {
  lk_sudo -f test ! -e "$1" ||
    lk_sudo -f test -e "$2" || {
    lk_sudo mv -nv "$1" "$2" &&
      LK_FILE_NO_CHANGE=0
  }
}

# lk_file_list_duplicates [DIR]
#
# Print a list of files in DIR or the current directory that would be considered
# duplicates on a case-insensitive filesystem. Only useful on case-sensitive
# filesystems.
function lk_file_list_duplicates() {
  find "${1:-.}" -print0 | sort -zf | gnu_uniq -zDi | tr '\0' '\n'
}
