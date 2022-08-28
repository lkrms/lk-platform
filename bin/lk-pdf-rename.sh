#!/bin/bash

. lk-bash-load.sh || exit

shopt -s nullglob nocaseglob

lk_assert_command_exists qpdfview

[[ ${1-} != -- ]] || shift

if lk_files_exist "$@"; then
    TRIAGE=0
elif lk_dirs_exist "$@"; then
    TRIAGE=1
else
    lk_usage "\
Usage: ${0##*/} PDF...
   or: ${0##*/} [DIR...] TARGET_DIR"
fi

function get_targets_sh() {
    cd "$TARGET" &&
        TARGETS=("$(pwd -P)"/*/) || exit
    [[ -n ${TARGETS+1} ]] ||
        lk_die "no directories found in $TARGET"
    TARGETS=("${TARGETS[@]%/}")
    TARGET_BASENAMES=("${TARGETS[@]##*/}")
    declare -p TARGETS TARGET_BASENAMES
}

lk_command_exists wmctrl &&
    WINDOW_ID=$(xdotool getactivewindow 2>/dev/null) ||
    WINDOW_ID=

lk_log_start

if ((TRIAGE)); then
    # Remove any trailing slashes
    set -- "${@%/}"
    TARGET=${*: -1}
    set -- "${@:1:$#-1}"
    # Use the target as the source if it's the only argument
    (($#)) || set -- "$TARGET"
    # Populate TARGETS and TARGET_BASENAMES
    SH=$(get_targets_sh) && eval "$SH" || lk_die ""
    while (($#)); do
        FILES+=("$1"/*.pdf)
        shift
    done
    [[ ${FILES+1} ]] || lk_die "nothing to rename"
    set -- "${FILES[@]}"
fi

i=0
for FILE in "$@"; do
    lk_tty_print "Processing $((++i)) of $#:" "$FILE"
    lk_is_pdf "$FILE" || lk_warn "skipping (not a PDF)" || continue
    # Open the PDF in qpdfview and reclaim focus after 0.5 seconds
    nohup qpdfview --unique --instance lk_pdf_rename "$FILE" &>/dev/null &
    disown
    [[ -z $WINDOW_ID ]] || {
        sleep 0.5
        wmctrl -ia "$WINDOW_ID"
    }
    NAME=${FILE##*/}
    lk_tty_read "Rename to:" NEW_NAME
    [[ -n $NEW_NAME ]] || continue
    NEW_NAME=${NEW_NAME%.[pP][dD][fF]}.pdf
    [[ $(lk_lower "$NAME") != "$(lk_lower "$NEW_NAME")" ]] || continue
    NEW_FILE=$(dirname "$FILE")/$NEW_NAME
    NEW_FILE=${NEW_FILE#./}

    PREFERRED_FILE=$NEW_FILE
    seq=1
    while [[ -e $NEW_FILE ]]; do
        NEW_FILE="${PREFERRED_FILE%.pdf} ($((++seq))).pdf"
    done
    mv -n "$FILE" "$NEW_FILE" || lk_die "error renaming $FILE to $NEW_FILE"
    if [[ $NEW_FILE == "$PREFERRED_FILE" ]]; then
        lk_tty_success "Renamed to" "${NEW_FILE##*/}"
    else
        lk_tty_warning "${PREFERRED_FILE##*/} already exists, renamed to" "${NEW_FILE##*/}"
    fi
done
