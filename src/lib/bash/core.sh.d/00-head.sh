#!/usr/bin/env bash

shopt -s extglob

export -n BASH_XTRACEFD SHELLOPTS

USER=${USER:-$(id -un)} &&
    { [[ ${S-} == "[[:blank:]]" ]] || readonly S="[[:blank:]]"; } &&
    { [[ ${NS-} == "[^[:blank:]]" ]] || readonly NS="[^[:blank:]]"; } || return

_LK_ARGV=("$@")
