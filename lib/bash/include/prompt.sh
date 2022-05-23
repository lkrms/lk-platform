#!/bin/bash

function _lk_prompt_debug_trap() {
    local IFS
    [ "${_LK_PROMPT_DISPLAYED:-0}" -eq 0 ] ||
        [ "$BASH_COMMAND" = "$PROMPT_COMMAND" ] || {
        unset IFS
        [ -n "${_LK_PROMPT_LAST+1}" ] ||
            _LK_PROMPT_LAST_START=$(lk_date %s)
        _LK_PROMPT_LAST=($BASH_COMMAND)
    }
}

function _lk_prompt_command() {
    local STATUS=$? DIM=$LK_DIM SECS PS=() STR LEN=25 IFS
    DIM=${DIM:-$LK_GREY}
    history -a
    shopt -u promptvars
    if [ -n "${_LK_PROMPT_LAST+1}" ]; then
        ((SECS = $(lk_date %s) - _LK_PROMPT_LAST_START)) || true
        if [ "$STATUS" -ne 0 ] ||
            [ "$SECS" -gt 1 ] ||
            { [ "$(type -t "${_LK_PROMPT_LAST[0]}")" != builtin ] &&
                [ "${_LK_PROMPT_LAST[0]}" != ls ]; }; then
            # "Thu May 06 15:02:32 "
            PS+=("\n\[$DIM\]\d \t\[$LK_RESET\] ")
            if [ "$STATUS" -eq 0 ]; then
                # "✔"
                PS+=("\[$LK_GREEN\]"$'\xe2\x9c\x94')
            else
                # "✘ returned 1"
                STR=" returned $STATUS"
                PS+=("\[$LK_RED\]"$'\xe2\x9c\x98'"$STR")
                ((LEN += ${#STR}))
            fi
            # " after 12s "
            STR=" after ${SECS}s "
            PS+=("$STR\[$LK_RESET$DIM\]")
            ((LEN = COLUMNS - LEN - ${#STR})) || true
            [ "$LEN" -le 0 ] || {
                # "( sleep 12; false )"
                unset IFS
                PS+=("( $(lk_strip_non_printing <<<"${_LK_PROMPT_LAST[*]}" |
                    head -c"$LEN" | sed 's/\\/\\&/g') )")
            }
            # "\n"
            PS+=("\[$LK_RESET\]\n")
        fi
        _LK_PROMPT_LAST=()
    fi
    if [ "$EUID" -ne 0 ]; then
        # "ubuntu@"
        PS+=("\[$LK_BOLD$LK_GREEN\]\u@")
    else
        # "root@"
        PS+=("\[$LK_BOLD$LK_RED\]\u@")
    fi
    # "host1 ~ "
    PS+=("\h\[$LK_RESET$LK_BOLD$LK_BLUE\] \w \[$LK_RESET\]")
    IFS=
    # "$ " or "# "
    PS1="${PS[*]}"'\$ '
    _LK_PROMPT_DISPLAYED=1
    [ "${LC_BYOBU:+1}${BYOBU_RUN_DIR:+2}" != 2 ] || export LC_BYOBU=0
}

function lk_prompt_enable() {
    unset _LK_PROMPT_DISPLAYED
    _LK_PROMPT_LAST=()
    PROMPT_COMMAND=_lk_prompt_command
    lk_trap_add DEBUG _lk_prompt_debug_trap
}
