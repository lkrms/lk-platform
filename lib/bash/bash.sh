#!/bin/bash
# shellcheck disable=SC2002

function lk_bash_array_literals() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '..|select(type=="object")|.Array|select(. != null).Elems[].Value.Parts[]|select(.Type=="Lit").Value'
}

# lk_bash_udf_defaults [STACKSCRIPT_PATH]
#
# Output Bash variable assignments for UDF tags found in the Linode StackScript
# at STACKSCRIPT_PATH or on standard input.
#
function lk_bash_udf_defaults() {
    local XML_PREFIX_REGEX="[a-zA-Z_][-a-zA-Z0-9._]*"
    echo "export -n \\"
    cat ${1+"$1"} |
        grep -E "^.*<($XML_PREFIX_REGEX:)?UDF name=\"([^\"]+)\"" "$1" |
        sed -E \
            -e "s/^.*<($XML_PREFIX_REGEX:)?UDF name=\"([^\"]+)\".* default=\"([^\"]*)\".*/    \2=\${\2:-\3} \\\\/" \
            -e "s/^.*<($XML_PREFIX_REGEX:)?UDF name=\"([^\"]+)\".*/    \2=\${\2:-} \\\\/"
}
