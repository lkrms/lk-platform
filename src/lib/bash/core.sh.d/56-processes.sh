#!/bin/bash

function lk_ps_parent_command() {
    ps -o comm= -p "$PPID"
}

function lk_ps_running_seconds() {
    # "elapsed time since the process was started, in the form [[DD-]hh:]mm:ss"
    _lk_stream_args 6 xargs -r ps -o etime= -p "$@" | awk '
      { d = t[1] = t[2] = t[3] = 0 }
/-/   { split($1, a, /-/)
        d  = a[1]
        $1 = a[2] }
      { n = split($1, a, /:/)
        for(i in a) { t[n - i + 1] = a[i] }
        print ((d * 24 + t[3]) * 60 + t[2]) * 60 + t[1] }'
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
