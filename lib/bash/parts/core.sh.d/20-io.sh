#!/bin/bash

# lk_fifo_flush FIFO_PATH
function lk_fifo_flush() {
    [ -p "${1-}" ] || lk_warn "not a FIFO: ${1-}" || return
    gnu_dd \
        if="$1" \
        of=/dev/null \
        iflag=nonblock \
        status=none &>/dev/null || true
}
