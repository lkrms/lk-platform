#!/usr/bin/env bash

# _lk_prompt_handle_debug
#
# Collect commands to include in the next prompt string.
function _lk_prompt_handle_debug() {
    if ((_LK_PROMPT_SEEN)) && [[ $BASH_COMMAND != _lk_prompt_create ]]; then
        # The first element of _LK_PROMPT is the command's start time
        [[ ${_LK_PROMPT+1} ]] || _LK_PROMPT[0]=$(lk_timestamp)
        _LK_PROMPT[${#_LK_PROMPT[@]}]=$BASH_COMMAND
    fi
}

# _lk_prompt_create
#
# Create a prompt string with:
#
# - the current time (e.g. "Thu May 06 15:02:32")
# - the exit status and elapsed time of the last command (e.g. " ✗ returned 1
#   after 12s")
# - the last command, reduced to a line of printable characters and truncated if
#   necessary (e.g. " ( sleep 12; false )")
# - the username of the current user
# - the name of the current host
# - the current working directory, abbreviated by replacing `$HOME` with tilde
# - the status of the current Git repository (if `git-prompt.sh` is loaded)
# - the value of `$LK_PROMPT_TAG` (if set)
function _lk_prompt_create() {
    local status=$? part parts=()
    if [[ ${_LK_PROMPT+1} ]]; then
        # 26 columns that will always be present: "Thu May 06 15:02:32 ✓ (  )"
        local now elapsed width=26
        now=$(lk_timestamp)
        set -- "${_LK_PROMPT[@]}"
        elapsed=$((now - $1))
        shift
        # "Thu May 06 15:02:32 "
        parts[${#parts[@]}]="\n\[$LK_DIM\]\d \t\[$LK_UNBOLD_UNDIM\] "
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
        # Add the last command if there is at least 1 column to display it
        if ((width > 0)); then
            local commands
            commands=$({
                printf '%s' "$1"
                shift
                ((!$#)) || printf '; %s' "$@"
            } | _lk_prompt_filter | head -c"$width")
            # " ( sleep 12; false )"
            local IFS=' '
            parts[${#parts[@]}]=" \[$LK_DIM\]( ${commands//\\/\\\\} )\[$LK_UNBOLD_UNDIM\]"
        fi
        parts[${#parts[@]}]="\n"
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
    parts[${#parts[@]}]="\h \[$LK_BLUE\]\w\[$LK_DEFAULT$LK_UNBOLD_UNDIM\]"
    if ((EUID)) && [[ $(type -t __git_ps1) == function ]]; then
        part=$(GIT_PS1_SHOWCOLORHINTS=1 __git_ps1 '%s')
        if [[ ${part:+1} ]]; then
            # "(main)"
            parts[${#parts[@]}]="\[$LK_YELLOW\](\[$LK_DEFAULT\]$part\[$LK_YELLOW\])\[$LK_DEFAULT\]"
        fi
    fi
    if [[ ${LK_PROMPT_TAG:+1} ]]; then
        # " <sp>tag<sp>"
        parts[${#parts[@]}]=" \[$LK_WHITE$LK_MAGENTA_BG\] \[$LK_BOLD\]${LK_PROMPT_TAG}\[$LK_UNBOLD_UNDIM\] \[$LK_DEFAULT_BG$LK_DEFAULT\]"
    fi
    history -a
    shopt -u promptvars
    local IFS=
    # " $ " or " # "
    PS1="${parts[*]} \\\$ "
    _LK_PROMPT_SEEN=1
    # Remove `history -a;history -r;` added by Byobu, for example
    # shellcheck disable=SC2178
    lk_bash_is 5 1 &&
        PROMPT_COMMAND=(_lk_prompt_create) ||
        PROMPT_COMMAND=_lk_prompt_create
    # Speaking of Byobu, prevent nested sessions
    [[ ${LC_BYOBU:+1}${BYOBU_TERM:+2} != 2 ]] || export LC_BYOBU=0
}

#### INCLUDE prompt.sh.d

# lk_prompt_enable
#
# Enable the lk-platform Bash prompt.
function lk_prompt_enable() {
    _LK_PROMPT_SEEN=0
    _LK_PROMPT=()
    # shellcheck disable=SC2178
    lk_bash_is 5 1 &&
        PROMPT_COMMAND=(_lk_prompt_create) ||
        PROMPT_COMMAND=_lk_prompt_create
    # On Bash 3.2, DEBUG handlers need to be removed before they can be replaced
    trap - DEBUG
    trap _lk_prompt_handle_debug DEBUG
}

#### Reviewed: 2025-10-31
