#!/bin/sh

set -eu

lk_die() {
    echo "${PREFIX-$(basename "$0"): }$1" >&2
    exit 1
}

[ "$#" -ge 2 ] || PREFIX="" lk_die "Usage:
  $(basename "$0") duration command [arg...]"

DURATION="$1"
shift

type "$1" >/dev/null 2>&1 ||
    lk_die "command not found: $1"

sleep "$DURATION"
exec "$@"
