#!/bin/bash
# shellcheck disable=SC1007,SC1090,SC2015

set -euo pipefail
lk_die() { echo "$1" >&2 && exit 1; }
[ -n "${LK_BASE:-}" ] || { BS="${BASH_SOURCE[0]}" && [ ! -L "$BS" ] &&
    LK_BASE="$(cd "${BS%/*}/.." && pwd -P)" &&
    [ -d "$LK_BASE/lib/bash" ] || lk_die "${BS:+$BS: }LK_BASE not set"; }

include= . "$LK_BASE/lib/bash/common.sh"

PARAM=
PARAM1=
PARAM2=
FLAG=0
VALUE="0"
SETTING="auto"

USAGE="\
Usage:
  $(basename "$0") [OPTION]... PARAM
  $(basename "$0") [OPTION]... PARAM1 PARAM2

Provide a boilerplate for Bash scripts that parse options with getopt.

Options:
  -f, --flag            set a flag
  -v, --value VALUE     set a value (default: $VALUE)
  -s, --setting[=SETTING]
                        enable a setting and provide an optional value
                        (default: $SETTING)"

OPTS="$(
    getopt --options "fv:s::" \
        --longoptions "flag,value:,setting::" \
        --name "$(basename "$0")" \
        -- "$@"
)" || lk_usage
eval "set -- $OPTS"

while :; do
    OPT="$1"
    shift
    case "$OPT" in
    -f | --flag)
        FLAG=1
        ;;
    -v | --value)
        VALUE="$1"
        ;;&
    -s | --setting)
        SETTING="${1:-$SETTING}"
        ;;&
    --)
        break
        ;;
    *)
        shift
        ;;
    esac
done

case "$#" in
1)
    PARAM="$1"
    ;;
2)
    PARAM1="$1"
    PARAM2="$2"
    ;;
*)
    lk_usage
    ;;
esac

declare -p \
    FLAG \
    VALUE \
    SETTING \
    PARAM \
    PARAM1 \
    PARAM2
