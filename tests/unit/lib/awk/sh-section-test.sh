#!/usr/bin/env bash

function input1() {
    cat <<EOF

[options]
foo = 1
bar = 2

#[disabled]
#key1 = value1

baz = 3


#[disabled]
#key2 = value2

[enabled]
qux = 4

EOF
}

function output1() {
    cat <<EOF
foo = 1
bar = 2

#[disabled]
#key1 = value1

baz = 3


EOF
}

function input2() {
    echo "$(output1)"
    echo "quux = 5"
}

function output2() {
    cat <<EOF

[options]
foo = 1
bar = 2

#[disabled]
#key1 = value1

baz = 3
quux = 5

#[disabled]
#key2 = value2

[enabled]
qux = 4

EOF
}

assert_output_equals_file <(output1) \
    awk \
    -v "section=options" \
    -f "$(lk_awk_dir)/sh-section-get.awk" \
    < <(input1)

entries=$(input2)
assert_output_equals_file <(output2) \
    awk \
    -v "section=options" \
    -v "entries=${entries//$'\n'/\\n}" \
    -f "$(lk_awk_dir)/sh-section-replace.awk" \
    < <(input1)
