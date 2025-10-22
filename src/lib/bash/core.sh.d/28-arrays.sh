#!/usr/bin/env bash

# lk_arr [-COMMAND] [ARRAY...]
function lk_arr() {
    local _CMD="printf '%s\n'" _sh _SH=
    [[ ${1-} != -* ]] || { _CMD=${1#-} && shift; }
    while [ $# -gt 0 ]; do
        _sh=" \"\${$1[@]}\""
        _SH+=${!1+$_sh}
        shift
    done
    # Print nothing if no array members were found
    [ -z "${_SH:+1}" ] || eval "$_CMD$_SH"
}

# lk_args [-COMMAND|--] [ARG...]
function lk_args() {
    local _CMD="printf '%s\n'"
    [[ ${1-} != -* ]] || { { [[ $1 == -- ]] || _CMD=${1#-}; } && shift; }
    ((!$#)) || eval "$_CMD \"\$@\""
}

# lk_in_array VALUE ARRAY...
function lk_in_array() {
    local IFS=$' \t\n'
    lk_arr "${@:2}" | grep -Fx -- "$1" >/dev/null
}

# lk_quote_arr [ARRAY...]
function lk_quote_arr() {
    lk_arr -lk_quote_args "$@"
}

# lk_implode_arr GLUE [ARRAY...]
function lk_implode_arr() {
    local GLUE=$1
    shift
    lk_arr -"printf '%s\0'" "$@" | _LK_INPUT_DELIM= lk_implode_input "$GLUE"
}

# lk_ere_implode_arr [-e] [ARRAY...]
function lk_ere_implode_arr() {
    local ARGS
    [ "${1-}" != -e ] || { ARGS=(-e) && shift; }
    lk_arr "$@" | lk_ere_implode_input ${ARGS+"${ARGS[@]}"}
}

# lk_arr_remove ARRAY VALUE
function lk_arr_remove() {
    local _SH
    _SH=$(eval "for _i in \${$1+\"\${!$1[@]}\"}; do
    [ \"\${$1[_i]}\" != \"\$2\" ] || echo \"unset \\\"$1[\$_i]\\\"\"
done") && eval "$_SH"
}

# lk_arr_from ARRAY COMMAND [ARG...]
#
# Populate ARRAY with each line of output from COMMAND.
function lk_arr_from() {
    (($# > 1)) || lk_bad_args || return
    lk_mapfile "$1" < <(shift && "$@")
}

# lk_arr_intersect ARRAY ARRAY2...
#
# Print ARRAY values that are present in at least one of the subsequent arrays.
function lk_arr_intersect() {
    (($# > 1)) || lk_bad_args || return
    comm -12 <(lk_arr "$1" | sort -u) <(shift && lk_arr "$@" | sort -u)
}

# lk_arr_complement ARRAY ARRAY2...
#
# Print ARRAY values that are not present in any of the subsequent arrays.
function lk_arr_complement() {
    (($# > 1)) || lk_bad_args || return
    comm -23 <(lk_arr "$1" | sort -u) <(shift && lk_arr "$@" | sort -u)
}

#### Reviewed: 2021-11-16
