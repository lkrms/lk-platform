#!/bin/bash

function lk_ps_parent_command() {
    ps -o comm= -p "$PPID"
}

# lk_ps_recurse_children [-p] PPID...
#
# Print the process ID of all processes descended from PPID. If -p is set,
# include PPID in the output.
function lk_ps_recurse_children() {
    [ "${1-}" != -p ] || {
        shift
        [ $# -eq 0 ] || printf '%s\n' "$@"
    }
    ps -eo pid=,ppid= | awk '
function recurse(p, _a, _i) { if (c[p]) {
    split(c[p], _a, ",")
    for (_i in _a) {
        print _a[_i]
        recurse(_a[_i])
    }
} }
BEGIN { for (i = 1; i < ARGC; i++) {
    ps[i] = ARGV[i]
    delete ARGV[i]
} }
{ c[$2] = (c[$2] ? c[$2] "," : "") $1 }
END { for (i in ps) {
    recurse(ps[i])
} }' "$@"
}
