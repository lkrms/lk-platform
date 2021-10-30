#!/bin/bash

# Run with -i to output the `install_gnu_commands` function
#
# To update REQUIRED_COMMANDS, run this in `$LK_BASE`:
#
#     lk_bash_find_scripts -print0 | xargs -0 awk \
#         -v s="^$S*" \
#         -v r='function install_gnu_commands\\(\\) \\{$' '
#             $0 ~ s r        { skip = 1; e = $0; sub(r, "", e); e = e "}" }
#             skip && $0 == e { skip = 0; next }
#             !skip           { print }' |
#         grep -Pho "\\bgnu_([a-zA-Z0-9_](?!$S*\\(\\)))+\\b" |
#         sort -u |
#         sed 's/^gnu_//'

export LC_ALL=C

REQUIRED_COMMANDS=(
    awk
    chmod
    chown
    cp
    date
    dd
    df
    diff
    find
    getopt
    grep
    realpath
    sed
    stat
    xargs
)

COMMANDS=(
    awk
    chgrp
    chmod
    chown
    cp
    date
    dd
    df
    diff
    du
    find
    getopt
    grep
    ln
    mktemp
    mv
    realpath
    sed
    sort
    stat
    tar
    xargs
)

COMMANDS=($(printf '%s\n' \
    "${COMMANDS[@]}" \
    "${REQUIRED_COMMANDS[@]}" |
    sort -u))

OPTIONAL_COMMANDS=($(comm -13 \
    <(printf '%s\n' "${REQUIRED_COMMANDS[@]}" | sort -u) \
    <(printf '%s\n' "${COMMANDS[@]}")))

function get_gnu_command() {
    local COMMAND PREFIX=
    unset COMMAND
    if [ "$PLATFORM" = macos ]; then
        PREFIX=g
        COMMAND=
    fi
    case "$1" in
    awk)
        COMMAND=g$1
        ;;
    diff)
        COMMAND=${COMMAND+"\"\${HOMEBREW_PREFIX:-\$_LK_HOMEBREW_PREFIX}/opt/diffutils/bin/$1\""}${COMMAND-$1}
        ;;
    getopt)
        COMMAND=${COMMAND+"\"\${HOMEBREW_PREFIX:-\$_LK_HOMEBREW_PREFIX}/opt/gnu-getopt/bin/$1\""}${COMMAND-$1}
        ;;
    *)
        COMMAND=$PREFIX$1
        ;;
    esac
    echo "$COMMAND"
}

function render() {
    local COMMAND
    case "$MODE" in
    build)
        if [ "$PLATFORM" = macos ]; then
            printf '%s &&\n    %s=%s ||\n    %s=%s\n' \
                lk_is_apple_silicon \
                _LK_HOMEBREW_PREFIX /opt/homebrew \
                _LK_HOMEBREW_PREFIX /usr/local
        fi
        for COMMAND in "${COMMANDS[@]}"; do
            printf 'function gnu_%s() { lk_sudo %s "$@"; }\n' \
                "$COMMAND" "$(get_gnu_command "$COMMAND")"
        done
        ;;
    install)
        printf '%s=(\n' GNU_COMMANDS
        {
            for COMMAND in "${REQUIRED_COMMANDS[@]}"; do
                printf '    %s gnu_%s 1\n' \
                    "$(get_gnu_command "$COMMAND")" "$COMMAND"
            done
            for COMMAND in "${OPTIONAL_COMMANDS[@]}"; do
                printf '    %s gnu_%s 0\n' \
                    "$(get_gnu_command "$COMMAND")" "$COMMAND"
            done
        } | sort -k2
        printf ')\n'
        ;;
    esac | sed 's/^/    /'
}

case "${1+${1:-null}}" in
"")
    MODE=build
    cat <<"EOF"
# Define wrapper functions (e.g. `gnu_find`) to invoke the GNU version of
# certain commands (e.g. `gfind`) when standard utilities are not compatible
# with their GNU counterparts, e.g. on BSD/macOS
EOF
    ;;
-i | --install)
    MODE=install
    cat <<"EOF"
function install_gnu_commands() {
    local GNU_COMMANDS i STATUS=0
EOF
    ;;
*)
    echo "Usage: ${0##*/} [-i|--install]" >&2
    exit 1
    ;;
esac

{
    printf 'if ! lk_is_macos; then\n'
    PLATFORM=
    render
    printf 'else\n'
    PLATFORM=macos
    render
    printf 'fi\n'
} |
    if [ "$MODE" != install ]; then
        cat
    else
        sed 's/^/    /'
    fi

[ "$MODE" != install ] || cat <<"EOF"
    for ((i = 0; i < ${#GNU_COMMANDS[@]}; i += 3)); do
        lk_symlink_bin "${GNU_COMMANDS[@]:i:2}" ||
            [ "${GNU_COMMANDS[*]:i+2:1}" -eq 0 ] ||
            STATUS=$?
    done
    return "$STATUS"
}
EOF

#### Reviewed: 2021-10-07
