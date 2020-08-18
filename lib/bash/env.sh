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
IFS=:
for DIR in $ADD_TO_PATH; do
    PATH="$(lk_path_add "$DIR")"
done
unset IFS
PATH="$(lk_path_add_to_front "${HOME:+$HOME/.homebrew/bin:$HOME/.local/bin}")"
[ "$PATH" = "$OLD_PATH" ] || {
    echo "export PATH=\"$(lk_esc "$PATH")\""
}
cat <<EOF
unset LK_ADD_TO_PATH
export SUDO_PROMPT="[sudo] password for %u: "
export WP_CLI_CONFIG_PATH="\$LK_BASE/etc/wp-cli.yml"
EOF

! type brew >/dev/null 2>&1 || cat <<EOF
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_CASK_OPTS="--appdir=\"\${HOMEBREW_CASK_APPDIR:-\$HOME/Applications}\" --no-quarantine"
EOF
