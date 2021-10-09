#!/bin/bash

# lk_trace [MESSAGE]
function lk_trace() {
    [ "${LK_DEBUG-}" = Y ] || return 0
    local NOW
    NOW=$(gnu_date +%s.%N) || return 0
    _LK_TRACE_FIRST=${_LK_TRACE_FIRST:-$NOW}
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$NOW" \
        "$_LK_TRACE_FIRST" \
        "${_LK_TRACE_LAST:-$NOW}" \
        "${1+${1::30}}" \
        "${BASH_SOURCE[1]+${BASH_SOURCE[1]#$LK_BASE/}:${BASH_LINENO[0]}}" |
        awk -F'\t' -v "d=$LK_DIM" -v "u=$LK_UNDIM" \
            '{printf "%s%09.4f  +%.4f\t%-30s\t%s\n",d,$1-$2,$1-$3,$4,$5 u}' >&2
    _LK_TRACE_LAST=$NOW
}

# lk_get_stack_trace [FIRST_FRAME_DEPTH [ROWS [FIRST_FRAME]]]
function lk_get_stack_trace() {
    local i=$((${1:-0} + ${_LK_STACK_DEPTH:-0})) r=0 ROWS=${2:-0} FRAME=${3-} \
        DEPTH=$((${#FUNCNAME[@]} - 1)) WIDTH FUNC FILE LINE \
        REGEX='^([0-9]*) ([^ ]*) (.*)$'
    WIDTH=${#DEPTH}
    while ((i++ < DEPTH)) && ((!ROWS || r++ < ROWS)); do
        FUNC=${FUNCNAME[i]-"{main}"}
        FILE=${BASH_SOURCE[i]-"{main}"}
        LINE=${BASH_LINENO[i - 1]-0}
        [[ ! ${FRAME-} =~ $REGEX ]] || {
            FUNC=${BASH_REMATCH[2]:-$FUNC}
            FILE=${BASH_REMATCH[3]:-$FILE}
            LINE=${BASH_REMATCH[1]:-$LINE}
            unset FRAME
        }
        ((ROWS == 1)) || printf "%${WIDTH}d. " "$((DEPTH - i + 1))"
        printf "%s %s (%s:%s)\n" \
            "$( ((r > 1)) && echo at || echo in)" \
            "$LK_BOLD$FUNC$LK_RESET" "$FILE$LK_DIM" "$LINE$LK_RESET"
    done
}

#### Reviewed: 2021-10-09
