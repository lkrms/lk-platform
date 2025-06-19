#!/usr/bin/env bash

if [[ ${1-} == --run ]]; then

    # add_traps SIGNAL
    function add_traps() {
        lk_trap_add -q "$1" "$(lk_quote_args report_trap "$1" 1 "$((BASH_SUBSHELL - 1))") \$LINENO"
        lk_trap_add "$1" report_trap "$1" 2 "$BASH_SUBSHELL"
        lk_trap_add -f "$1" report_trap "$1" 2 "$BASH_SUBSHELL"
    }

    # report_trap SIGNAL INDEX SUBSHELL [LINENO]
    function report_trap() {
        local status=$?
        printf '%s #%d (trap/signal subshell: %d/%d): %d%s\n' \
            "$1" "$2" "$3" "$BASH_SUBSHELL" "$status" "${4+ ($4)}"
        return 7
    }

    . "$LK_BASE/lib/bash/common.sh" || exit

    _LK_CAN_FAIL=1

    add_traps EXIT
    add_traps ERR

    set +e
    (
        echo "Subshell #1: inherited traps only, set +e"
        (exit 2)
    )
    echo "Exit status: $?"
    echo
    (
        echo "Subshell #2: with traps, set +e"
        add_traps EXIT
        add_traps ERR
        (exit 3)
    )
    echo "Exit status: $?"
    echo
    (
        set -e
        echo "Subshell #3: inherited traps only, set -e (inner)"
        (exit 4)
    )
    echo "Exit status: $?"
    echo
    (
        set -e
        echo "Subshell #4: with traps, set -e (inner)"
        add_traps EXIT
        add_traps ERR
        (exit 5)
    )
    echo "Exit status: $?"
    echo
    set -e
    (
        echo "Subshell #5: inherited traps only, set -e"
        (exit 6)
    )

else

    function output() {

        if lk_bash_at_least 4; then

            cat <<EOF
Subshell #1: inherited traps only, set +e
ERR #2 (trap/signal subshell: 0/1): 2
ERR #1 (trap/signal subshell: 0/1): 2 (30)
ERR #2 (trap/signal subshell: 0/0): 2
ERR #1 (trap/signal subshell: 0/0): 2 (31)
Exit status: 2

Subshell #2: with traps, set +e
ERR #2 (trap/signal subshell: 1/1): 3
ERR #1 (trap/signal subshell: 1/1): 3 (38)
EXIT #2 (trap/signal subshell: 1/1): 3
EXIT #1 (trap/signal subshell: 1/1): 3 (1)
ERR #2 (trap/signal subshell: 1/1): 7
ERR #1 (trap/signal subshell: 1/1): 7 (1)
ERR #2 (trap/signal subshell: 0/0): 3
ERR #1 (trap/signal subshell: 0/0): 3 (39)
Exit status: 3

Subshell #3: inherited traps only, set -e (inner)
ERR #2 (trap/signal subshell: 0/1): 4
ERR #1 (trap/signal subshell: 0/1): 4 (45)
ERR #2 (trap/signal subshell: 0/0): 7
ERR #1 (trap/signal subshell: 0/0): 7 (46)
Exit status: 7

Subshell #4: with traps, set -e (inner)
ERR #2 (trap/signal subshell: 1/1): 5
ERR #1 (trap/signal subshell: 1/1): 5 (54)
EXIT #2 (trap/signal subshell: 1/1): 7
EXIT #1 (trap/signal subshell: 1/1): 7 (1)
ERR #2 (trap/signal subshell: 0/0): 7
ERR #1 (trap/signal subshell: 0/0): 7 (55)
Exit status: 7

Subshell #5: inherited traps only, set -e
ERR #2 (trap/signal subshell: 0/1): 6
ERR #1 (trap/signal subshell: 0/1): 6 (61)
ERR #2 (trap/signal subshell: 0/0): 7
ERR #1 (trap/signal subshell: 0/0): 7 (62)
EXIT #2 (trap/signal subshell: 0/0): 7
EXIT #1 (trap/signal subshell: 0/0): 7 (1)
EOF

        else

            cat <<EOF
Subshell #1: inherited traps only, set +e
Exit status: 2

Subshell #2: with traps, set +e
EXIT #2 (trap/signal subshell: 1/1): 3
EXIT #1 (trap/signal subshell: 1/1): 3 (144)
Exit status: 3

Subshell #3: inherited traps only, set -e (inner)
Exit status: 4

Subshell #4: with traps, set -e (inner)
EXIT #2 (trap/signal subshell: 1/1): 5
EXIT #1 (trap/signal subshell: 1/1): 5 (144)
Exit status: 7

Subshell #5: inherited traps only, set -e
EXIT #2 (trap/signal subshell: 0/0): 6
EXIT #1 (trap/signal subshell: 0/0): 6 (144)
EOF

        fi

    }

    assert_output_equals -7 "$(output)" "$BASH" "$BASH_SOURCE" --run

fi
