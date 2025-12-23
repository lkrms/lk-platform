#!/usr/bin/env bash

set -euo pipefail
lk_die() { echo "${BASH_SOURCE-$0}: $1" >&2 && false || exit; }

_DIR=${BASH_SOURCE%"${BASH_SOURCE##*/}"}
LK_BASE=$(cd "${_DIR:-.}/../.." && pwd -P) &&
    [ "$LK_BASE/lib/platform/${BASH_SOURCE##*/}" -ef "$BASH_SOURCE" ] &&
    export LK_BASE || lk_die "LK_BASE not found"

. "$LK_BASE/lib/bash/common.sh"

LK_USAGE="\
Usage: ${0##*/} [OPTION...] -- COMMAND [ARG...]

Run COMMAND in a standard lk-platform shell environment with output logging
enabled. COMMAND is interpreted by Bash and may therefore be a shell builtin
or function.

OPTIONS

    -i, --include=LIBRARY   call \`lk_require LIBRARY\` before running COMMAND
                            (may be given multiple times)"

lk_getopt "i:" "include:"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -i | --include)
        lk_require "$1" || lk_warn "invalid library: $1" || lk_usage
        shift
        ;;
    --)
        break
        ;;
    esac
done

[ $# -gt 0 ] || lk_usage
type -t "$1" >/dev/null || lk_warn "command not found: $1" || lk_usage

[ -n "${LK_LOG_BASENAME-}" ] ||
    LK_LOG_BASENAME=${1##*/}-$(lk_md5 "$@")
export -n LK_LOG_BASENAME

LK_LOG_CMDLINE=("$@")
lk_log_open

"$@"
