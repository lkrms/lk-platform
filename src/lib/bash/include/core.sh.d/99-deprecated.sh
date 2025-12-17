#!/usr/bin/env bash

lk_bash_at_least() { lk_bash_is "$@"; }
lk_cache_mark_dirty() { _LK_STACK_DEPTH=$((${_LK_STACK_DEPTH-0} + 1)) lk_cache_flush; }
lk_caller_name() { lk_caller $((${1-0} + 1)); }
lk_command_exists() { lk_has "$@"; }
lk_confirm() { lk_tty_yn "$@"; }
lk_debug() { lk_debug_is_on; }
lk_delete_on_exit_withdraw() { lk_on_exit_undo_delete "$@"; }
lk_dirs_exist() { lk_test_all_d "$@"; }
lk_dry_run() { lk_is_dryrun; }
lk_echo_args() { lk_args "$@"; }
lk_echo_array() { lk_arr "$@"; }
lk_ellipsis() { lk_ellipsise "$@"; }
lk_escape_ere_replace() { lk_sed_escape_replace "$@"; }
lk_escape_ere() { lk_sed_escape "$@"; }
lk_false() { lk_is_false "$@"; }
lk_file_security() { lk_file_owner_mode "$@"; }
lk_file_sort_by_date() { lk_file_sort_modified "$@"; }
lk_files_exist() { lk_test_all_f "$@"; }
lk_files_not_empty() { lk_test_all_s "$@"; }
lk_first_command() { lk_runnable "$@"; }
lk_first_existing() { lk_readable "$@"; }
lk_first_file() { lk_readable "$@"; }
lk_get_tty() { lk_writable_tty "$@"; }
lk_is_apple_silicon() { lk_system_is_apple_silicon; }
lk_is_arch() { lk_system_is_arch; }
lk_is_linux() { lk_system_is_linux; }
lk_is_macos() { lk_system_is_macos; }
lk_is_qemu() { lk_system_is_qemu; }
lk_is_system_apple_silicon() { lk_system_is_apple_silicon -t; }
lk_is_ubuntu() { lk_system_is_ubuntu; }
lk_is_virtual() { lk_system_is_vm; }
lk_is_wsl() { lk_system_is_wsl; }
lk_jq_get_array() { lk_json_mapfile "$@"; }
lk_log_create_file() { lk_log_file_create "$@"; }
lk_log_start() { lk_log_open "$@"; }
lk_maybe_sudo() { lk_sudo "$@"; }
lk_mktemp_dir() { _LK_STACK_DEPTH=$((${_LK_STACK_DEPTH-0} + 1)) lk_mktemp -d; }
lk_mktemp_file() { _LK_STACK_DEPTH=$((${_LK_STACK_DEPTH-0} + 1)) lk_mktemp; }
lk_no_input() { lk_input_is_off; }
lk_paths_exist() { lk_test_all_e "$@"; }
lk_regex_implode() { lk_ere_implode_args -- "$@"; }
lk_root() { lk_user_is_root; }
lk_safe_grep() { lk_grep "$@"; }
lk_script_name() { lk_script $((${1-0} + 1)); }
lk_script_running() { lk_is_script; }
lk_test_many() { lk_test "$@"; }
lk_test() { lk_test_all "$@"; }
lk_true() { lk_is_true "$@"; }
lk_tty_detail_pairs() { lk_tty_pairs_detail "$@"; }
lk_verbose() { lk_is_v "$@"; }
lk_version_at_least() { lk_version_is "$@"; }

[[ ${S-} ]] || S=$LK_h
[[ ${NS-} ]] || NS=$LK_H
