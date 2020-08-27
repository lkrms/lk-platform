#!/bin/bash

# lk_dir_set_permissions DIR [WRITABLE_REGEX [OWNER][:[GROUP]]]
function lk_dir_set_permissions() {
    local DIR="${1:-}" WRITABLE_REGEX="${2:-}" OWNER="${3:-}" \
        LOG_DIR WRITABLE TYPE MODE ARGS \
        DIR_MODE="${LK_DIR_MODE:-0755}" \
        FILE_MODE="${LK_FILE_MODE:-0644}" \
        WRITABLE_DIR_MODE="${LK_WRITABLE_DIR_MODE:-0775}" \
        WRITABLE_FILE_MODE="${LK_WRITABLE_FILE_MODE:-0664}"
    [ -d "$DIR" ] || lk_warn "not a directory: $DIR" || return
    DIR="$(realpath "$DIR")" &&
        LOG_DIR="$(lk_mktemp_dir)" || return
    lk_console_item "Setting permissions on" "$DIR"
    lk_console_detail "Logging changes in" "$LOG_DIR" "$LK_RED"
    lk_console_detail "File modes:" "$DIR_MODE, $FILE_MODE"
    [ -z "$WRITABLE_REGEX" ] || {
        lk_console_detail "Writable file modes:" "$WRITABLE_DIR_MODE, $WRITABLE_FILE_MODE"
        lk_console_detail "Writable paths:" "$WRITABLE_REGEX"
    }
    [ -z "$OWNER" ] ||
        if lk_is_root || lk_is_true "$(lk_get_maybe_sudo)"; then
            lk_console_detail "Owner:" "$OWNER"
            lk_maybe_sudo chown -Rhc "$OWNER" "$DIR" >"$LOG_DIR/chown.log" || return
            lk_console_detail "File ownership changes:" "$(wc -l <"$LOG_DIR/chown.log")" "$LK_GREEN"
        else
            lk_console_warning "Unable to set owner (not running as root)"
        fi
    for WRITABLE in "" w; do
        [ -z "$WRITABLE" ] || [ -n "$WRITABLE_REGEX" ] || continue
        for TYPE in d f; do
            case "$WRITABLE$TYPE" in
            d)
                MODE="$DIR_MODE"
                ;;
            f)
                MODE="$FILE_MODE"
                ;;
            wd)
                MODE="$WRITABLE_DIR_MODE"
                ;;
            wf)
                MODE="$WRITABLE_FILE_MODE"
                ;;
            esac
            ARGS=(-type "$TYPE" ! -perm "$MODE")
            case "$WRITABLE$TYPE" in
            d | f)
                # exclude writable directories and their descendants
                ARGS=(! \( -type d -regex "$WRITABLE_REGEX" -prune \) "${ARGS[@]}")
                [ "$WRITABLE$TYPE" != f ] ||
                    # exclude writable files (i.e. not just files in writable directories)
                    ARGS+=(! -regex "$WRITABLE_REGEX")
                ;;
            w*)
                ARGS+=(-regex "$WRITABLE_REGEX(/.*)?")
                ;;
            esac
            find "$DIR" -regextype posix-egrep "${ARGS[@]}" -print0 |
                lk_maybe_sudo gnu_xargs -0r chmod -c "0$MODE" >>"$LOG_DIR/chmod.log" || return
        done
    done
    lk_console_detail "File mode changes:" "$(wc -l <"$LOG_DIR/chmod.log")" "$LK_GREEN"
}

# lk_sudo_offer_nopasswd
#   Invite the current user to add themselves to the system's sudoers policy
#   with unlimited access and no password prompts.
function lk_sudo_offer_nopasswd() {
    local FILE
    FILE="/etc/sudoers.d/nopasswd-$USER"
    ! lk_is_root || lk_warn "cannot run as root" || return
    sudo -n test -e "$FILE" 2>/dev/null || {
        lk_can_sudo install || return
        lk_confirm "Allow user '$USER' to run sudo without entering a password?" Y || return
        sudo install -m 440 /dev/null "$FILE" &&
            sudo tee "$FILE" >/dev/null <<<"$USER ALL=(ALL) NOPASSWD:ALL" &&
            lk_console_message "User '$USER' may now run any command as any user" || return
    }
}
