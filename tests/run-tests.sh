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
    output=$("$@") || status=$?
    ((status == expected_status)) ||
        assertion_failed 'expected status %d, got %d' "$expected_status" "$status" ||
        return
    [[ $output == "$expected_output" ]] ||
        if [[ "$expected_output$output" == *$'\n'* ]]; then
            assertion_failed_diff 'expected output does not match actual output' "$expected_output" "$output" ||
                return
        else
            assertion_failed 'expected output %q, got %q' "$expected_output" "$output" ||
                return
        fi
}

# assert_output_equals_file [-expected_status] expected_output_file COMMAND [ARG...]
function assert_output_equals_file() {
    local expected_status=0 expected_output output status=0
    [[ $1 != -* ]] || { expected_status=${1:1} && shift; }
    expected_output=$(cat "$1" && echo .) ||
        assertion_failed 'error reading expected output' ||
        return
    shift
    output=$("$@" && echo . || lk_pass echo .) || status=$?
    ((status == expected_status)) ||
        assertion_failed 'expected status %d, got %d' "$expected_status" "$status" ||
        return
    [[ $output == "$expected_output" ]] ||
        if [[ "$expected_output$output" == *$'\n'* ]]; then
            assertion_failed_diff 'expected output does not match actual output' "${expected_output%.}" "${output%.}" ||
                return
        else
            assertion_failed 'expected output %q, got %q' "${expected_output%.}" "${output%.}" ||
                return
        fi
}

# assertion_failed message [arg...]
function assertion_failed() {
    local message=$1
    shift
    printf "%s: ${message}\\n" "${BASH_SOURCE[2]#tests/unit/}:${BASH_LINENO[1]}" "$@" >&2
    return 1
}

# assertion_failed_diff message expected actual [arg...]
function assertion_failed_diff() { {
    local message=$1 expected=$2 actual=$3
    shift 3
    printf "%s: ${message}\\n" "${BASH_SOURCE[2]#tests/unit/}:${BASH_LINENO[1]}" "$@"
    ! diff -u --color --label Expected --label Actual \
        <(printf '%s' "$expected") <(printf '%s' "$actual")
    printf '\n'
    return 1
} >&2; }

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
