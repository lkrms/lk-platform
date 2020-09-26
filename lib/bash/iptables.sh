#!/bin/bash

# lk_iptables_both FUNCTION [ARG...]
#   Call the specified lk_iptables_ function with LK_IPTABLES_CMD=iptables
#   and LK_IPTABLES_CMD=ip6tables.
function lk_iptables_both() {
    local LK_IPTABLES_CMD EXIT_STATUS=0
    [[ "$1" =~ ^lk_iptables_ ]] ||
        lk_warn "$1 does not start with lk_iptables_" || return
    for LK_IPTABLES_CMD in iptables ip6tables; do
        lk_command_exists "$LK_IPTABLES_CMD" ||
            lk_warn "command not found: $LK_IPTABLES_CMD" || return 127
        "$@" || EXIT_STATUS="$?"
    done
    return "$EXIT_STATUS"
}

# lk_iptables_maybe_insert CHAIN [-t TABLE] RULE_SPEC
function lk_iptables_maybe_insert() {
    local LK_IPTABLES_CMD="${LK_IPTABLES_CMD:-iptables}" \
        LK_IPTABLES_COMMAND="${LK_IPTABLES_COMMAND:--I}"
    lk_elevate bash -c "\
$LK_IPTABLES_CMD -C \"\$@\" 2>/dev/null || \
    $LK_IPTABLES_CMD $LK_IPTABLES_COMMAND \"\$@\"" bash "$@"
}

# lk_iptables_maybe_append CHAIN [-t TABLE] RULE_SPEC
function lk_iptables_maybe_append() {
    local LK_IPTABLES_COMMAND=-A
    lk_iptables_maybe_insert "$@"
}

# lk_iptables_has_chain CHAIN [TABLE]
function lk_iptables_has_chain() {
    local LK_IPTABLES_CMD="${LK_IPTABLES_CMD:-iptables}"
    [ -n "${1:-}" ] || lk_warn "no chain" || return
    lk_elevate \
        "$LK_IPTABLES_CMD" -n ${2:+-t "$2"} --list "$1" >/dev/null 2>&1
}

# lk_iptables_flush_chain CHAIN [TABLE]
function lk_iptables_flush_chain() {
    local LK_IPTABLES_CMD="${LK_IPTABLES_CMD:-iptables}"
    [ -n "${1:-}" ] || lk_warn "no chain" || return
    if lk_iptables_has_chain "$@"; then
        lk_elevate "$LK_IPTABLES_CMD" ${2:+-t "$2"} --flush "$1"
    else
        lk_elevate "$LK_IPTABLES_CMD" ${2:+-t "$2"} --new-chain "$1"
    fi
}

function _lk_define_ip6tables_functions() {
    local i
    for i in "$@"; do
        eval "\
function lk_ip6tables_$i() {
    LK_IPTABLES_CMD=ip6tables lk_iptables_$i \"\$@\"
}"
    done
}

_lk_define_ip6tables_functions \
    maybe_insert \
    maybe_append \
    has_chain \
    flush_chain
