#!/bin/bash

function lk_script_is_running() {
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
    [[ ${LK_DEBUG-} =~ ^[1Yy]$ ]]
}

#### Reviewed: 2021-09-06
