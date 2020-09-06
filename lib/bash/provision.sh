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

# lk_apply_setting <FILE> <SETTING> <VAL> [<DELIM>] [<COMMENT_CHARS>] [<SPACES>]
#
# Set value of SETTING to VAL in FILE.
#
# Notes:
# - DELIM defaults to "="
# - To uncomment an existing SETTING assignment first, use COMMENT_CHARS to
#   specify which characters can be removed from the beginning of lines
# - Use SPACES to specify whitespace characters considered legal before and
#   after SETTING, VAL and DELIMITER
function lk_apply_setting() {
    local FILE_PATH="$1" SETTING_NAME="$2" SETTING_VALUE="$3" DELIMITER="${4:-=}" \
        COMMENT_PATTERN SPACE_PATTERN NAME_ESCAPED VALUE_ESCAPED DELIMITER_ESCAPED CHECK_PATTERN SEARCH_PATTERN REPLACE REPLACED
    lk_maybe_sudo test -f "$FILE_PATH" || lk_warn "$FILE_PATH must exist" || return
    COMMENT_PATTERN="${5:+[$(lk_escape_ere "$5")]*}"
    SPACE_PATTERN="${6:+[$(lk_escape_ere "$6")]*}"
    NAME_ESCAPED="$(lk_escape_ere "$SETTING_NAME")"
    VALUE_ESCAPED="$(lk_escape_ere "$SETTING_VALUE")"
    DELIMITER_ESCAPED="$(sed -Ee "s/^$SPACE_PATTERN//" -e "s/$SPACE_PATTERN\$//" <<<"$DELIMITER")"
    [ -n "$DELIMITER_ESCAPED" ] || DELIMITER_ESCAPED="$DELIMITER"
    DELIMITER_ESCAPED="$(lk_escape_ere "$DELIMITER_ESCAPED")"
    CHECK_PATTERN="^$SPACE_PATTERN$NAME_ESCAPED$SPACE_PATTERN$DELIMITER_ESCAPED$SPACE_PATTERN$VALUE_ESCAPED$SPACE_PATTERN\$"
    grep -Eq "$CHECK_PATTERN" "$FILE_PATH" || {
        REPLACE="$SETTING_NAME$DELIMITER$SETTING_VALUE"
        # try to replace an uncommented value first
        SEARCH_PATTERN="^($SPACE_PATTERN)$NAME_ESCAPED$SPACE_PATTERN$DELIMITER_ESCAPED.*\$"
        REPLACED="$(sed -E "0,/$SEARCH_PATTERN/{s/$SEARCH_PATTERN/\\1$(lk_escape_ere_replace "$REPLACE")/}" "$FILE_PATH")" || return
        # failing that, try for a commented one
        grep -Eq "$CHECK_PATTERN" <<<"$REPLACED" || {
            SEARCH_PATTERN="^($SPACE_PATTERN)$COMMENT_PATTERN($SPACE_PATTERN)$NAME_ESCAPED$SPACE_PATTERN$DELIMITER_ESCAPED.*\$"
            REPLACED="$(sed -E "0,/$SEARCH_PATTERN/{s/$SEARCH_PATTERN/\\1\\2$(lk_escape_ere_replace "$REPLACE")/}" "$FILE_PATH")" || return
        }
        lk_keep_original "$FILE_PATH" || return
        if grep -Eq "$CHECK_PATTERN" <<<"$REPLACED"; then
            lk_maybe_sudo tee "$FILE_PATH" <<<"$REPLACED" >/dev/null || return
        else
            {
                echo "$REPLACED"
                echo "$REPLACE"
            } | lk_maybe_sudo tee "$FILE_PATH" >/dev/null || return
        fi
    }
}

# LK_EXPAND_WHITESPACE=<1|0|Y|N> \
#   lk_enable_entry <FILE> <ENTRY> [<COMMENT_CHARS>] [<TRAILING_PATTERN>]
#
# Add ENTRY to FILE if not already present.
#
# Notes:
# - To uncomment an existing ENTRY line first, use COMMENT_CHARS to specify
#   which characters can be removed from the beginning of lines
# - Use TRAILING_PATTERN to provide a regular expression matching existing text
#   to retain if it appears after ENTRY (default: keep whitespace and comments)
# - LK_EXPAND_WHITESPACE allows one or more whitespace characters in ENTRY to
#   match one or more whitespace characters in FILE (default: enabled)
# - If LK_EXPAND_WHITESPACE is enabled, escaped whitespace characters in ENTRY
#   are unescaped without expansion
function lk_enable_entry() {
    local FILE_PATH="$1" ENTRY="$2" OPTIONAL_COMMENT_PATTERN COMMENT_PATTERN TRAILING_PATTERN \
        ENTRY_ESCAPED SPACE_PATTERN CHECK_PATTERN SEARCH_PATTERN REPLACED
    lk_maybe_sudo test -f "$FILE_PATH" || lk_warn "$FILE_PATH must exist" || return
    OPTIONAL_COMMENT_PATTERN="${3:+[$(lk_escape_ere "$3")]*}"
    COMMENT_PATTERN="${3:+$(lk_trim "$3")}"
    COMMENT_PATTERN="${COMMENT_PATTERN:+[$(lk_escape_ere "$COMMENT_PATTERN")]+}"
    TRAILING_PATTERN="${4-\\s+${COMMENT_PATTERN:+(${COMMENT_PATTERN}.*)?}}"
    ENTRY_ESCAPED="$(lk_escape_ere "$ENTRY")"
    SPACE_PATTERN=
    lk_is_false "${LK_EXPAND_WHITESPACE:-1}" || {
        ENTRY_ESCAPED="$(sed -Ee 's/(^|[^\])\s+/\1\\s+/g' -e 's/\\\\(\s)/\1/g' <<<"$ENTRY_ESCAPED")"
        SPACE_PATTERN='\s*'
    }
    CHECK_PATTERN="^$SPACE_PATTERN$ENTRY_ESCAPED${TRAILING_PATTERN:+($TRAILING_PATTERN)?}\$"
    grep -Eq "$CHECK_PATTERN" "$FILE_PATH" || {
        # try to replace a commented entry
        SEARCH_PATTERN="^($SPACE_PATTERN)$OPTIONAL_COMMENT_PATTERN($SPACE_PATTERN$ENTRY_ESCAPED${TRAILING_PATTERN:+($TRAILING_PATTERN)?})\$"
        REPLACED="$(sed -E "0,/$SEARCH_PATTERN/{s/$SEARCH_PATTERN/\1\2/}" "$FILE_PATH")" || return
        lk_keep_original "$FILE_PATH" || return
        if grep -Eq "$CHECK_PATTERN" <<<"$REPLACED"; then
            lk_maybe_sudo tee "$FILE_PATH" <<<"$REPLACED" >/dev/null || return
        else
            {
                echo "$REPLACED"
                echo "$ENTRY"
            } | lk_maybe_sudo tee "$FILE_PATH" >/dev/null || return
        fi
    }
}
