#!/bin/sh

set -eu

lk_die() { s=$? && echo "${0##*/}: $1" >&2 && (exit $s) && false || exit; }

[ $# -ge 2 ] || {
    echo "Usage: ${0##*/} DURATION COMMAND [ARG...]" >&2
    exit 1
}

DURATION=$1
shift

type "$1" >/dev/null 2>&1 ||
    lk_die "command not found: $1"

sleep "$DURATION"
exec "$@"
