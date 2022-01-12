#!/bin/bash

. lk-bash-load.sh || exit

lk_assert_command_exists mutool

[ $# -ge 2 ] &&
    lk_test lk_is_pdf "$@" || lk_usage "\
Usage: ${0##*/} PDF1 PDF2..."

lk_log_start

NEWEST=$(lk_file_sort_modified "$@" | tail -n1)
FILE=$1
TEMP=$(lk_file_prepare_temp -n "$FILE")
lk_delete_on_exit "$TEMP"

lk_echo_args "$@" |
    lk_tty_list - "Combining:" "PDF" "PDFs"

mutool merge -o "$TEMP" -- "$@"
touch -r "$NEWEST" -- "$TEMP"

lk_rm -- "$@"

mv -- "$TEMP" "$FILE"
lk_tty_print "Successfully combined to:" "$FILE"
