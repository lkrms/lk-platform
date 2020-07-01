#!/bin/bash
# shellcheck disable=SC2002

function lk_bash_array_literals() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '..|select(type=="object")|.Array|select(. != null).Elems[].Value.Parts[]|select(.Type=="Lit").Value'
}
