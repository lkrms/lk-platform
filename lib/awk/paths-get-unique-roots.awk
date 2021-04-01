# Input:
#
#     /d1/d2/d3/d4/d5
#     /d1/d2/d3/d4
#     /d1/d2/d3/d42
#     /d1/d2/d33
#     /d14/d24
#     /d14/d25
#
# Output:
#
#     /d1/d2
#     /d14

function parent(p) {
    sub("/[^/]+$", "", p)
    return p
}

/^(\/[^\/]+)+$/ {
    n = split($0, a, "/")
    for (i = 2; i <= n; i++) {
        # If input is /d1/d2/d3/d4, set `path` to /d1, /d1/d2, /d1/d2/d3 and
        # /d1/d2/d3/d4 in turn, stopping when the path is unique, i.e. when it
        # isn't the ancestor of a path already stored in `aa`
        path = (i > 2 ? path : "") "/" a[i]
        if (aa[path]) {
            next
        }
        found = 0
        for (j in aa) {
            if (aa[j] && index(j, path "/") == 1) {
                found = 1
                break
            }
        }
        if (found) {
            # If the full path (/d1/d2/d3/d4 in the example above) isn't unique,
            # use it as a shared ancestor by leaving `path` as-is
            if (i < n) {
                continue
            }
        } else if (i == 2) {
            # If the first directory (/d1 in the example above) is unique,
            # store the entire path (/d1/d2/d3/d4) to seed its hierarchy
            path = $0
        } else {
            # If any other directory is unique (e.g. /d1/d2/d3 in the example
            # above), use its parent (/d1/d2) as a shared ancestor
            path = parent(path)
        }
        # Add `path` to `aa` and remove any of its descendants
        aa[path] = 1
        for (j in aa) {
            if (aa[j] && index(j, path "/") == 1) {
                delete aa[j]
            }
        }
        next
    }
}
END {
    for (i in aa) {
        if (aa[i]) {
            print i
        }
    }
}
