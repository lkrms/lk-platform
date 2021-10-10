#!/bin/bash

lk_command_first_existing() { lk_first_command "$@"; }
lk_confirm() { lk_tty_yn "$@"; }
lk_console_blank() { lk_tty_print; }
lk_console_detail_list() { lk_tty_list_detail - "$@"; }
lk_console_detail() { lk_tty_detail "$@"; }
lk_console_item() { lk_tty_print "$1" "$2" "${3-${_LK_TTY_COLOUR-$_LK_COLOUR}}"; }
lk_console_list() { lk_tty_list - "$@"; }
lk_console_message() { lk_tty_print "${1-}" "${3+$2}" "${3-${2-${_LK_TTY_COLOUR-$_LK_COLOUR}}}"; }
lk_console_read_secret() { local r && lk_tty_read_silent "$1" r "${@:2}" && echo "$r"; }
lk_console_read() { local r && lk_tty_read "$1" r "${@:2}" && echo "$r"; }
lk_echo_array() { lk_arr "$@"; }
lk_escape_ere_replace() { lk_sed_escape_replace "$@"; }
lk_escape_ere() { lk_sed_escape "$@"; }
lk_first_existing() { lk_first_file "$@"; }
lk_is_false() { lk_false "$@"; }
lk_is_true() { lk_true "$@"; }
lk_maybe_sudo() { lk_sudo "$@"; }
lk_myself() { local s=$? && { [[ ${1-} != -* ]] || _LK_STACK_DEPTH= lk_warn "-f not supported"; } && lk_pass -$s lk_script_name $((2 + ${_LK_STACK_DEPTH:-0})); }
lk_regex_implode() { lk_ere_implode_args -- "$@"; }

#### Reviewed: 2021-10-09
