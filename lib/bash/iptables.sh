#!/bin/bash

function lk_iptables() {
    lk_maybe_sudo iptables "$@" &&
        lk_maybe_sudo ip6tables "$@"
}

function lk_iptables_both() {
    local COMMAND EXIT_STATUS=0
    [[ "$1" =~ ^lk_iptables_ ]] ||
        lk_warn "$1 does not start with lk_iptables_" || return
    for COMMAND in iptables ip6tables; do
        lk_command_exists "$COMMAND" ||
            lk_warn "$COMMAND: command not found" || return 127
        "$@" || EXIT_STATUS="$?"
    done
    return "$EXIT_STATUS"
}

# lk_iptables_has_chain chain [table]
function lk_iptables_has_chain() {
    local COMMAND="${COMMAND:-iptables}"
    [ -n "${1:-}" ] || lk_warn "no chain" || return
    lk_elevate "$COMMAND" -n ${2:+-t "$2"} --list "$1" >/dev/null 2>&1
}

# lk_ip6tables_has_chain chain [table]
function lk_ip6tables_has_chain() {
    COMMAND=ip6tables lk_iptables_has_chain "$@"
}

# lk_iptables_flush_chain chain [table]
function lk_iptables_flush_chain() {
    local COMMAND="${COMMAND:-iptables}"
    [ -n "${1:-}" ] || lk_warn "no chain" || return
    if lk_iptables_has_chain "$@"; then
        lk_elevate "$COMMAND" ${2:+-t "$2"} --flush "$1"
    else
        lk_elevate "$COMMAND" ${2:+-t "$2"} --new-chain "$1"
    fi
}
