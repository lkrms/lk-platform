#!/bin/bash

. lk-bash-load.sh || exit

lk_assert_command_exists mutool

lk_test_many lk_is_pdf "$@" || lk_usage "\
Usage: ${0##*/} PDF..."

lk_log_start

lk_console_message "Cleaning $# $(lk_plural $# file files)"

# Keep the original PDF unless file size is reduced by at least this much
PERCENT_SAVED_THRESHOLD=${PERCENT_SAVED_THRESHOLD:-2}

ERRORS=()

i=0
for FILE in "$@"; do
    lk_console_item "Processing $((++i)) of $#:" "$FILE"
    TEMP=$(lk_file_prepare_temp -n "$FILE")
    lk_delete_on_exit "$TEMP"
    mutool clean -gggg -zfi -- "$FILE" "$TEMP" &&
        touch -r "$FILE" -- "$TEMP" || {
        ERRORS+=("$FILE")
        continue
    }
    OLD_SIZE=$(gnu_stat -Lc %s -- "$FILE")
    NEW_SIZE=$(gnu_stat -Lc %s -- "$TEMP")
    ((SAVED = OLD_SIZE - NEW_SIZE)) || true
    if [ "$SAVED" -ge 0 ]; then
        ((PERCENT_SAVED = (SAVED * 100 + (OLD_SIZE - 1)) / OLD_SIZE)) || true
        lk_console_detail "File size" \
            "reduced by $PERCENT_SAVED% ($SAVED bytes)" "$LK_GREEN"
    else
        ((PERCENT_SAVED = -((OLD_SIZE - 1) - SAVED * 100) / OLD_SIZE)) || true
        lk_console_detail "File size" \
            "increased by $((-PERCENT_SAVED))% ($((-SAVED)) bytes)" "$LK_RED"
    fi
    if [ "$PERCENT_SAVED" -lt "$PERCENT_SAVED_THRESHOLD" ]; then
        lk_console_detail "Keeping original:" "$FILE"
        continue
    fi
    lk_rm -- "$FILE"
    mv -- "$TEMP" "$FILE"
    lk_console_detail "Cleaned successfully:" "$FILE"
done

[ ${#ERRORS[@]} -eq 0 ] ||
    lk_console_error -r \
        "Unable to process ${#ERRORS[@]} $(lk_plural \
            ${#ERRORS[@]} file files):" $'\n'"$(lk_echo_array ERRORS)" ||
    lk_die ""
