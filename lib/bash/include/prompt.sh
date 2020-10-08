#!/bin/bash
# shellcheck disable=SC2206

function lk_prompt_debug_trap() {
    [ "${LK_PROMPT_DISPLAYED:-0}" -eq 0 ] ||
        [ "$BASH_COMMAND" = "$PROMPT_COMMAND" ] || {
        LK_PROMPT_LAST_COMMAND=($BASH_COMMAND)
        LK_PROMPT_LAST_COMMAND_START=$(lk_date %s)
    }
}

function lk_prompt_command() {
    local EXIT_STATUS=$? LK_DIM=${LK_DIM:-$LK_GREY} \
        SECS COMMAND PS=() STR LEN=25 IFS
    history -a
    if [ ${#LK_PROMPT_LAST_COMMAND[@]} -gt 0 ]; then
        ((SECS = $(lk_date %s) - LK_PROMPT_LAST_COMMAND_START)) || true
        if [ "$EXIT_STATUS" -ne 0 ] ||
            [ "$SECS" -gt 1 ] ||
            { [ "$(type -t "${LK_PROMPT_LAST_COMMAND[0]}")" != "builtin" ] &&
                [[ ! "${LK_PROMPT_LAST_COMMAND[0]}" =~ ^(ls)$ ]]; }; then
            COMMAND=${LK_PROMPT_LAST_COMMAND[*]}
            COMMAND=${COMMAND//$'\r\n'/ }
            COMMAND=${COMMAND//$'\n'/ }
            PS+=("\n$LK_DIM\d \t$LK_RESET ")
            if [ "$EXIT_STATUS" -eq 0 ]; then
                PS+=("$LK_GREEN"$'\xe2\x9c\x94')
            else
                STR=" returned $EXIT_STATUS"
                ((LEN += ${#STR}))
                PS+=("$LK_RED"$'\xe2\x9c\x98'"$STR")
            fi
            STR=" after ${SECS}s "
            PS+=("$STR$LK_RESET$LK_DIM")
            ((LEN = $(tput cols 2>/dev/null) - LEN - ${#STR})) || true
            [ "$LEN" -le 0 ] || PS+=("( \$(printf %s $(printf %q "${COMMAND:0:$LEN}")) )")
            PS+=("$LK_RESET\n")
        fi
        LK_PROMPT_LAST_COMMAND=()
    fi
    if [ "$EUID" -ne 0 ]; then
        PS+=("$LK_BOLD$LK_GREEN\u@")
    else
        PS+=("$LK_BOLD$LK_RED\u@")
    fi
    PS+=("\h$LK_RESET$LK_BOLD$LK_BLUE \w $LK_RESET")
    IFS=
    PS1="${PS[*]//$'\x02\x01'/}\\\$ "
    # Fix alignment issues with versions of Bash that ignore non-printing
    # characters between "\[" and "\]", but not the equivalent \x01 and \x02,
    # when calculating prompt width
    PS1="${PS1//$'\x01'/\\[}"
    PS1="${PS1//$'\x02'/\\]}"
    unset IFS
    LK_PROMPT_DISPLAYED=1
}

function lk_enable_prompt() {
    shopt -s promptvars
    LK_PROMPT_DISPLAYED=
    LK_PROMPT_LAST_COMMAND=()
    PROMPT_COMMAND=lk_prompt_command
    trap lk_prompt_debug_trap DEBUG
}
