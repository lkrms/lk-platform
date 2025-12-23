#!/usr/bin/env bash

. lk-bash-load.sh || exit

lk_assert_command_exists mutool

lk_test_all lk_is_pdf "$@" || lk_usage "\
Usage: ${0##*/} PDF..."

lk_log_open

lk_tty_print "Cleaning $# $(lk_plural $# file files)"

# Keep the original PDF unless file size is reduced by at least this much
PERCENT_SAVED_THRESHOLD=${PERCENT_SAVED_THRESHOLD:-2}

ERRORS=()

i=0
for FILE in "$@"; do
    lk_tty_print "Processing $((++i)) of $#:" "$FILE"
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
        lk_tty_detail "File size" \
            "reduced by $PERCENT_SAVED% ($SAVED bytes)" "$LK_GREEN"
    else
        ((PERCENT_SAVED = -((OLD_SIZE - 1) - SAVED * 100) / OLD_SIZE)) || true
        lk_tty_detail "File size" \
            "increased by $((-PERCENT_SAVED))% ($((-SAVED)) bytes)" "$LK_RED"
    fi
    if [ "$PERCENT_SAVED" -lt "$PERCENT_SAVED_THRESHOLD" ]; then
        lk_tty_detail "Keeping original:" "$FILE"
        continue
    fi
    lk_rm -- "$FILE"
    mv -- "$TEMP" "$FILE"
    lk_tty_detail "Cleaned successfully:" "$FILE"
done

[ ${#ERRORS[@]} -eq 0 ] ||
    lk_tty_error -r \
        "Unable to process ${#ERRORS[@]} $(lk_plural \
            ${#ERRORS[@]} file files):" $'\n'"$(lk_arr ERRORS)" ||
    lk_die ""
