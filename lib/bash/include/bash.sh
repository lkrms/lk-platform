#!/bin/bash

# shellcheck disable=SC2002

function lk_bash_function_names() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '..|select(type=="object" and .Type == "FuncDecl").Name.Value'
}

function lk_bash_command_literals() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '..|select(type=="object").Args[0].Parts[0]|select(.Type=="Lit").Value'
}

function lk_bash_array_literals() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '..|select(type=="object" and .Array!=null).Array.Elems[].Value.Parts[]|select(.Type=="Lit").Value'
}

# lk_bash_udf_defaults [STACKSCRIPT]
#
# Output Bash-compatible variable assignments for each UDF tag in STACKSCRIPT or
# on standard input.
#
# Example:
#
#     $ lk_bash_udf_defaults <<EOF
#     # <UDF name="_HOSTNAME" label="Short hostname" />
#     # <UDF name="_TIMEZONE" label="Timezone" default="UTC" />
#     EOF
#     export -n \
#         _HOSTNAME=${_HOSTNAME:-} \
#         _TIMEZONE=${_TIMEZONE:-UTC}
#
function lk_bash_udf_defaults() {
    local XML_PREFIX_REGEX="[a-zA-Z_][-a-zA-Z0-9._]*" OUTPUT
    OUTPUT=$(
        echo "export -n \\"
        cat ${1+"$1"} |
            grep -E "^.*<($XML_PREFIX_REGEX:)?UDF name=\"([^\"]+)\"" |
            sed -E \
                -e "s/^.*<($XML_PREFIX_REGEX:)?UDF name=\"([^\"]+)\".* default=\"([^\"]*)\".*/    \2=\${\2:-\3} \\\\/" \
                -e "s/^.*<($XML_PREFIX_REGEX:)?UDF name=\"([^\"]+)\".*/    \2=\${\2:-} \\\\/"
    ) && echo "${OUTPUT% \\}"
}
