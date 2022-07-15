#!/bin/bash

function lk_validate_clear() {
    _LK_VALIDATE_STATUS=0
}

function lk_validate_status() {
    return "${_LK_VALIDATE_STATUS:-0}"
}

# shellcheck disable=SC2059
function _lk_validate_fail() {
    printf "$1" "${_LK_VALIDATE_FIELD_NAME:-$2}" "${@:3}"
    _LK_VALIDATE_STATUS=1
    false
}

function _lk_validate_list() {
    local FN=$1 VAR=$2 VAL=${!2-} IFS=${_LK_VALIDATE_DELIM:-,} NULL VALID SELECTED i
    shift
    SELECTED=($VAL)
    unset IFS
    for i in ${SELECTED[@]+"${SELECTED[@]}"}; do
        [ -z "$i" ] || {
            NULL=0
            eval "$VAR=\$i $FN \"\$@\"" || VALID=0
        }
    done
    [ "${VALID:-1}" -eq 1 ] &&
        { [ "${_LK_REQUIRED:-0}" -eq 0 ] ||
            [ "${NULL:-1}" -eq 0 ] ||
            _lk_validate_fail "Required: %s\n" "$1"; }
}

function lk_validate_not_null() {
    [ -n "${!1-}" ] ||
        _lk_validate_fail "Required: %s\n" "$1"
}

function lk_validate_not_equal() {
    local CASE=1 VAL1 VAL2
    [ "${1-}" != -i ] || { CASE=0 && shift; }
    ! { [ "${_LK_REQUIRED:-0}" -eq 0 ] || lk_validate_not_null "$1"; } || {
        VAL1=${!1-}
        VAL2=${!2-}
        ((CASE)) || {
            VAL1=$(lk_lower "$VAL1")
            VAL2=$(lk_lower "$VAL2")
        }
        [ "$VAL1" != "$VAL2" ] ||
            _lk_validate_fail "Cannot equal %s: %s\n" "$2" "$1"
    }
}

function lk_validate() {
    ! { [ "${_LK_REQUIRED:-0}" -eq 0 ] || lk_validate_not_null "$1"; } ||
        [ -z "${!1-}" ] || {
        [[ ${!1} =~ $2 ]] ||
            _lk_validate_fail "Invalid %s: %q\n" "$1" "${!1}"
    }
}

function lk_validate_list() {
    _lk_validate_list lk_validate "$@"
}

function lk_validate_one_of() {
    ! { [ "${_LK_REQUIRED:-0}" -eq 0 ] || lk_validate_not_null "$1"; } ||
        [ -z "${!1-}" ] || {
        { [ $# -gt 1 ] && printf '%s\n' "${@:2}" || cat; } |
            grep -Fx "${!1}" >/dev/null ||
            _lk_validate_fail "Unknown %s: %q\n" "$1" "${!1}"
    }
}

function lk_validate_many_of() {
    local OPTIONS
    if [ $# -gt 1 ]; then
        _lk_validate_list lk_validate_one_of "$@"
    else
        [ ! -t 0 ] &&
            lk_mapfile OPTIONS /dev/stdin &&
            [ ${#OPTIONS[@]} -gt 0 ] ||
            _lk_validate_fail "No options in input: %s\n" "$1" ||
            return
        _lk_validate_list lk_validate_one_of "$@" "${OPTIONS[@]}"
    fi
}
