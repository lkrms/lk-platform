#!/bin/bash

# Run with -i to output the `install_gnu_commands` function
#
# To update REQUIRED_COMMANDS:
#
#     lk_bash_find_scripts -d "$LK_BASE" -print0 |
#         xargs -0 grep -Pho "\\bgnu_([a-zA-Z0-9_](?!$S*\\(\\)))+\\b" |
#         sort -u |
#         sed 's/^gnu_//'

export LC_ALL=C

REQUIRED_COMMANDS=(
    awk
    chmod
    chown
    cp
    date
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

function gnu_command() {
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
        COMMAND=${COMMAND+"\"\${HOMEBREW_PREFIX:-\$_LK_HOMEBREW_PREFIX}/bin/$1\""}${COMMAND-$1}
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
    "")
        if [ "$PLATFORM" = macos ]; then
            printf '%s &&\n    %s=%s ||\n    %s=%s\n' \
                lk_is_apple_silicon \
                _LK_HOMEBREW_PREFIX /opt/homebrew \
                _LK_HOMEBREW_PREFIX /usr/local
        fi
        for COMMAND in "${COMMANDS[@]}"; do
            printf 'function gnu_%s() { lk_maybe_sudo %s "$@"; }\n' \
                "$COMMAND" "$(gnu_command "$COMMAND")"
        done
        ;;
    install)
        printf '%s=(\n' GNU_COMMANDS
        {
            for COMMAND in "${REQUIRED_COMMANDS[@]}"; do
                printf '    %s gnu_%s 1\n' \
                    "$(gnu_command "$COMMAND")" "$COMMAND"
            done
            for COMMAND in "${OPTIONAL_COMMANDS[@]}"; do
                printf '    %s gnu_%s 0\n' \
                    "$(gnu_command "$COMMAND")" "$COMMAND"
            done
        } | sort -k2
        printf ')\n'
        ;;
    esac | sed 's/^/    /'
}

if [[ ! $1 =~ ^(-i|--install)$ ]]; then
    MODE=
    cat <<"EOF"
# Define wrapper functions (e.g. `gnu_find`) to invoke the GNU version of
# certain commands (e.g. `gfind`) on systems where standard utilities are not
# compatible with their GNU counterparts, e.g. BSD/macOS
EOF
else
    MODE=install
    cat <<"EOF"
function install_gnu_commands() {
    local GNU_COMMANDS i STATUS=0
EOF
fi

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

printf '\n'
