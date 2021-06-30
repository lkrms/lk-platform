#!/bin/bash

function lk_iptables() {
    local STATUS=0
    [ "$EUID" -eq 0 ] || {
        lk_elevate bash -c "$(
            declare -f lk_iptables
            lk_quote_args lk_iptables "$@"
        )"
        return
    }
    iptables "$@" || STATUS=$?
    ip6tables "$@" || return
    return "$STATUS"
} #### Reviewed: 2021-03-22

# _lk_iptables_args MIN_PARAMS USAGE [ARG...]
function _lk_iptables_args() {
    local OPTIND OPTARG OPT LK_USAGE PARAMS=$1 HAS_SUFFIX= \
        COMMAND=("iptables${_LK_IPTABLES_CMD_SUFFIX-}") \
        _LK_STACK_DEPTH=1
    [ -n "${_LK_IPTABLES_CMD_SUFFIX-}" ] || unset HAS_SUFFIX
    [ -z "${_LK_IPTABLES_46-}" ] ||
        set -- "-${_LK_IPTABLES_46#-}" "$@"
    LK_USAGE="Usage: ${FUNCNAME[1]} [-4|-6${HAS_SUFFIX-|-b}]${2:+ $2}"
    shift 2
    while getopts ":46bh" OPT; do
        case "$OPT" in
        4)
            COMMAND=("iptables${_LK_IPTABLES_CMD_SUFFIX-}")
            ;;
        6)
            COMMAND=("ip6tables${_LK_IPTABLES_CMD_SUFFIX-}")
            ;;
        b)
            [ -z "${HAS_SUFFIX+1}" ] || lk_usage || return
            COMMAND=("lk_iptables")
            ;;
        h)
            lk_usage
            echo "return 0"
            return 0
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -ge "$PARAMS" ] || lk_usage || return
    ! lk_verbose || [ -n "${HAS_SUFFIX+1}" ] ||
        COMMAND+=(-v)
    printf 'local LK_USAGE=%q COMMAND=(%s)\n' \
        "$LK_USAGE" \
        "${COMMAND[*]}"
    printf 'shift %s\n' \
        $((OPTIND - 1))
} #### Reviewed: 2021-06-05

# lk_iptables_maybe_insert CHAIN [-t TABLE] RULE_SPEC
function lk_iptables_maybe_insert() {
    local SH
    SH=$(_lk_iptables_args 2 "CHAIN [-t TABLE] RULE_SPEC" "$@") &&
        eval "$SH" || return
    lk_elevate bash -c "$(
        function maybe_insert() {
            "${COMMAND[@]}" -C "$@" &>/dev/null ||
                "${COMMAND[@]}" "${_LK_IPTABLES_SUBCOMMAND:--I}" "$@"
        }
        declare -f lk_iptables maybe_insert
        declare -p COMMAND _LK_IPTABLES_SUBCOMMAND 2>/dev/null || true
        lk_quote_args maybe_insert "$@"
    )"
} #### Reviewed: 2021-04-23

# lk_iptables_maybe_append CHAIN [-t TABLE] RULE_SPEC
function lk_iptables_maybe_append() {
    local SH
    SH=$(_lk_iptables_args 2 "CHAIN [-t TABLE] RULE_SPEC" "$@") &&
        eval "$SH" || return
    _LK_IPTABLES_SUBCOMMAND=-A \
        lk_iptables_maybe_insert "$@"
} #### Reviewed: 2021-03-22

# lk_iptables_has_chain CHAIN [TABLE]
function lk_iptables_has_chain() {
    local SH
    SH=$(_lk_iptables_args 1 "CHAIN [TABLE]" "$@") && eval "$SH" || return
    lk_elevate "${COMMAND[@]}" ${2:+-t "$2"} --numeric --list "$1" &>/dev/null
} #### Reviewed: 2021-03-22

# lk_iptables_flush_chain CHAIN [TABLE]
function lk_iptables_flush_chain() {
    local SH
    SH=$(_lk_iptables_args 1 "CHAIN [TABLE]" "$@") && eval "$SH" || return
    if lk_iptables_has_chain "$@"; then
        lk_elevate "${COMMAND[@]}" ${2:+-t "$2"} --flush "$1"
    else
        lk_elevate "${COMMAND[@]}" ${2:+-t "$2"} --new-chain "$1"
    fi
} #### Reviewed: 2021-03-22

# lk_iptables_delete_chain CHAIN [TABLE]
function lk_iptables_delete_chain() {
    local SH
    SH=$(_lk_iptables_args 1 "CHAIN [TABLE]" "$@") && eval "$SH" || return
    if lk_iptables_has_chain "$@"; then
        lk_elevate "${COMMAND[@]}" ${2:+-t "$2"} --delete-chain "$1"
    fi
} #### Reviewed: 2021-03-22

# lk_iptables_insert CHAIN [-t TABLE] RULE_SPEC
function lk_iptables_insert() {
    local SH
    SH=$(_lk_iptables_args 2 "CHAIN [-t TABLE] RULE_SPEC" "$@") &&
        eval "$SH" || return
    lk_elevate "${COMMAND[@]}" -I "$@"
} #### Reviewed: 2021-03-22

# lk_iptables_append CHAIN [-t TABLE] RULE_SPEC
function lk_iptables_append() {
    local SH
    SH=$(_lk_iptables_args 2 "CHAIN [-t TABLE] RULE_SPEC" "$@") &&
        eval "$SH" || return
    lk_elevate "${COMMAND[@]}" -A "$@"
} #### Reviewed: 2021-03-22

# lk_iptables_delete CHAIN [-t TABLE] RULE_SPEC
function lk_iptables_delete() {
    local SH
    SH=$(_lk_iptables_args 2 "CHAIN [-t TABLE] RULE_SPEC" "$@") &&
        eval "$SH" || return
    lk_elevate "${COMMAND[@]}" -D "$@"
} #### Reviewed: 2021-03-22

# lk_iptables_delete_all CHAIN [-t TABLE] RULE_SPEC
function lk_iptables_delete_all() {
    local SH
    SH=$(_lk_iptables_args 2 "CHAIN [-t TABLE] RULE_SPEC" "$@") &&
        eval "$SH" || return
    while lk_elevate "${COMMAND[@]}" -C "$@" &>/dev/null; do
        lk_elevate "${COMMAND[@]}" -D "$@" || break
    done
} #### Reviewed: 2021-03-22

function _lk_iptables_save() {
    [ "$EUID" -eq 0 ] || {
        lk_elevate bash -c "$(
            declare -f _lk_iptables_save
            declare -p COMMAND
            lk_quote_args _lk_iptables_save "$@"
        )"
        return
    }
    for t in filter nat mangle raw security; do
        "${COMMAND[@]}" -t "$t" || break
    done | sed -E "s/^(:[^ ]+ [^ ]+ \[)[0-9]+:[0-9]+(\])/\10:0\2/"
}

function lk_iptables_save() {
    local SH
    SH=$(_LK_IPTABLES_CMD_SUFFIX=-save &&
        _lk_iptables_args 0 "" "$@") && eval "$SH" || return
    _lk_iptables_save "$@"
}

lk_provide iptables
