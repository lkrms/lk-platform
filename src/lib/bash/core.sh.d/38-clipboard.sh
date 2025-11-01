#!/usr/bin/env bash

# lk_clip_set
#
# Copy input to the desktop environment's clipboard.
function lk_clip_set() {
    [[ ! -t 0 ]] || lk_err "no input" || return
    local command
    command=$(
        lk_runnable \
            "xclip -selection clipboard" \
            pbcopy \
            clip
    ) || lk_err "no clipboard" || return
    command $command || lk_err "error copying input to clipboard" || return
    lk_tty_detail "Input copied to clipboard"
}

# lk_clip_get
#
# Paste the desktop environment's clipboard to output.
function lk_clip_get() {
    local command
    command=$(
        lk_runnable \
            "xclip -selection clipboard -out" \
            pbpaste \
            "powershell.exe -noprofile -command Get-Clipboard"
    ) || lk_err "no clipboard" || return
    command $command || lk_err "error pasting clipboard to output" || return
}

#### Reviewed: 2025-11-01
