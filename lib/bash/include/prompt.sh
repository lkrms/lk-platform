#!/bin/bash
# shellcheck disable=SC2206

function lk_prompt_debug_trap() {
    local IFS
    [ "${LK_PROMPT_DISPLAYED:-0}" -eq 0 ] ||
        [ "$BASH_COMMAND" = "$PROMPT_COMMAND" ] || {
        IFS=$' \t\n\r'
        LK_PROMPT_LAST_COMMAND=($BASH_COMMAND)
        LK_PROMPT_LAST_COMMAND_START=$(lk_date %s)
    }
}

function lk_prompt_command() {
    local EXIT_STATUS=$? LK_DIM=${LK_DIM:-$LK_GREY} \
        SECS PS=() STR LEN=25 IFS
    history -a
    if [ ${#LK_PROMPT_LAST_COMMAND[@]} -gt 0 ]; then
        ((SECS = $(lk_date %s) - LK_PROMPT_LAST_COMMAND_START)) || true
        if [ "$EXIT_STATUS" -ne 0 ] ||
            [ "$SECS" -gt 1 ] ||
            { [ "$(type -t "${LK_PROMPT_LAST_COMMAND[0]}")" != "builtin" ] &&
                [[ ! "${LK_PROMPT_LAST_COMMAND[0]}" =~ ^(ls)$ ]]; }; then
            PS+=("\n\[$LK_DIM\]\d \t\[$LK_RESET\] ")
            if [ "$EXIT_STATUS" -eq 0 ]; then
                PS+=("\[$LK_GREEN\]"$'\xe2\x9c\x94')
            else
                STR=" returned $EXIT_STATUS"
                ((LEN += ${#STR}))
                PS+=("\[$LK_RED\]"$'\xe2\x9c\x98'"$STR")
            fi
            STR=" after ${SECS}s "
            PS+=("$STR\[$LK_RESET$LK_DIM\]")
            ((LEN = $(tput cols 2>/dev/null) - LEN - ${#STR})) || true
            [ "$LEN" -le 0 ] || {
                LK_PROMPT_LAST_COMMAND_CLEAN=$(lk_strip_non_printing \
                    "${LK_PROMPT_LAST_COMMAND[*]}")
                PS+=("( \$(echo \"\${LK_PROMPT_LAST_COMMAND_CLEAN:0:$LEN}\") )")
            }
            PS+=("\[$LK_RESET\]\n")
        fi
        LK_PROMPT_LAST_COMMAND=()
    fi
    if [ "$EUID" -ne 0 ]; then
        PS+=("\[$LK_BOLD$LK_GREEN\]\u@")
    else
        PS+=("\[$LK_BOLD$LK_RED\]\u@")
    fi
    PS+=("\h\[$LK_RESET$LK_BOLD$LK_BLUE\] \w \[$LK_RESET\]")
    IFS=
    PS1="${PS[*]}\\\$ "
    LK_PROMPT_DISPLAYED=1
}

function lk_enable_prompt() {
    shopt -s promptvars
    LK_PROMPT_DISPLAYED=
    LK_PROMPT_LAST_COMMAND=()
    PROMPT_COMMAND=lk_prompt_command
    trap lk_prompt_debug_trap DEBUG
}
