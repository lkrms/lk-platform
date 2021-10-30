#!/bin/bash

function lk_script_running() {
    [ "${BASH_SOURCE+${BASH_SOURCE[*]: -1}}" = "$0" ]
}

# lk_verbose [LEVEL]
#
# Return true if LK_VERBOSE is at least LEVEL, or at least 1 if LEVEL is not
# specified.
#
# The default value of LK_VERBOSE is 0.
function lk_verbose() {
    [ "${LK_VERBOSE:-0}" -ge "${1-1}" ]
}

# lk_debug
#
# Return true if LK_DEBUG is set.
function lk_debug() {
    [ "${LK_DEBUG-}" = Y ]
}

function lk_root() {
    [ "$EUID" -eq 0 ]
}

# lk_true VAR
#
# Return true if VAR or ${!VAR} is 'Y', 'yes', '1', 'true', or 'on' (not
# case-sensitive).
function lk_true() {
    local REGEX='^([yY]([eE][sS])?|1|[tT][rR][uU][eE]|[oO][nN])$'
    [[ $1 =~ $REGEX ]] || [[ ${1:+${!1-}} =~ $REGEX ]]
}

# lk_false VAR
#
# Return true if VAR or ${!VAR} is 'N', 'no', '0', 'false', or 'off' (not
# case-sensitive).
function lk_false() {
    local REGEX='^([nN][oO]?|0|[fF][aA][lL][sS][eE]|[oO][fF][fF])$'
    [[ $1 =~ $REGEX ]] || [[ ${1:+${!1-}} =~ $REGEX ]]
}

#### Reviewed: 2021-10-04
