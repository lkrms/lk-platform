#!/usr/bin/env bash

# lk_find_shell_scripts [-d DIR] [FIND_ARG...]
function lk_find_shell_scripts() {
    local DIR
    [[ ${1-} != -d ]] || { DIR=$(cd "$2" && pwd -P) && shift 2 || return; }
    gnu_find "${DIR:-.}" \
        ! \( \( \( -type d -name .git \) -o ! -readable \) -prune \) \
        -type f \
        \( -name '*.sh' -o -exec \
        sh -c 'head -c20 "$1" | grep -Eq "^#!/(usr/)?bin/(env )?(ba)?sh\\>"' sh '{}' \; \) \
        \( "${@--print}" \)
}

#### Reviewed: 2022-10-06
