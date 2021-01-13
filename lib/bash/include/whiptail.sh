#!/bin/bash

# lk_whiptail_checklist TITLE TEXT [TAG ITEM...] [INITIAL_STATUS]
#
# Present each ITEM (or input line if no TAG ITEM pairs are passed) as a
# checklist menu, and output a list of TAG strings (or lines) selected by the
# user.
#
# Use INITIAL_STATUS to specify that entries should initially be "on" (the
# default), or "off".
function lk_whiptail_checklist() {
    # minimum dialog width: 54 (i.e. 38+16)
    # maximum dialog width: 76 (i.e. 60+16)
    # maximum list height: 10
    # maximum dialog height: 16 + lines of text after wrapping
    local TITLE=$1 TEXT=$2 LIST_HEIGHT=10 WIDTH=38 MAX_WIDTH=60 \
        INITIAL_STATUS LINE ITEM ITEMS=()
    shift 2 || return
    # If an odd number of arguments remain, the last one is INITIAL_STATUS
    ! (($# % 2)) || INITIAL_STATUS="${*: -1:1}"
    INITIAL_STATUS=${INITIAL_STATUS:-${LK_CHECKLIST_DEFAULT:-on}}
    if [ $# -lt 2 ]; then
        while IFS= read -r LINE || [ -n "$LINE" ]; do
            ! lk_no_input || {
                [ "$INITIAL_STATUS" = off ] || echo "$LINE"
                continue
            }
            ITEM=$(lk_ellipsis "$MAX_WIDTH" "$LINE")
            ITEMS+=("$(printf '%q %q' "$LINE" "$ITEM")")
            [ ${#ITEM} -le "$WIDTH" ] || WIDTH=${#ITEM}
        done
    else
        while [ $# -ge 2 ]; do
            ! lk_no_input || {
                [ "$INITIAL_STATUS" = off ] || echo "$1"
                shift 2
                continue
            }
            ITEM=$(lk_ellipsis "$MAX_WIDTH" "$2")
            ITEMS+=("$(printf '%q %q' "$1" "$ITEM")")
            [ ${#ITEM} -le "$WIDTH" ] || WIDTH=${#ITEM}
            shift 2
        done
    fi
    ! lk_no_input || return 0
    [ ${#ITEMS[@]} -ge "$LIST_HEIGHT" ] || LIST_HEIGHT=${#ITEMS[@]}
    ((WIDTH += 16, WIDTH += WIDTH % 2))
    TEXT=$(lk_fold "$TEXT" $((WIDTH - 4)))
    eval "ITEMS=(${ITEMS[*]/%/ $INITIAL_STATUS})"
    whiptail \
        --backtitle "$(lk_myself 1)" \
        --title "$TITLE" \
        --notags \
        --separate-output \
        --checklist "$TEXT" \
        "$((LIST_HEIGHT + 6 + $(wc -l <<<"$TEXT")))" \
        "$WIDTH" \
        "$LIST_HEIGHT" \
        "${ITEMS[@]}" \
        3>&1 1>&2 2>&3
}

lk_provide whiptail
