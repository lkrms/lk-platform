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
    local expected_output=$1
    shift
    _do_assert_output_equals "$expected_output" "" "$@"
}

# assert_output_with_stderr_equals [-expected_status] expected_output expected_stderr COMMAND [ARG...]
function assert_output_with_stderr_equals() {
    local expected_status=0
    [[ $1 != -* ]] || { expected_status=${1:1} && shift; }
    _do_assert_output_equals "$@"
}

# _do_assert_output_equals expected_output expected_stderr COMMAND [ARG...]
function _do_assert_output_equals() {
    local expected_output=$1 expected_stderr=$2 \
        output stderr=$TEMP/stderr status=0 actual expected
    shift 2
    output=$(_LK_STACK_DEPTH=$((${_LK_STACK_DEPTH-0} + 1)) "$@" 2>"$stderr") || status=$?
    ((status == expected_status)) ||
        assertion_failed 'expected status %d, got %d' "$expected_status" "$status" ||
        return
    stderr=$(<"$stderr")
    for actual in output stderr; do
        expected=expected_$actual
        [[ ${!actual} == "${!expected}" ]] ||
            if [[ "${!expected}${!actual}" == *$'\n'* ]]; then
                assertion_failed_diff "expected $actual does not match actual $actual" "${!expected}" "${!actual}" ||
                    return
            else
                assertion_failed -q "expected $actual %s, got %s" "${!expected}" "${!actual}" ||
                    return
            fi
    done
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
            assertion_failed -q 'expected output %s, got %s' "${expected_output%.}" "${output%.}" ||
                return
        fi
}

# assertion_failed [-q] message [arg...]
function assertion_failed() {
    local quote=0
    [[ $1 != -q ]] || {
        quote=1
        shift
    }
    local message=$1
    shift
    if (($# && quote)); then
        local args=() arg
        for arg in "$@"; do
            args[${#args[@]}]="'${arg//"'"/"'\\''"}'"
        done
        set -- "${args[@]}"
    fi
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

TEMP=$(mktemp -d)
trap 'rm -Rf "$TEMP"' EXIT

if (($#)); then
    set -- "${@#tests/unit/}"
    set -- "${@/#/tests/unit/}"
fi

TESTS=0
PASSED=0
FAILED=0
ERRORS=()
while IFS= read -r TEST; do
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
done < <(find tests/unit -type f -name '*-test.sh' |
    if (($#)); then
        grep -Fxf <(printf '%s\n' "$@") | sort
    else
        sort
    fi)

SUMMARY=(Tests "$TESTS")
((!PASSED)) || SUMMARY+=(Passed "$PASSED")
((!FAILED)) || SUMMARY+=(Failed "$FAILED")

if (($#)); then
    IFS=$'\n'
    if MISSING=($(printf '%s\n' "$@" | sort -u | grep -Fxvf <(find tests/unit -type f -name '*-test.sh'))); then
        printf '%s: file not found\n' "${MISSING[@]#tests/unit/}" >&2
        SUMMARY+=(Missing "${#MISSING[@]}")
        ((++FAILED))
    fi
fi

((!TESTS && !$#)) || lk_tty_print

if ((!FAILED)); then
    lk_tty_success 'OK'
elif [[ -n ${ERRORS+1} ]]; then
    lk_tty_error 'ERRORS:' $'\n'"$(
        printf -- '- %s\n' "${ERRORS[@]#tests/unit/}"
    )"
    lk_tty_print
fi
lk_tty_detail "$(printf '%s: %d, ' "${SUMMARY[@]}" | sed -E 's/, $/\n/')"
lk_tty_detail "Bash version:" "$BASH_VERSION"

((!FAILED)) || lk_die ""
