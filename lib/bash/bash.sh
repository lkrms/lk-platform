#!/bin/bash
# shellcheck disable=SC2002

function lk_bash_array_literals() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '..|select(type=="object")|.Array|select(. != null).Elems[].Value.Parts[]|select(.Type=="Lit").Value'
}

# lk_bash_udf_defaults [<STACKSCRIPT_PATH>]
#
# Output Bash variable assignments for UDF tags found in the Linode StackScript
# at STACKSCRIPT_PATH or on standard input.
#
function lk_bash_udf_defaults() {
    cat ${1+"$1"} |
        grep -E '^.*<(NO)?UDF name="([^"]+)"' "$1" |
        sed -E \
            -e 's/^.*<(NO)?UDF name="([^"]+)".* default="([^"]*)".*/\2=${\2:-\3}/' \
            -e 's/^.*<(NO)?UDF name="([^"]+)".*/\2=${\2:-}/'
}
