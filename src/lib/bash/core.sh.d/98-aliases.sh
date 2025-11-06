#!/usr/bin/env bash

lk_color_off() { lk_colour_off; }
lk_color_on() { lk_colour_on; }
lk_complement_arr() { lk_arr_complement "$@"; }
lk_complement_file() { lk_file_complement "$@"; }
lk_delete_on_exit() { lk_on_exit_delete "$@"; }
lk_intersect_arr() { lk_arr_intersect "$@"; }
lk_intersect_file() { lk_file_intersect "$@"; }
lk_kill_on_exit() { lk_on_exit_kill "$@"; }
lk_undo_delete_on_exit() { lk_on_exit_undo_delete "$@"; }
