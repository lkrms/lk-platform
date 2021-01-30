#!/bin/bash

# shellcheck disable=SC2002,SC2015,SC2120,SC2207

function lk_bash_is_builtin() {
    [ "$(type -t "$1")" = builtin ]
}

function lk_bash_function_names() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '..|select(type=="object" and .Type=="FuncDecl").Name.Value'
}

function lk_bash_command_literals() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '..|select(type=="object").Args[0].Parts[0]|select(.Type=="Lit").Value'
}

function lk_bash_array_literals() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r "\
..|select(type==\"object\" and .Array!=null).Array.Elems[].Value.Parts[]|(
    select(.Type==\"Lit\" or .Type==\"SglQuoted\"),
    select(.Type==\"DblQuoted\" and (.Parts|length)==1 and .Parts[0].Type==\"Lit\").Parts[0]
).Value"
}

# lk_bash_find_scripts [-d DIR] [FIND_ACTION...]
function lk_bash_find_scripts() {
    local DIR
    [ "${1:-}" != -d ] || { DIR=$(cd "$2" && pwd -P) && shift 2 || return; }
    find "${DIR:-.}" \
        ! \( \( \( -type d -name .git \) -o ! -readable \) -prune \) \
        -type f \
        \( -name '*.sh' -o -exec \
        sh -c 'head -c12 "$1" | grep -Eq "^#!/bin/(ba)?sh\\>"' sh '{}' \; \) \
        \( "${@--print}" \)
}

# lk_bash_audit [-g] SCRIPT [SOURCE...]
#
# Print a summary of commands used in SCRIPT that are not functions declared in
# SCRIPT or any SOURCE. If -g is set, store results in global array variables:
# - COMMANDS
# - COMMAND_FILES
# - MISSING_COMMANDS
# - PACKAGES
function lk_bash_audit() {
    local LC_ALL=C IFS=$'\n' FILE SCRIPT FUNCTIONS COMMAND _PATH
    export LC_ALL
    [ "${1:-}" != -g ] &&
        { local COMMANDS COMMAND_FILES MISSING_COMMANDS PACKAGES; } || shift
    lk_paths_exist "$@" || lk_usage "\
Usage: $(lk_myself -f) [-g] SCRIPT [SOURCE...]

Print a summary of commands used in SCRIPT that are not functions declared in
SCRIPT or any SOURCE. If -g is set, store results in global array variables:
- COMMANDS
- COMMAND_FILES
- MISSING_COMMANDS
- PACKAGES" || return
    FILE=${1##/dev/fd/*}
    SCRIPT=$(cat "$1") &&
        COMMANDS=($(echo "$SCRIPT" | lk_bash_command_literals |
            lk_filter '! lk_bash_is_builtin')) &&
        FUNCTIONS=($(for s in <(echo "$SCRIPT") "${@:2}"; do
            lk_bash_function_names "$s"
        done)) || return
    COMMANDS=($(comm -23 \
        <(lk_echo_array COMMANDS | sort -u) \
        <(lk_echo_array FUNCTIONS | sort -u)))
    [ -n "${COMMANDS+1}" ] || {
        lk_console_message "No external commands used${FILE:+ in $1}"
        return 0
    }
    lk_echo_array COMMANDS |
        lk_console_list "External commands used${FILE:+ in $1}:"
    COMMAND_FILES=()
    MISSING_COMMANDS=()
    PACKAGES=()
    for COMMAND in "${COMMANDS[@]}"; do
        [[ ! $COMMAND =~ ^(lk_|\./) ]] || continue
        _PATH=$(which "$COMMAND" 2>/dev/null) &&
            _PATH=$(realpath "$_PATH") &&
            COMMAND_FILES[${#COMMAND_FILES[@]}]=$_PATH$(
                [ "${COMMAND##*/}" = "${_PATH##*/}" ] || echo " ($COMMAND)"
            ) &&
            PACKAGES[${#PACKAGES[@]}]=$_PATH ||
            MISSING_COMMANDS[${#MISSING_COMMANDS[@]}]=$COMMAND
    done
    [ ${#MISSING_COMMANDS[@]} -eq 0 ] ||
        lk_echo_array MISSING_COMMANDS |
        lk_console_detail_list "Not installed:"
    COMMAND_FILES=($(lk_echo_array COMMAND_FILES | sort -u))
    PACKAGES=($(lk_echo_array PACKAGES | sort -u))
    PACKAGES=($(
        if lk_is_arch; then
            pacman -Qo "${PACKAGES[@]}" |
                awk -v fs=" is owned by " \
                    'BEGIN{FS=fs}{if($2){f=$1;FS=" ";$0=$2;print$1": "f;FS=fs}}'
        elif lk_is_ubuntu; then
            dpkg -S "${PACKAGES[@]}"
        fi | sort -u | tee -a >(lk_console_list "Command owners:") || true
    ))
    lk_echo_array PACKAGES | awk -F: '{print$1}' | sort -u |
        lk_console_detail_list "Packages:"
}

# lk_bash_audit_tree [-g] [DIR]
function lk_bash_audit_tree() {
    local GLOBALS DIR SH FILES
    [ "${1:-}" != -g ] || { GLOBALS=1 && shift; }
    DIR=${1:+$(cd "$1" && pwd -P)} || return
    SH=$(lk_bash_find_scripts ${DIR:+-d "$DIR"} -print0 | {
        lk_mapfile -z FILES &&
            declare -p FILES
    }) && eval "$SH" || return
    lk_echo_args "${FILES[@]#${DIR:-.}/}" |
        lk_console_list "Auditing:" script scripts
    lk_bash_audit ${GLOBALS+-g} <(cat "${FILES[@]}")
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

lk_provide bash
