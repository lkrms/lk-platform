#!/usr/bin/env bash

# return_status [-q] <status>
function return_status() {
    local print=1
    [[ $1 != -q ]] || { print=0 && shift; }
    local status=$1
    ((!print)) || echo "Returning $status"
    return $((status))
}

# pass_to_lk_pass <command> [<args>...]
function pass_to_lk_pass() {
    "$@" || lk_pass return_status 0 || return
    lk_pass return_status 128
}

# pass_with_status_to_lk_pass <status> <command> [<args>...]
function pass_with_status_to_lk_pass() {
    local status=$1
    shift
    "$@" || {
        lk_pass "-$status" return_status 0 || return
        return
    }
    lk_pass "-$status" return_status 128
}

function -return() {
    local IFS=, status=$1
    shift
    echo "Returning $status from ${FUNCNAME[1]}($*)"
    return $((status))
}

function -not_a_number() { -return 71 "$@"; }
function -6ish() { -return 6 "$@"; }
function -0or1() { -return 0 "$@"; }

assert_output_equals -0 'Returning 2' lk_pass return_status 2

assert_output_equals -8 'Returning 0' pass_to_lk_pass return_status -q 8
assert_output_equals -0 'Returning 128' pass_to_lk_pass return_status -q 0

assert_output_equals -4 'Returning 0' pass_with_status_to_lk_pass 4 return_status -q 8
assert_output_equals -6 'Returning 128' pass_with_status_to_lk_pass 6 return_status -q 0
assert_output_equals -0 'Returning 0' pass_with_status_to_lk_pass 0 return_status -q 2

assert_output_equals -8 'Returning 71 from -not_a_number(return_status,0)' pass_with_status_to_lk_pass not_a_number return_status -q 8
assert_output_equals -0 'Returning 6 from -6ish(return_status,128)' pass_with_status_to_lk_pass 6ish return_status -q 0
assert_output_equals -2 'Returning 0 from -0or1(return_status,0)' pass_with_status_to_lk_pass 0or1 return_status -q 2
