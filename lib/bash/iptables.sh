#!/bin/bash

function lk_iptables() {
    lk_maybe_sudo iptables "$@" &&
        lk_maybe_sudo ip6tables "$@"
}

# lk_iptables_flush_chain chain [table]
function lk_iptables_flush_chain() {
    local COMMAND
    [ -n "${1:-}" ] || lk_warn "no chain" || return
    for COMMAND in iptables ip6tables; do
        lk_command_exists "$COMMAND" || lk_warn "$COMMAND not found" || return
        if lk_maybe_sudo $COMMAND -n ${2:+-t "$2"} --list "$1" >/dev/null 2>&1; then
            lk_maybe_sudo $COMMAND ${2:+-t "$2"} --flush "$1" || return
        else
            lk_maybe_sudo $COMMAND ${2:+-t "$2"} --new-chain "$1" || return
        fi
    done
}
