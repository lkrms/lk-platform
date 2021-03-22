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
    local OPTIND OPTARG OPT PARAMS=$1 LK_USAGE COMMAND=(iptables) \
    _LK_STACK_DEPTH=1
    [ -z "${LK_IPTABLES_46:-}" ] ||
        set -- "-${LK_IPTABLES_46#-}" "$@"
    LK_USAGE="\
Usage: $(lk_myself -f) [-4|-6|-b]${2:+ $2}"
    shift 2
    while getopts ":46b" OPT; do
        case "$OPT" in
        4)
            COMMAND=(iptables)
            ;;
        6)
            COMMAND=(ip6tables)
            ;;
        b)
            COMMAND=(lk_iptables)
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -ge "$PARAMS" ] || lk_usage || return
    ! lk_verbose ||
        COMMAND+=(-v)
    printf 'local LK_USAGE=%q COMMAND=(%s)\n' \
        "$LK_USAGE" \
        "${COMMAND[*]}"
    printf 'shift %s\n' \
        $((OPTIND - 1))
} #### Reviewed: 2021-03-22

# lk_iptables_maybe_insert CHAIN [-t TABLE] RULE_SPEC
function lk_iptables_maybe_insert() {
    local SH
    SH=$(_lk_iptables_args 2 "CHAIN [-t TABLE] RULE_SPEC" "$@") &&
        eval "$SH" || return
    lk_elevate bash -c "$(
        function _maybe_insert() {
            "$1" -C "${@:3}" &>/dev/null || "$@"
        }
        declare -f lk_iptables _maybe_insert
        lk_quote_args _maybe_insert \
            "${COMMAND[@]}" "${_LK_IPTABLES_SUBCOMMAND:--I}" "$@"
    )"
} #### Reviewed: 2021-03-22

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

lk_provide iptables
