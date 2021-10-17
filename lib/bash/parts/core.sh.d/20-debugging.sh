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

# lk_stack_trace [FIRST_FRAME_DEPTH [ROWS [FIRST_FRAME]]]
function lk_stack_trace() {
    local DEPTH=$((${1:-0} + ${_LK_STACK_DEPTH:-0})) ROWS=${2:-0} FRAME=${3-} \
        _D=$((${#FUNCNAME[@]} - 1)) _R WIDTH ROW=0 FUNC FILE LINE \
        REGEX='^([0-9]*) ([^ ]*) (.*)$'
    # _D = maximum DEPTH, _R = maximum rows of output (DEPTH=0 is always skipped
    # to exclude lk_stack_trace)
    ((_R = _D - DEPTH, ROWS = ROWS ? (ROWS > _R ? _R : ROWS) : _R, ROWS)) ||
        lk_warn "invalid arguments" || return
    WIDTH=${#_R}
    while ((ROW++ < ROWS)) && ((DEPTH++ < _D)); do
        FUNC=${FUNCNAME[DEPTH]-"{main}"}
        FILE=${BASH_SOURCE[DEPTH]-"{main}"}
        LINE=${BASH_LINENO[DEPTH - 1]-0}
        [[ ! ${FRAME-} =~ $REGEX ]] || {
            FUNC=${BASH_REMATCH[2]:-$FUNC}
            FILE=${BASH_REMATCH[3]:-$FILE}
            LINE=${BASH_REMATCH[1]:-$LINE}
            unset FRAME
        }
        ((ROWS == 1)) || printf "%${WIDTH}d. " "$ROW"
        printf "%s %s (%s:%s)\n" \
            "$( ((ROW > 1)) && echo at || echo in)" \
            "$LK_BOLD$FUNC$LK_RESET" "$FILE$LK_DIM" "$LINE$LK_UNDIM"
    done
}

#### Reviewed: 2021-10-17
