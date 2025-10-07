#!/usr/bin/env bash

# _lk_prompt_trap_debug
#
# Collect commands for the next prompt string.
function _lk_prompt_trap_debug() {
    # Don't collect anything before the first prompt
    if ((!_LK_PROMPT_SEEN)) || [[ $BASH_COMMAND == "$PROMPT_COMMAND" ]]; then
        return
    fi

    # Normalise arguments without unsafe expansion
    local command=($BASH_COMMAND) IFS=' '
    if [[ -z ${_LK_PROMPT+1} ]]; then
        _LK_PROMPT_START=$(lk_timestamp)
        _LK_PROMPT_FIRST=$command
    fi
    _LK_PROMPT[${#_LK_PROMPT[@]}]=${command[*]}
}

# _lk_prompt_command
#
# Create a prompt string with current time, last command, elapsed time, exit
# status and Git status.
function _lk_prompt_command() {
    local status=$? part parts=()
    history -a
    # Prevent unsafe prompt string expansion
    shopt -u promptvars
    if [[ -n ${_LK_PROMPT+1} ]]; then
        local elapsed=$(($(lk_timestamp) - _LK_PROMPT_START))
        # If the last command failed, ran for at least 2 seconds, or is not a
        # builtin, add a summary line
        if ((status || elapsed > 1 || ${#_LK_PROMPT[@]} > 1)) ||
            [[ $(type -t "$_LK_PROMPT_FIRST") != builtin ]]; then
            # Start with these 26 columns: "Thu May 06 15:02:32 ✓ (  )"
            local width=26
            # "Thu May 06 15:02:32 "
            parts[${#parts[@]}]="\n\[$LK_DIM\]\d \t\[$LK_UNDIM\] "
            if ((!status)); then
                # "✓"
                parts[${#parts[@]}]="\[$LK_GREEN\]✓"
            else
                # "✗ returned 1"
                part=" returned $status"
                parts[${#parts[@]}]="\[$LK_RED\]✗$part"
                ((width += ${#part}))
            fi
            # " after 12s"
            if ((elapsed < 120)); then
                elapsed+=s
            else
                elapsed=$(lk_duration "$elapsed")
            fi
            part=" after $elapsed"
            parts[${#parts[@]}]="$part\[$LK_DEFAULT\]"
            width=$((COLUMNS - width - ${#part}))
            if ((width > 0)); then
                # " ( sleep 12; false )"
                local IFS=' '
                parts[${#parts[@]}]=" \[$LK_DIM\]( $(
                    set -- "${_LK_PROMPT[@]}"
                    { printf '%s' "$1" && shift && { ((!$#)) || printf '; %s' "$@"; }; } |
                        _lk_prompt_sanitise |
                        head -c"$width"
                ) )\[$LK_UNDIM\]"
            fi
            # "\n"
            parts[${#parts[@]}]="\n"
        fi
        _LK_PROMPT=()
    fi
    if ((EUID)); then
        # "ubuntu@"
        parts[${#parts[@]}]="\[$LK_BOLD$LK_GREEN\]\u@"
    else
        # "root@"
        parts[${#parts[@]}]="\[$LK_BOLD$LK_RED\]\u@"
    fi
    # "host1 ~"
    parts[${#parts[@]}]="\h \[$LK_BLUE\]\w\[$LK_DEFAULT$LK_UNBOLD\]"
    if ((EUID)) && [[ $(type -t __git_ps1) == function ]]; then
        part=$(GIT_PS1_SHOWCOLORHINTS=1 __git_ps1 '%s')
        if [[ -n ${part:+1} ]]; then
            # "(main)"
            parts[${#parts[@]}]="\[$LK_YELLOW\](\[$LK_DEFAULT\]$part\[$LK_YELLOW\])\[$LK_DEFAULT\]"
        fi
    fi
    if [[ -n ${LK_PROMPT_TAG:+1} ]]; then
        # " .tag."
        parts[${#parts[@]}]=" \[$LK_WHITE$LK_MAGENTA_BG\] \[$LK_BOLD\]${LK_PROMPT_TAG}\[$LK_UNBOLD\] \[$LK_DEFAULT_BG$LK_DEFAULT\]"
    fi
    local IFS=
    # " $ " or " # "
    PS1="${parts[*]} \\\$ "
    _LK_PROMPT_SEEN=1
    # Remove `history -a;history -r;` added by Byobu, for example
    lk_bash_at_least 5 1 &&
        PROMPT_COMMAND=(_lk_prompt_command) ||
        PROMPT_COMMAND=_lk_prompt_command
    # Speaking of Byobu, prevent nested sessions
    [[ ${LC_BYOBU:+1}${BYOBU_TERM:+2} != 2 ]] || export LC_BYOBU=0
}

# lk_prompt_enable
#
# Enable the lk-platform Bash prompt.
function lk_prompt_enable() {
    eval "$(lk_get_regex NON_PRINTING_REGEX)"
    eval "function _lk_prompt_sanitise() {
    LC_ALL=C sed -E $(
        printf '%q' "s/$NON_PRINTING_REGEX//g; "$'s/.*\r(.)/\\1/'
    ) | tr -d '\\0-\\10\\16-\\37\\177'
}"
    _LK_PROMPT_SEEN=0
    _LK_PROMPT=()
    lk_bash_at_least 5 1 &&
        PROMPT_COMMAND=(_lk_prompt_command) ||
        PROMPT_COMMAND=_lk_prompt_command
    # On Bash 3.2, DEBUG handlers need to be removed before they can be replaced
    trap - DEBUG
    trap _lk_prompt_trap_debug DEBUG
}

#### Reviewed: 2025-07-03
