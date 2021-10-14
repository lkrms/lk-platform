#!/bin/bash

export -n BASH_XTRACEFD SHELLOPTS
export LC_ALL=C

USER=${USER:-$(id -un)} &&
    { [ "${S-}" = "[[:blank:]]" ] || readonly S="[[:blank:]]"; } &&
    { [ "${NS-}" = "[^[:blank:]]" ] || readonly NS="[^[:blank:]]"; } || return

_LK_ARGV=("$@")
_LK_PROVIDED=core

#### Reviewed: 2021-10-14
