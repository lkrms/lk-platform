#!/usr/bin/env bash

function lk_bash_is_builtin() {
    [[ $(type -t "$1") == builtin ]]
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
                sed -E "s/^/$(lk_sed_escape_replace "$1"):/"
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
    lk_find_shell_scripts -d "$DIR" -print0 |
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
        _lk_apt_flock
        command
        exec
        lk_cache
        lk_elevate
        lk_env_clean
        lk_faketty
        lk_get_outputs_of
        lk_git_with_repos
        lk_keep_trying
        lk_log_bypass
        lk_log_bypass_stderr
        lk_log_bypass_stdout
        lk_maybe
        lk_maybe_drop
        lk_sudo
        lk_maybe_trace
        lk_mktemp_dir_with
        lk_mktemp_with
        lk_nohup
        lk_pass
        lk_report_error
        lk_require_output
        lk_run_as
        lk_sudo
        lk_tty_run
        lk_tty_run_detail
        lk_unbuffer
        lk_xargs
        sudo
        xargs
    )
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r \
            --arg regex "^$(lk_ere_implode_args -- "$EXEC_COMMANDS")\$" \
            '..|select(type=="object")|((.Args[0].Parts[0]|select(.Type=="Lit").Value),(select(.Args[]?.Parts[]?|select(type=="object" and .Type=="Lit" and (.Value|test($regex)))|length>0)|[.Args[].Parts[]|(if .Type=="Lit" then (if .Value|test($regex) then "" else .Value end) else null end)]|first|select(.!=null)))'
}

function lk_bash_array_literals() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '
..|select(type=="object" and .Array.Elems!=null).Array.Elems[].Value|
    select((.Parts|length)==1).Parts[0]|(
        select(.Type=="Lit" or .Type=="SglQuoted"),
        select(.Type=="DblQuoted" and (.Parts|length)==1 and .Parts[0].Type=="Lit").Parts[0]
    ).Value'
}

# lk_bash_command_type_paths [FILE]
#
# Example output:
#
#     ...
#     FuncDecl      Stmts[9].Cmd
#     Block         Stmts[9].Cmd.Body.Cmd
#     DeclClause    Stmts[9].Cmd.Body.Cmd.Stmts[0].Cmd
#     BinaryCmd     Stmts[9].Cmd.Body.Cmd.Stmts[1].Cmd
#     CallExpr      Stmts[9].Cmd.Body.Cmd.Stmts[1].Cmd.X.Cmd
#     ...
function lk_bash_command_type_paths() {
    cat ${1+"$1"} |
        shfmt -tojson |
        jq -r '
path(..|select(type=="object" and .Cmd.Type)) as $path |
    [getpath($path).Cmd.Type, (($path|join("."))+".Cmd")] | @tsv' |
        sed -E 's/\.([0-9]+)/[\1]/g'
}

# lk_bash_command_cut [-c] [-t <TYPE>] [FILE] [-- <CUT_ARG>...]
#
# For example, `lk_bash_command_cut -c FuncDecl core.sh --complement` removes
# function declarations from `core.sh`, including any comments associated with
# them.
function lk_bash_command_cut() {
    local COMMENTS TYPE=FuncDecl FILE=/dev/stdin
    [[ ${1-} != -c ]] || { COMMENTS=true && shift; }
    [[ ${1-} != -t ]] || { TYPE=${2-} && shift 2 || return; }
    ((!$#)) || [[ $1 == -- ]] || { FILE=${1:-$FILE} && shift; }
    [[ $1 != -- ]] || shift
    [[ -f $FILE ]] || { [[ -e $FILE ]] && lk_mktemp_with FILE cat "$FILE"; } ||
        lk_warn "file not found: $FILE" || return
    cut "$@" -z -b "$(shfmt -tojson <"$FILE" |
        jq -r \
            --arg type "$TYPE" \
            --argjson comments "${COMMENTS:-false}" '
[..|select(type=="object" and .Cmd.Type==$type)|
    (if $comments then .Comments[] else empty end, .Cmd)|
    "\(.Pos.Offset+1)-\(.End.Offset)" ] | join(",")')" <"$FILE" |
        lk_squeeze_whitespace
}

# lk_bash_audit [-g] SCRIPT [SOURCE...]
#
# Print a summary of commands used in SCRIPT that are not functions declared in
# SCRIPT or any SOURCE. If -g is set, store results in the following arrays
# instead of printing a summary:
# - COMMANDS: all non-builtin commands used in SCRIPT
# - COMMAND_FILES: the resolved paths of all installed COMMANDS
# - MISSING_COMMANDS: all COMMANDS that are not installed locally
# - PACKAGES: the names of the packages that own COMMAND_FILES
function lk_bash_audit() {
    local IFS=$'\n' FILE SCRIPT _COMMANDS FUNCTIONS COMMAND _PATH QUIET=1
    [ "${1-}" != -g ] &&
        local COMMANDS COMMAND_FILES MISSING_COMMANDS PACKAGES QUIET= || shift
    lk_test_all_e "$@" || lk_usage "\
Usage: $FUNCNAME [-g] SCRIPT [SOURCE...]" || return
    FILE=${1##/dev/fd/*}
    SCRIPT=$(<"$1") &&
        _COMMANDS=($(lk_bash_command_literals <<<"$SCRIPT" |
            lk_filter '! lk_bash_is_builtin' | sort -u)) &&
        FUNCTIONS=($(for s in <(cat <<<"$SCRIPT") "${@:2}"; do
            lk_bash_function_names "$s"
        done | sort -u)) || return
    COMMANDS=($(comm -23 \
        <(lk_arr _COMMANDS) \
        <(lk_arr FUNCTIONS)))
    # Add functions that are also commands on the local system
    COMMANDS+=($(type -P $(comm -12 \
        <(lk_arr _COMMANDS) \
        <(lk_arr FUNCTIONS) |
        sed -E '/^_?lk_/d') | sed -E 's/.*\/([^/]+)$/\1/'))
    COMMAND_FILES=()
    MISSING_COMMANDS=()
    PACKAGES=()
    [ -n "${COMMANDS+1}" ] || {
        [ -n "$QUIET" ] ||
            lk_tty_print "No external commands used${FILE:+ in $1}"
        return
    }
    [ -n "$QUIET" ] ||
        lk_arr COMMANDS | sort |
        lk_tty_list - "External commands used${FILE:+ in $1}:"
    for COMMAND in "${COMMANDS[@]}"; do
        [[ ! $COMMAND =~ ^(lk_|\./) ]] || continue
        _PATH=$(type -P "$COMMAND") &&
            _PATH=$(lk_realpath "$_PATH") &&
            COMMAND_FILES[${#COMMAND_FILES[@]}]=$_PATH ||
            MISSING_COMMANDS[${#MISSING_COMMANDS[@]}]=$COMMAND
    done
    [ -n "$QUIET" ] ||
        [ ${#MISSING_COMMANDS[@]} -eq 0 ] ||
        lk_tty_list_detail MISSING_COMMANDS "Not installed:"
    [ ${#COMMAND_FILES[@]} -gt 0 ] || return 0
    COMMAND_FILES=($(lk_arr COMMAND_FILES | sort -u))
    PACKAGES=($(
        if lk_system_is_arch; then
            pacman -Qo "${COMMAND_FILES[@]}" |
                awk -F " is owned by " -v OFS=": " \
                    '$2 {split($2, a, " "); print a[1], $1}'
        elif lk_system_is_ubuntu; then
            dpkg -S "${COMMAND_FILES[@]}"
        fi | sort -u || true
    ))
    [ ${#PACKAGES[@]} -gt 0 ] || return 0
    [ -n "$QUIET" ] ||
        lk_tty_list PACKAGES "Command owners:"
    PACKAGES=($(lk_arr PACKAGES | cut -d: -f1 | sort -u))
    [ -n "$QUIET" ] ||
        lk_tty_list PACKAGES "Packages:"
}

# lk_bash_audit_tree [-g] [DIR]
function lk_bash_audit_tree() {
    local GLOBALS DIR SH FILES
    unset GLOBALS
    [ "${1-}" != -g ] || { GLOBALS=1 && shift; }
    DIR=${1:+$(cd "$1" && pwd -P)} || return
    SH=$(lk_find_shell_scripts ${DIR:+-d "$DIR"} -print0 | {
        lk_mapfile -z FILES &&
            declare -p FILES
    }) && eval "$SH" || return
    lk_args "${FILES[@]#${DIR:-.}/}" |
        lk_tty_list - "Auditing:" script scripts
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
        [ -z "${EXPORT+1}" ] || echo 'export -n \'
        cat ${1+"$1"} | sed -En "\
s/$REGEX_DEFAULT/${EXPORT+    }\2=\${\2:-\3}${EXPORT+ \\\\}/p
s/$REGEX/${EXPORT+    }\2=\${\2-}${EXPORT+ \\\\}/p"
    ) && echo "${OUTPUT% \\}"
}
