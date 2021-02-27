#!/bin/bash

# shellcheck disable=SC2016

# lk_iptables_both FUNCTION [ARG...]
#
# Run the IPv4 and IPv6 invocations of the given lk_iptables command.
function lk_iptables_both() {
    local EXIT_STATUS=0
    [[ $1 =~ ^lk_iptables_ ]] && [ "$1" != lk_iptables_both ] ||
        lk_warn "$1 is not a valid lk_iptables function" || return
    "$1" -4 "${@:2}" || EXIT_STATUS=$?
    "$1" -6 "${@:2}" || EXIT_STATUS=$?
    return "$EXIT_STATUS"
}

function _lk_iptables_which() {
    local COMMAND=iptables
    [ "${1:-}" != -4 ] || shift
    [ "${1:-}" != -6 ] || { COMMAND=ip6tables && shift; }
    printf 'local %s=%q\n' COMMAND "$COMMAND"
    printf 'set --'
    printf ' %q' "$@"
}

# lk_iptables_maybe_insert [-4|-6] CHAIN [-t TABLE] RULE_SPEC
function lk_iptables_maybe_insert() {
    eval "$(_lk_iptables_which "$@")"
    local IPTABLES_COMMAND=${_LK_IPTABLES_COMMAND:--I}
    lk_elevate bash -c \
        '$1 -C "${@:3}" 2>/dev/null || $1 $2 "${@:3}"' \
        bash "$COMMAND" "$IPTABLES_COMMAND" "$@"
}

# lk_iptables_maybe_append [-4|-6] CHAIN [-t TABLE] RULE_SPEC
function lk_iptables_maybe_append() {
    _LK_IPTABLES_COMMAND=-A \
        lk_iptables_maybe_insert "$@"
}

# lk_iptables_has_chain [-4|-6] CHAIN [TABLE]
function lk_iptables_has_chain() {
    eval "$(_lk_iptables_which "$@")"
    [ -n "${1:-}" ] || lk_warn "no chain" || return
    lk_elevate "$COMMAND" ${2:+-t "$2"} --numeric --list "$1" &>/dev/null
}

# lk_iptables_flush_chain [-4|-6] CHAIN [TABLE]
function lk_iptables_flush_chain() {
    eval "$(_lk_iptables_which "$@")"
    [ -n "${1:-}" ] || lk_warn "no chain" || return
    if lk_iptables_has_chain "$@"; then
        lk_elevate "$COMMAND" ${2:+-t "$2"} --flush "$1"
    else
        lk_elevate "$COMMAND" ${2:+-t "$2"} --new-chain "$1"
    fi
}

# lk_iptables_delete_chain [-4|-6] CHAIN [TABLE]
function lk_iptables_delete_chain() {
    eval "$(_lk_iptables_which "$@")"
    [ -n "${1:-}" ] || lk_warn "no chain" || return
    if lk_iptables_has_chain "$@"; then
        lk_elevate "$COMMAND" ${2:+-t "$2"} --delete-chain "$1"
    fi
}

lk_provide iptables
