#!/bin/bash

lk_command_first_existing() { lk_first_command "$@"; }
lk_confirm() { lk_tty_yn "$@"; }
lk_console_blank() { lk_tty_print; }
lk_console_detail_diff() { lk_tty_diff_detail "$@"; }
lk_console_detail_file() { lk_tty_file_detail "$@"; }
lk_console_detail_list() { lk_tty_list_detail - "$@"; }
lk_console_detail() { lk_tty_detail "$@"; }
lk_console_diff() { lk_tty_diff "$@"; }
lk_console_item() { lk_tty_print "$1" "$2" "${3-${_LK_TTY_COLOUR-$_LK_COLOUR}}"; }
lk_console_list() { lk_tty_list - "$@"; }
lk_console_message() { lk_tty_print "${1-}" "${3+$2}" "${3-${2-${_LK_TTY_COLOUR-$_LK_COLOUR}}}"; }
lk_console_read_secret() { local IFS r && unset IFS && lk_tty_read_silent "$1" r "${@:2}" && echo "$r"; }
lk_console_read() { local IFS r && unset IFS && lk_tty_read "$1" r "${@:2}" && echo "$r"; }
lk_echo_array() { lk_arr "$@"; }
lk_elevate_if_error() { lk_elevate -f "$@"; }
lk_escape_ere_replace() { lk_sed_escape_replace "$@"; }
lk_escape_ere() { lk_sed_escape "$@"; }
lk_first_existing() { lk_first_file "$@"; }
lk_include() { lk_require "$@"; }
lk_is_false() { lk_false "$@"; }
lk_is_true() { lk_true "$@"; }
lk_maybe_sudo() { lk_sudo "$@"; }
lk_regex_implode() { lk_ere_implode_args -- "$@"; }
lk_run_detail() { lk_tty_run_detail "$@"; }
lk_run() { lk_tty_run "$@"; }
lk_tty_detail_pairs() { lk_tty_pairs_detail "$@"; }

#### Reviewed: 2021-10-15
