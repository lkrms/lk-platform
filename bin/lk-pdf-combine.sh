#!/bin/bash

# shellcheck disable=SC1091,SC2015

include='' . lk-bash-load.sh || exit

lk_assert_command_exists mutool

[ $# -ge 2 ] &&
    lk_test_many lk_is_pdf "$@" || lk_usage "\
Usage: ${0##*/} PDF1 PDF2..."

lk_log_output

NEWEST=$(lk_sort_paths_by_date "$@" | tail -n1)
FILE=$1
TEMP=$(lk_file_prepare_temp -n "$FILE")
lk_delete_on_exit "$TEMP"

lk_echo_args "$@" |
    lk_console_list "Combining:" "PDF" "PDFs"

mutool merge -o "$TEMP" -- "$@"
touch -r "$NEWEST" -- "$TEMP"

if lk_command_exists trash-put; then
    trash-put -- "$@"
else
    for f in "$@"; do
        lk_file_backup -m "$f"
        rm -- "$f"
    done
fi

mv -- "$TEMP" "$FILE"
lk_console_item "Successfully combined to:" "$FILE"
