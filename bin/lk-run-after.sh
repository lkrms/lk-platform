#!/bin/sh

set -eu

lk_die() { s=$? && echo "${LK_DIE_PREFIX-${0##*/}: }$1" >&2 &&
    (return $s) && false || exit; }

[ $# -ge 2 ] || LK_DIE_PREFIX='' lk_die "\
Usage: ${0##*/} DURATION COMMAND [ARG...]"

DURATION=$1
shift

type "$1" >/dev/null 2>&1 ||
    lk_die "command not found: $1"

sleep "$DURATION"
exec "$@"
