#!/bin/bash

[ -n "${LK_BASE:-}" ] ||
    eval "$(
        RC_PATH="${BASH_SOURCE[0]}"
        if [ ! -L "$RC_PATH" ] &&
            LK_BASE="$(cd "$(dirname "$RC_PATH")/.." && pwd -P)" &&
            [ -d "$LK_BASE/lib/bash" ]; then
            export LK_BASE
            declare -p LK_BASE
            shopt -s nullglob
            for FILE in "$LK_BASE/lib/bash"/*.sh; do
                echo ". \"\$LK_BASE/lib/bash\"/$(basename "$FILE")"
            done
        else
            echo "$RC_PATH: symbolic links to lk-platform scripts are not supported" >&2
        fi
    )"
