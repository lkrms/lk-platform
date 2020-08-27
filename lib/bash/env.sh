#!/bin/sh
# shellcheck disable=SC2016

lk_esc() {
    echo "$1" | sed -Ee 's/\\/\\\\/g' -e 's/[$`"]/\\&/g'
}

lk_esc_ere() {
    echo "$1" | sed -Ee 's/\\/\\\\/g' -e 's/[]$()*+./?[^{|}]/\\&/g'
}

lk_in_path() {
    case ":$PATH:" in
    *:$1:*)
        return
        ;;
    *)
        return 1
        ;;
    esac
}

lk_path_add() {
    if ! lk_in_path "$1" && [ -d "$1" ]; then
        echo "$PATH:$1" | sed -Ee 's/:+/:/g' -e 's/(^:|:$)//g'
    else
        echo "$PATH"
    fi
}

lk_path_add_to_front() {
    if [ -d "$1" ]; then
        echo "$1:$(echo "$PATH" |
            sed -Ee "s/(:|^)$(lk_esc_ere "$1")(:|$)/\\1\\2/g" \
                -e 's/:+/:/g' -e 's/(^:|:$)//g')"
    else
        echo "$PATH"
    fi
}

OLD_PATH="$PATH"
ADD_TO_PATH="${LK_ADD_TO_PATH:+$LK_ADD_TO_PATH:}$LK_BASE/bin"
ADD_TO_PATH_FIRST="${HOME:+$HOME/.homebrew/bin:$HOME/.local/bin}${LK_ADD_TO_PATH_FIRST:+:$LK_ADD_TO_PATH_FIRST}"
IFS=:
for DIR in $ADD_TO_PATH; do
    PATH="$(lk_path_add "$DIR")"
done
for DIR in $ADD_TO_PATH_FIRST; do
    PATH="$(lk_path_add_to_front "$DIR")"
done
unset IFS
[ "$PATH" = "$OLD_PATH" ] || {
    echo "export PATH=\"$(lk_esc "$PATH")\""
}
cat <<EOF
unset LK_ADD_TO_PATH LK_ADD_TO_PATH_FIRST
export SUDO_PROMPT="[sudo] password for %p: "
export WP_CLI_CONFIG_PATH="\$LK_BASE/etc/wp-cli.yml"
EOF

! type brew >/dev/null 2>&1 ||
    ! BREW_SH=$(brew shellenv 2>/dev/null) ||
    cat <<EOF
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_CASK_OPTS=--no-quarantine
$BREW_SH
EOF
