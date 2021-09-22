#!/bin/bash

function _lk_whiptail() {
    whiptail "$@" 3>&1 1>&2 2>&3
}

function lk_whiptail() {
    lk_log_bypass_stderr _lk_whiptail "$@"
}

# lk_whiptail_build_list ARRAY SED_SCRIPT TAG...
#
# Populate ARRAY with TAG ITEM elements for each TAG, where ITEM is the output
# of `sed -E "$SED_SCRIPT" <<<"$TAG"`.
#
# Example:
#
#     $ lk_whiptail_build_list APPS 's/^(.*\/)?(.*)\.app$/\2/' /Applications/*.app
#     $ printf '%s\t%s\n' "${APPS[@]}"
#     /Applications/Firefox.app	Firefox
#     /Applications/Keynote.app	Keynote
#     ...
#     /Applications/iTerm.app	iTerm
function lk_whiptail_build_list() {
    [ $# -ge 2 ] || lk_warn "invalid arguments" || return
    lk_mapfile "$1" <(lk_echo_args "${@:3}" | sed -E "p;$2")
}

# - lk_whiptail_checklist TITLE TEXT TAG ITEM [TAG ITEM...] [STATUS]
# - lk_whiptail_checklist -s TITLE TEXT TAG ITEM STATUS [TAG ITEM STATUS...]
#
# Display a checklist box with STATUS as the initial on/off state for all
# options (unless the alternate form is used to set each STATUS individually),
# and output the TAG of each ITEM selected by the user.
function lk_whiptail_checklist() {
    local _STATUS= _ARGS=2
    [ "${1-}" != -s ] || { unset _STATUS && _ARGS=3 && shift; }
    # Minimum dialog width: 54 (i.e. 38+16)
    # Maximum dialog width: 76 (i.e. 60+16)
    # Maximum list height: 10
    # Maximum dialog height: 16 + lines of text after wrapping
    local TITLE=${1-} TEXT=${2-} LIST_HEIGHT=10 WIDTH=38 MAX_WIDTH=60 \
        STATUS ITEM ITEMS=() i=0
    (($# >= _ARGS + 2)) || lk_warn "invalid arguments" || return
    shift 2
    [ -z "${_STATUS+1}" ] || {
        # If an odd number of arguments remain, the last one is STATUS
        ! (($# % 2)) || STATUS="${*: -1:1}"
        STATUS=${STATUS:-on}
    }
    while [ $# -ge "$_ARGS" ]; do
        ((++i))
        STATUS=${_STATUS+$STATUS}${_STATUS-$3}
        ! lk_no_input || {
            [ "$STATUS" = off ] || echo "$1"
            shift "$_ARGS"
            continue
        }
        ITEM=$(lk_ellipsis "$MAX_WIDTH" "$2")
        ITEMS+=("$1" "$ITEM" "$STATUS")
        [ ${#ITEM} -le "$WIDTH" ] || WIDTH=${#ITEM}
        shift "$_ARGS"
    done
    ! lk_no_input || return 0
    ((LIST_HEIGHT = i >= LIST_HEIGHT ? LIST_HEIGHT : i))
    ((WIDTH += 16, WIDTH += WIDTH % 2))
    TEXT=$(fold -s -w $((WIDTH - 4)) <<<"$TEXT")
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

#### Reviewed: 2021-09-22
