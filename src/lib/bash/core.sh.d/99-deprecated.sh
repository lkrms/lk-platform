#!/bin/bash

lk_confirm() { lk_tty_yn "$@"; }
lk_delete_on_exit_withdraw() { lk_on_exit_undo_delete "$@"; }
lk_echo_args() { lk_args "$@"; }
lk_echo_array() { lk_arr "$@"; }
lk_ellipsis() { lk_ellipsise "$@"; }
lk_escape_ere_replace() { lk_sed_escape_replace "$@"; }
lk_escape_ere() { lk_sed_escape "$@"; }
lk_file_security() { lk_file_owner_mode "$@"; }
lk_file_sort_by_date() { lk_file_sort_modified "$@"; }
lk_first_existing() { lk_first_file "$@"; }
lk_jq_get_array() { lk_json_mapfile "$@"; }
lk_maybe_sudo() { lk_sudo "$@"; }
lk_mktemp_dir() { _LK_STACK_DEPTH=$((1 + ${_LK_STACK_DEPTH:-0})) lk_mktemp -d; }
lk_mktemp_file() { _LK_STACK_DEPTH=$((1 + ${_LK_STACK_DEPTH:-0})) lk_mktemp; }
lk_regex_implode() { lk_ere_implode_args -- "$@"; }
lk_test_many() { lk_test "$@"; }
lk_tty_detail_pairs() { lk_tty_pairs_detail "$@"; }
