#!/bin/bash

function _lk_mail_ready() {
    lk_is_true "${_LK_MAIL_READY:-}" ||
        lk_warn "lk_mail_new must be called before $(lk_myself -f 1)" || return
}

function lk_mail_new() {
    _LK_MAIL_TEXT=
    _LK_MAIL_HTML=
    _LK_MAIL_ATTACH=()
    _LK_MAIL_ATTACH_NAME=()
    _LK_MAIL_ATTACH_TYPE=()
    _LK_MAIL_READY=1
}

function lk_mail_set_text() {
    _lk_mail_ready || return
    _LK_MAIL_TEXT=$1
}

function lk_mail_set_html() {
    _lk_mail_ready || return
    _LK_MAIL_HTML=$1
}

# lk_mail_attach FILE_PATH [FILE_NAME [MIME_TYPE]]
function lk_mail_attach() {
    local FILE_NAME MIME_TYPE
    _lk_mail_ready || return
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    FILE_NAME=${2:-${1##*/}}
    MIME_TYPE=${3:-$(file --brief --mime-type "$(realpath "$1")")} ||
        MIME_TYPE=application/octet-stream
    _LK_MAIL_ATTACH+=("$1")
    _LK_MAIL_ATTACH_NAME+=("$FILE_NAME")
    _LK_MAIL_ATTACH_TYPE+=("$MIME_TYPE")
}

# _lk_mail_get_part CONTENT CONTENT_TYPE [ENCODING [HEADER...]]
function _lk_mail_get_part() {
    local BOUNDARY=${ALT_BOUNDARY:-$BOUNDARY}
    cat <<EOF
${BOUNDARY:+${PREAMBLE:+$PREAMBLE
}--${ALT_BOUNDARY:-$BOUNDARY}
}Content-Type: $2${3:+
Content-Transfer-Encoding: $3}$([ $# -lt 4 ] || printf '\n%s' "${@:4}")
${1:+
$1}
EOF
    PREAMBLE=
}

function _lk_mail_end_parts() {
    [ -z "${!1}" ] || {
        printf -- '--%s--\n\n' "${!1}"
        eval "$1="
    }
}

# lk_mail_get_mime SUBJECT TO [FROM [HEADERS...]]
#
# shellcheck disable=SC2097,SC2098
function lk_mail_get_mime() {
    local SUBJECT TO FROM HEADERS BOUNDARY='' ALT_BOUNDARY='' ALT_TYPE i \
        TEXT_PART=() TEXT_PART_TYPE=() ENCODING=8bit CHARSET=utf-8 \
        PREAMBLE="This is a multi-part message in MIME format."
    _lk_mail_ready || return
    [ $# -ge 2 ] || lk_warn "invalid arguments" || return
    SUBJECT=$1
    TO=$2
    FROM=${3:-${LK_MAIL_FROM-$({ ADDRESS=${USER:-nobody}@$(hostname -f) ||
        ADDRESS=${USER:-nobody}@localhost; } &&
        { NAME=$(lk_full_name 2>/dev/null) ||
            NAME=${USER:-nobody}; } &&
        printf '"%s" <%s>' \
            "${NAME//\"/\\\"}" \
            "$ADDRESS")}}
    [[ ! $SUBJECT$TO$FROM =~ .*[$'\r\n'].* ]] ||
        lk_warn "line breaks not permitted in SUBJECT, TO, or FROM" ||
        return
    HEADERS=(
        "From: $FROM"
        "To: $TO"
        "Date: $(date -R)"
        "Subject: $SUBJECT"
        "${@:4}"
    )
    TEXT_PART=(${_LK_MAIL_TEXT:+"$_LK_MAIL_TEXT"}
        ${_LK_MAIL_HTML:+"$_LK_MAIL_HTML"})
    TEXT_PART_TYPE=(${_LK_MAIL_TEXT:+"text/plain"}
        ${_LK_MAIL_HTML:+"text/html"})
    lk_echo_array TEXT_PART |
        LC_ALL=C \
            grep -v "^[[:alnum:][:space:][:punct:][:cntrl:]]*\$" >/dev/null || {
        ENCODING=7bit
        CHARSET=us-ascii
    }
    [ ${#TEXT_PART[@]} -le 1 ] || {
        ALT_BOUNDARY=$(lk_random_hex 12)
        ALT_TYPE="multipart/alternative; boundary=$ALT_BOUNDARY"
    }
    [ ${#_LK_MAIL_ATTACH[@]} -eq 0 ] ||
        { [ ${#_LK_MAIL_ATTACH[@]} -eq 1 ] && [ ${#TEXT_PART[@]} -eq 0 ]; } ||
        BOUNDARY=$(lk_random_hex 12)
    [ -z "${BOUNDARY:-$ALT_BOUNDARY}" ] || {
        HEADERS+=("MIME-Version: 1.0")
        [ -n "$BOUNDARY" ] &&
            HEADERS+=("Content-Type: multipart/mixed; boundary=$BOUNDARY") ||
            HEADERS+=("Content-Type: $ALT_TYPE"
                "Content-Transfer-Encoding: $ENCODING")
        HEADERS+=("")
    }
    lk_echo_array HEADERS
    [ -z "$BOUNDARY" ] || [ -z "$ALT_BOUNDARY" ] ||
        ALT_BOUNDARY='' _lk_mail_get_part "" "$ALT_TYPE" "$ENCODING"
    for i in "${!TEXT_PART[@]}"; do
        _lk_mail_get_part "${TEXT_PART[$i]%$'\n'}"$'\n' \
            "${TEXT_PART_TYPE[$i]}; charset=$CHARSET" "$ENCODING"
    done
    _lk_mail_end_parts ALT_BOUNDARY
    for i in "${!_LK_MAIL_ATTACH[@]}"; do
        # TODO: implement lk_maybe_encode_header_value
        _lk_mail_get_part "" \
            "$(printf '%s; name="%s"' \
                "${_LK_MAIL_ATTACH_TYPE[$i]}" \
                "${_LK_MAIL_ATTACH_NAME[$i]//\"/\\\"}")" \
            "base64" \
            "$(printf 'Content-Disposition: attachment; filename="%s"' \
                "${_LK_MAIL_ATTACH_NAME[$i]//\"/\\\"}")"
        lk_base64 <"${_LK_MAIL_ATTACH[$i]}" || return
    done
    _lk_mail_end_parts BOUNDARY
}

# lk_mail_send SUBJECT TO [FROM [HEADERS...]]
function lk_mail_send() {
    local MTA
    _lk_mail_ready || return
    [ $# -ge 2 ] || lk_usage "\
Usage: $(lk_myself -f) SUBJECT TO [FROM [HEADERS...]]" || return
    MTA=$(lk_command_first_existing sendmail msmtp) ||
        lk_warn "MTA not found" || return
    lk_mail_get_mime "$@" | "$MTA" -oi -t
}
