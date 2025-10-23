#!/usr/bin/env bash

shopt -s extglob

[[ ${USER-} ]] || USER=$(id -un) || return

# Provide horizontal whitespace patterns known to work everywhere
LK_h=$'[ \t]'
LK_H=$'[^ \t]'

# Collect arguments passed to the current script or function
_LK_ARGV=("$@")

#### Reviewed: 2025-10-18
