#!/usr/bin/env bash

set -euo pipefail

function die() {
    local s=$?
    printf '%s: %s\n' "${0##*/}" "${1-command failed}" >&2
    exit $((s ? s : 1))
}

# assert_output_equals [-expected_status] expected_output COMMAND [ARG...]
function assert_output_equals() {
    local expected_status=0
    [[ $1 != -* ]] || { expected_status=${1:1} && shift; }
    local expected_output=$1 output status=0
    shift
    output=$("$@" 2>&1) || status=$?
    ((status == expected_status)) ||
        assertion_failed 'expected status %d, got %d' "$expected_status" "$status" ||
        return
    [[ $output == "$expected_output" ]] ||
        assertion_failed 'expected output %q, got %q' "$expected_output" "$output" ||
        return
}

# assertion_failed message [arg...]
function assertion_failed() {
    local message=$1
    shift
    printf "%s: ${message}\\n" "${BASH_SOURCE[2]#tests/unit/}:${BASH_LINENO[1]}" "$@" >&2
    return 1
}

[[ ${BASH_SOURCE[0]} -ef tests/run-tests.sh ]] ||
    die "must run from root of package folder"

LK_BASE=$(pwd -P)
. "$LK_BASE/lib/bash/common.sh"

TESTS=0
PASSED=0
FAILED=0
ERRORS=()
while IFS= read -rd '' TEST; do
    lk_tty_print "Running:" "${TEST#tests/unit/}"
    set +e
    (
        set -e
        . "$TEST"
    )
    RESULT=$?
    set -e
    if ((RESULT == 0)); then
        ((++PASSED))
    else
        ERRORS[${#ERRORS[@]}]=$TEST
        ((++FAILED))
    fi
    ((++TESTS))
done < <(find tests/unit -type f -name '*-test.sh' -print0)

((!TESTS)) || lk_tty_print

SUMMARY=(Tests "$TESTS")
((!PASSED)) || SUMMARY+=(Passed "$PASSED")
((!FAILED)) || SUMMARY+=(Failed "$FAILED")

if ((!FAILED)); then
    lk_tty_success 'OK'
else
    lk_tty_error 'ERRORS:' $'\n'"$(
        printf -- '- %s\n' "${ERRORS[@]#tests/unit/}"
    )"
    lk_tty_print
fi
lk_tty_detail "$(printf '%s: %d, ' "${SUMMARY[@]}" | sed -E 's/, $/\n/')"

((!FAILED)) || lk_die ""
