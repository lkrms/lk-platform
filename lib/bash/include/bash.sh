#!/bin/bash

# shellcheck disable=SC2002

function lk_bash_is_builtin() {
    [ "$(type -t "$1")" = builtin ]
}

# lk_bash_function_names [-H] [FILE...]
#
# Print the name of each Bash function declared in FILE. If -H is set, add
# "FILE:" to the beginning of each line.
function lk_bash_function_names() {
    local WITH_FILENAME
    [ "${1-}" != -H ] || { WITH_FILENAME=1 && shift; }
    [ $# -gt 0 ] || set -- /dev/stdin
    while [ $# -gt 0 ]; do
        if [ ${WITH_FILENAME:-0} -eq 1 ]; then
            lk_bash_function_names "$1" |
                sed -E "s/^/$(lk_escape_ere_replace "$1"):/"
        else
            shfmt -tojson <"$1" | jq -r \
                '..|select(type=="object" and .Type=="FuncDecl").Name.Value'
        fi
        shift
    done
}

# lk_bash_function_declarations ROOT_DIR
#
# Print "FUNCTION_NAME TIMES_DECLARED FILE[:FILE]" for each Bash function
# declared in ROOT_DIR.
function lk_bash_function_declarations() {
    local DIR
    [ $# -eq 1 ] && DIR=$(cd "$1" && pwd -P) ||
        lk_warn "directory not found: ${1-}" || return
    local PROG='
function print_pending() {
    if (pending) {
        print fn, count, pending
    }
}
{
    file = "." substr($1, length(dir) + 1)
    if (fn == $2) {
        pending = pending ":" file
        count++
    } else {
        print_pending()
        fn = $2
        pending = file
        count = 1
    }
}
END {
    print_pending()
}'
    lk_bash_find_scripts -d "$DIR" -print0 |
        lk_xargs -z lk_bash_function_names -H |
        sort -u |
        sort -t: -k2 |
        awk -F: -v "dir=${DIR%/}" "$PROG"
}

function lk_bash_local_variable_names() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '..|select(type=="object" and .Type=="DeclClause" and .Variant.Value=="local").Args[].Name.Value'
}

function lk_bash_unset_local_variable_names() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '..|select(type=="object" and .Type=="DeclClause" and .Variant.Value=="local").Args[]|select(.Naked).Name.Value'
}

function lk_bash_command_literals() {
    local EXEC_COMMANDS=(
        command
        exec
        lk_cache
        lk_elevate
        lk_elevate_if_error
        lk_get_outputs_of
        lk_keep_trying
        lk_log_bypass
        lk_log_bypass_stderr
        lk_log_bypass_stdout
        lk_log_bypass_tty
        lk_log_bypass_tty_stderr
        lk_log_bypass_tty_stdout
        lk_log_no_bypass
        lk_maybe_drop
        lk_maybe_elevate
        lk_maybe_sudo
        lk_maybe_trace
        lk_pass
        lk_require_output
        lk_run
        lk_run_as
        lk_run_detail
        lk_tty
        lk_xargs
        xargs
    )
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r \
            --arg regex "^$(lk_regex_implode "$EXEC_COMMANDS")\$" \
            '..|select(type=="object")|((.Args[0].Parts[0]|select(.Type=="Lit").Value),(select(.Args[]?.Parts[]?|select(type=="object" and .Type=="Lit" and (.Value|test($regex)))|length>0)|[.Args[].Parts[]|(if .Type=="Lit" then (if .Value|test($regex) then "" else .Value end) else null end)]|first|select(.!=null)))'
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
    [ "${1-}" != -d ] || { DIR=$(cd "$2" && pwd -P) && shift 2 || return; }
    gnu_find "${DIR:-.}" \
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
    local IFS=$'\n' FILE SCRIPT _COMMANDS FUNCTIONS COMMAND _PATH
    [ "${1-}" != -g ] &&
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
        _COMMANDS=($(echo "$SCRIPT" | lk_bash_command_literals |
            lk_filter '! lk_bash_is_builtin')) &&
        FUNCTIONS=($(for s in <(echo "$SCRIPT") "${@:2}"; do
            lk_bash_function_names "$s"
        done)) || return
    COMMANDS=($(comm -23 \
        <(lk_echo_array _COMMANDS | sort -u) \
        <(lk_echo_array FUNCTIONS | sort -u)))
    # Add functions that are also commands on the local system
    COMMANDS+=($(type -P $(comm -12 \
        <(lk_echo_array _COMMANDS | sort -u) \
        <(lk_echo_array FUNCTIONS | sort -u) |
        sed -E '/^_?lk_/d') | sed -E 's/.*\/([^/]+)$/\1/'))
    [ -n "${COMMANDS+1}" ] || {
        lk_console_message "No external commands used${FILE:+ in $1}"
        return 0
    }
    lk_echo_array COMMANDS | sort |
        lk_console_list "External commands used${FILE:+ in $1}:"
    COMMAND_FILES=()
    MISSING_COMMANDS=()
    PACKAGES=()
    for COMMAND in "${COMMANDS[@]}"; do
        [[ ! $COMMAND =~ ^(lk_|\./) ]] || continue
        _PATH=$(type -P "$COMMAND") &&
            _PATH=$(_lk_realpath "$_PATH") &&
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
    unset GLOBALS
    [ "${1-}" != -g ] || { GLOBALS=1 && shift; }
    DIR=${1:+$(cd "$1" && pwd -P)} || return
    SH=$(lk_bash_find_scripts ${DIR:+-d "$DIR"} -print0 | {
        lk_mapfile -z FILES &&
            declare -p FILES
    }) && eval "$SH" || return
    lk_echo_args "${FILES[@]#${DIR:-.}/}" |
        lk_console_list "Auditing:" script scripts
    lk_bash_audit ${GLOBALS+-g} <(cat "${FILES[@]}")
}

# lk_linode_get_udf_vars [-n] [STACKSCRIPT]
#
# Output shell variable assignments for the Linode UDF tags in input or
# STACKSCRIPT. If -n is set, format the output as an `export -n` command.
#
# Example:
#
#     $ lk_linode_get_udf_vars -n <<EOF
#     # <UDF name="_HOSTNAME" label="Short hostname" />
#     # <UDF name="_TIMEZONE" label="Timezone" default="UTC" />
#     EOF
#     export -n \
#         _HOSTNAME=${_HOSTNAME-} \
#         _TIMEZONE=${_TIMEZONE:-UTC}
function lk_linode_get_udf_vars() {
    local EXPORT REGEX REGEX_DEFAULT OUTPUT
    unset EXPORT
    [ "${1-}" != -n ] || { EXPORT= && shift; }
    REGEX="[a-zA-Z_][-a-zA-Z0-9._]*"
    REGEX="^.*<($REGEX:)?UDF name=\"([^\"]+)\".*"
    REGEX_DEFAULT="$REGEX default=\"([^\"]+)\".*"
    OUTPUT=$(
        [ -z "${EXPORT+1}" ] || echo "export -n \\"
        cat ${1+"$1"} | sed -En "\
s/$REGEX_DEFAULT/${EXPORT+    }\2=\${\2:-\3}${EXPORT+ \\\\}/p
s/$REGEX/${EXPORT+    }\2=\${\2-}${EXPORT+ \\\\}/p"
    ) && echo "${OUTPUT% \\}"
}

lk_provide bash
