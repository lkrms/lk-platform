#!/usr/bin/env bash

# lk_ssh_host_parameter_sh [USER@]<HOST>[:PORT] <VAR_PREFIX> [PARAMETER...]
#
# Always included: user, hostname, port, identityfile
function lk_ssh_host_parameter_sh() {
    [[ ${1-} =~ ^(^([^@]+)@)?([^@:]+)(:([0-9]+))?$ ]] || return
    local user=${BASH_REMATCH[2]} host=${BASH_REMATCH[3]} \
        port=${BASH_REMATCH[5]} PREFIX=${2-} AWK
    shift 2 &&
        lk_awk_load AWK sh-get-ssh-host-parameters || return
    ssh -G ${port:+-p "$port"} "${user:+$user@}$host" |
        awk -v prefix="$PREFIX" -f "$AWK" "$@"
}

# lk_ssh_run_on_host [options] [USER@]<HOST>[:PORT] [sudo] <COMMAND> [ARG...]
#
# Run COMMAND on HOST after loading the given Bash functions and libraries
# (including COMMAND itself, if it is a Bash function)
#
# Options:
#
#     -f FUNCTION   Declare FUNCTION on the remote system before running COMMAND
#     -l LIBRARY    Add LIBRARY and any dependencies to the generated script
#
# - `-f` and `-l` may be given multiple times
# - If `-l` is set, the `core` library is added automatically
# - Use `-l core` to add the `core` library only
# - Values applied to `-l` correspond to arguments passed to `lk_require`
function lk_ssh_run_on_host() {
    local FUNC=() LIB=() LIB_DIR=$LK_BASE/lib/bash/include
    while (($# > 1)) && [[ $1 == -* ]]; do
        case "$1" in
        -f)
            FUNC[${#FUNC[@]}]=$2
            ;;
        -l)
            local FILE=$LIB_DIR/$2.sh
            [[ -r $FILE ]] || lk_warn "file not found: $FILE" || return
            LIB[${#LIB[@]}]=$2
            ;;
        *)
            false || lk_warn "invalid argument: $1" || return
            ;;
        esac
        shift 2
    done
    [[ ${2-} != sudo ]] && (($# > 1)) || (($# > 2)) ||
        lk_warn "invalid arguments" || return
    local HOST=$1 SUDO SH
    shift
    unset SUDO
    [[ $1 != sudo ]] || { SUDO= && shift; }
    [[ $(type -t "$1") != function ]] || FUNC[${#FUNC[@]}]=$1
    # Add the requested functions and libraries, and any dependencies, to a
    # temporary file
    lk_mktemp_with SH || return
    {
        [[ -z ${LIB+1} ]] || (
            LAST=0
            while :; do
                lk_mapfile LIB < <(
                    FILES=("${LIB[@]/#/$LIB_DIR/}")
                    FILES=("${FILES[@]/%/.sh}")
                    { lk_arr LIB && sed -En \
                        's/^lk_require ([-a-zA-Z0-9_ ]+)$/\1/p' "${FILES[@]}" |
                        tr -s '[:blank:]' '\n'; } |
                        sed '/^core$/d' |
                        lk_uniq
                )
                ((LAST < ${#LIB[@]})) || break
                LAST=${#LIB[@]}
            done
            FILES=("${LIB[@]/#/$LIB_DIR/}")
            IFS=,
            sed -E "s/^(_LK_SOURCED=).*/\1core${LIB+,${LIB[*]}}/" \
                "$LIB_DIR/core.sh" || return
            unset IFS
            [[ -z ${FILES+1} ]] ||
                cat "${FILES[@]/%/.sh}" || return
        )
        [[ -z ${FUNC+1} ]] || {
            lk_mapfile FUNC < <(lk_arr FUNC | lk_uniq) &&
                declare -f "${FUNC[@]}" || return
        }
        lk_quote_args "$@"
    } >"$SH" || return
    local REMOTE_SH STATUS=0 ARGS=(
        -o ControlMaster=auto
        -o ControlPath="/tmp/.${FUNCNAME}_%C-%u"
        -o ControlPersist=60
    )
    lk_debug || ARGS+=(-o LogLevel=QUIET)
    [[ ! $HOST =~ :[0-9]+$ ]] || {
        ARGS+=(-o Port="${HOST##*:}")
        HOST=${HOST%:*}
    }
    REMOTE_SH=$(ssh "${ARGS[@]}" "$HOST" mktemp) || return
    scp -pq "${ARGS[@]}" "$SH" "$HOST:$REMOTE_SH" &&
        ssh -tt "${ARGS[@]}" "$HOST" \
            "${SUDO+sudo }LK_TTY_HOSTNAME=1 bash $(
                lk_quote_args "$REMOTE_SH"
            )" || STATUS=$?
    ssh "${ARGS[@]}" "$HOST" "rm -f $(lk_quote_args "$REMOTE_SH")" || true
    return "$STATUS"
}
