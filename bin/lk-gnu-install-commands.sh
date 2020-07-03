#!/bin/bash
# shellcheck disable=SC1090,SC2015

set -euo pipefail
lk_die() { echo "$1" >&2 && exit 1; }
[ -n "${LK_BASE:-}" ] || { BS="${BASH_SOURCE[0]}" && [ ! -L "$BS" ] &&
    LK_BASE="$(cd "$(dirname "$BS")/.." && pwd -P)" &&
    [ -d "$LK_BASE/lib/bash" ] || lk_die "${BS:+$BS: }LK_BASE not set"; }

. "$LK_BASE/lib/bash/common.sh"

lk_install_gnu_commands "$@"
