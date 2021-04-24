#!/bin/bash

function _lk_whiptail() {
    whiptail "$@" 3>&1 1>&2 2>&3
}

function lk_whiptail() {
    lk_log_bypass_stderr _lk_whiptail "$@"
}

# lk_whiptail_checklist TITLE TEXT TAG ITEM [TAG ITEM...] [STATUS]
#
# Display options in a checklist box and output the TAG of each ITEM selected by
# the user, using STATUS as the initial on/off state for all options (default:
# "on").
function lk_whiptail_checklist() {
    # Minimum dialog width: 54 (i.e. 38+16)
    # Maximum dialog width: 76 (i.e. 60+16)
    # Maximum list height: 10
    # Maximum dialog height: 16 + lines of text after wrapping
    local TITLE=${1:-} TEXT=${2:-} LIST_HEIGHT=10 WIDTH=38 MAX_WIDTH=60 \
        STATUS LINE ITEM ITEMS=()
    [ $# -ge 4 ] || lk_warn "invalid arguments" || return
    shift 2
    # If an odd number of arguments remain, the last one is STATUS
    ! (($# % 2)) || STATUS="${*: -1:1}"
    STATUS=${STATUS:-on}
    while [ $# -ge 2 ]; do
        ! lk_no_input || {
            [ "$STATUS" = off ] || echo "$1"
            shift 2
            continue
        }
        ITEM=$(lk_ellipsis "$MAX_WIDTH" "$2")
        ITEMS+=("$(printf '%q %q' "$1" "$ITEM")")
        [ ${#ITEM} -le "$WIDTH" ] || WIDTH=${#ITEM}
        shift 2
    done
    ! lk_no_input || return 0
    [ ${#ITEMS[@]} -ge "$LIST_HEIGHT" ] || LIST_HEIGHT=${#ITEMS[@]}
    ((WIDTH += 16, WIDTH += WIDTH % 2))
    TEXT=$(lk_fold "$TEXT" $((WIDTH - 4)))
    eval "ITEMS=(${ITEMS[*]/%/ $STATUS})"
    lk_whiptail \
        --backtitle "$(lk_myself 1)" \
        --title "$TITLE" \
        --notags \
        --separate-output \
        --checklist "$TEXT" \
        "$((LIST_HEIGHT + 6 + $(wc -l <<<"$TEXT")))" \
        "$WIDTH" \
        "$LIST_HEIGHT" \
        "${ITEMS[@]}"
}

lk_provide whiptail

#### Reviewed: 2021-04-24
