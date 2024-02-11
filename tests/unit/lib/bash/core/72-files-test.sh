#!/usr/bin/env bash

function input1() {
    cat <<EOF
[section]
;key = off

EOF
}

function input2() {
    cat <<EOF
[section]
key = on

EOF
}

lk_mktemp_dir_with DIR
FILE=$DIR/file1

install -m 2777 /dev/null "$FILE"
assert_output_equals "2777" lk_file_mode "$FILE"

lk_file -m 600 "$FILE" < <(input1)
assert_output_equals "0600" lk_file_mode "$FILE"
assert_output_equals "$(input1)" cat "$FILE"

lk_file -m 0644 "$FILE" < <(input2)
assert_output_equals "0644" lk_file_mode "$FILE"
assert_output_equals "$(input2)" cat "$FILE"
