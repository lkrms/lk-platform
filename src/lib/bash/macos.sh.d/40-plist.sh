#!/bin/bash

function PlistBuddy() {
    lk_sudo /usr/libexec/PlistBuddy "$@"
}

function _lk_plist_buddy() {
    [[ -n ${_LK_PLIST:+1} ]] ||
        _LK_STACK_DEPTH=1 lk_warn "call lk_plist_set_file first" || return
    # Create the plist file without "File Doesn't Exist, Will Create"
    [[ -e $_LK_PLIST ]] ||
        PlistBuddy -c "Save" "$_LK_PLIST" >/dev/null || return
    local COMMAND=$1
    shift
    PlistBuddy "$@" -c "$COMMAND" "$_LK_PLIST" || return
}

function _lk_plist_quote() {
    echo "\"${1//\"/\\\"}\""
}

# lk_plist_set_file PLIST_FILE
#
# Run subsequent lk_plist_* commands on PLIST_FILE.
function lk_plist_set_file() {
    _LK_PLIST=$1
}

# lk_plist_delete ENTRY
function lk_plist_delete() {
    _lk_plist_buddy "Delete $(_lk_plist_quote "$1")"
}

# lk_plist_maybe_delete ENTRY
function lk_plist_maybe_delete() {
    lk_plist_delete "$1" 2>/dev/null || true
}

# lk_plist_add ENTRY TYPE [VALUE]
#
# TYPE must be one of:
# - string
# - array
# - dict
# - bool
# - real
# - integer
# - date
# - data
function lk_plist_add() {
    _lk_plist_buddy \
        "Add $(_lk_plist_quote "$1") $2${3+ $(_lk_plist_quote "$3")}"
}

# lk_plist_replace ENTRY TYPE [VALUE]
#
# See lk_plist_add for valid types.
function lk_plist_replace() {
    lk_plist_delete "$1" 2>/dev/null || true
    lk_plist_add "$@"
}

# lk_plist_merge_from_file ENTRY PLIST_FILE [PLIST_FILE_ENTRY]
function lk_plist_merge_from_file() {
    (($# < 3)) || {
        [[ -e $2 ]] || lk_warn "file not found: $2" || return
        local TEMP
        lk_mktemp_with TEMP \
            PlistBuddy -x -c "Print $(_lk_plist_quote "$3")" "$2" || return
        set -- "$1" "$TEMP"
    }
    _lk_plist_buddy "Merge $(_lk_plist_quote "$2") $(_lk_plist_quote "$1")"
}

# lk_plist_replace_from_file ENTRY TYPE PLIST_FILE [PLIST_FILE_ENTRY]
#
# Use TYPE to specify the data type of the PLIST_FILE entry being applied.
#
# See lk_plist_add for valid types.
function lk_plist_replace_from_file() {
    lk_plist_replace "$1" "$2" &&
        lk_plist_merge_from_file "$1" "$3" ${4+"$4"}
}

# lk_plist_get ENTRY
function lk_plist_get() {
    _lk_plist_buddy "Print $(_lk_plist_quote "$1")"
}

# lk_plist_get_xml ENTRY
function lk_plist_get_xml() {
    _lk_plist_buddy "Print $(_lk_plist_quote "$1")" -x
}

# lk_plist_exists ENTRY
function lk_plist_exists() {
    lk_plist_get "$1" &>/dev/null
}

# lk_plist_maybe_add ENTRY TYPE [VALUE]
#
# See lk_plist_add for valid types.
function lk_plist_maybe_add() {
    lk_plist_exists "$1" ||
        lk_plist_add "$@"
}
