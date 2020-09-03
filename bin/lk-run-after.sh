#!/bin/sh

set -eu

lk_die() { s=$? && echo "${PREFIX-$0: }$1" >&2 && (return $s) && false || exit; }

[ $# -ge 2 ] || PREFIX="" lk_die "\
Usage:
  ${0##*/} duration command [arg...]"

DURATION=$1
shift

type "$1" >/dev/null 2>&1 ||
    lk_die "$1: command not found"

sleep "$DURATION"
exec "$@"
