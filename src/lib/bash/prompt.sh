#!/bin/bash

function _lk_prompt_trap() {
    if ((${_LK_PROMPT_DISPLAYED-0})) &&
        [[ $BASH_COMMAND != "$PROMPT_COMMAND" ]]; then
        if [[ -z ${_LK_PROMPT_LAST+1} ]]; then
            _LK_PROMPT_LAST_START=$(lk_date %s)
            _LK_PROMPT_LAST=($BASH_COMMAND)
            return
        fi
        _LK_PROMPT_LAST[${#_LK_PROMPT_LAST[@]}]=';'
        _LK_PROMPT_LAST+=($BASH_COMMAND)
    fi
}

function _lk_prompt_command() {
    # "Thu May 06 15:02:32 ✔( )" is 24 characters wide
    local STATUS=$? SECS PS=() STR LEN=24 IFS
    # Append the last command to HISTFILE
    history -a
    # Suppress expansion of prompt strings
    shopt -u promptvars
    if [[ -n ${_LK_PROMPT_LAST+1} ]]; then
        SECS=$(($(lk_date %s) - _LK_PROMPT_LAST_START))
        if ((STATUS)) ||
            ((SECS > 1)) ||
            [[ $(type -t "$_LK_PROMPT_LAST") != builtin ]]; then
            # "Thu May 06 15:02:32 "
            PS+=("\n\[$LK_DIM\]\d \t\[$LK_UNDIM\] ")
            if ((!STATUS)); then
                # "✔"
                PS+=("\[$LK_GREEN\]"$'\xe2\x9c\x94')
            else
                # "✘ returned 1"
                STR=" returned $STATUS"
                PS+=("\[$LK_RED\]"$'\xe2\x9c\x98'"$STR")
                ((LEN += ${#STR}))
            fi
            # " after 12s "
            if ((SECS < 120)); then
                SECS+=s
            else
                SECS=$(lk_duration "$SECS")
            fi
            STR=" after $SECS "
            PS+=("$STR\[$LK_DEFAULT$LK_DIM\]")
            LEN=$((COLUMNS - LEN - ${#STR}))
            if ((LEN > 0)); then
                # "( sleep 12; false )"
                unset IFS
                PS+=("($(printf ' %s' "${_LK_PROMPT_LAST[@]}" |
                    lk_prompt_sanitise |
                    head -c"$LEN") )")
            fi
            # "\n"
            PS+=("\[$LK_UNDIM\]\n")
        fi
        _LK_PROMPT_LAST=()
    fi
    if ((EUID)); then
        # "ubuntu@"
        PS+=("\[$LK_BOLD$LK_GREEN\]\u@")
    else
        # "root@"
        PS+=("\[$LK_BOLD$LK_RED\]\u@")
    fi
    # "host1 ~ "
    PS+=("\h\[$LK_BLUE\] \w \[$LK_DEFAULT$LK_UNBOLD\]")
    [[ -z ${LK_PROMPT_TAG:+1} ]] ||
        PS+=("\[$LK_WHITE$LK_MAGENTA_BG\] \[$LK_BOLD\]${LK_PROMPT_TAG}\[$LK_UNBOLD\] \[$LK_DEFAULT_BG$LK_DEFAULT\] ")
    IFS=
    # "$ " or "# "
    PS1="${PS[*]}\\\$ "
    _LK_PROMPT_DISPLAYED=1
    [[ ${LC_BYOBU:+1}${BYOBU_TERM:+2} != 2 ]] || export LC_BYOBU=0
}

function lk_prompt_enable() {
    eval "$(lk_get_regex NON_PRINTING_REGEX)"
    eval "function lk_prompt_sanitise() {
    LC_ALL=C sed -E $(
        printf '%q' "s/$NON_PRINTING_REGEX//g; "$'s/.*\r(.)/\\1/'
    ) | tr -d '\\0-\\10\\16-\\37\\177'
}"
    unset _LK_PROMPT_DISPLAYED
    _LK_PROMPT_LAST=()
    PROMPT_COMMAND=_lk_prompt_command
    trap _lk_prompt_trap DEBUG
}
