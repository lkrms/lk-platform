#!/bin/bash

lk_bin_depth=1 . lk-bash-load.sh || exit

SOURCE_FILES=()
SOURCE_ROOT=
SOURCE_EXT=
TARGET_ROOT=
PRESET="General/HQ 1080p30 Surround"
TARGET_EXT=m4v

function __usage() {
    cat <<EOF
Encode one or more video files with HandBrakeCLI.

Usage:
  ${0##*/} [options] <SOURCE_FILE>... [TARGET_DIR]
  ${0##*/} [options] <SOURCE_DIR> [TARGET_DIR]
  ${0##*/} [options] <SOURCE_DIR> <SOURCE_EXT> <TARGET_DIR>

Options:
  -Z, --preset=<PRESET>     Select preset by name (case-sensitive).
                            [default: $PRESET]
  -x, --target-ext=<EXT>    Set output file extension.
                            [default: $TARGET_EXT]

TARGET_DIR overrides environment variable LK_HANDBRAKE_TARGET. If neither are
set, files are encoded to the current directory.

To list available presets:
  HandBrakeCLI --preset-import-gui -z

To stop processing after the current encode:
  touch ~/.lk-handbrake-stop
EOF
}

lk_getopt "Z:x:" "preset:,target-ext:"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -Z | --preset)
        PRESET=$1
        shift
        ;;
    -x | --target-ext)
        TARGET_EXT=${1#.}
        shift
        ;;
    --)
        break
        ;;
    esac
done

if lk_files_exist "$@"; then
    # <SOURCE_FILE>...
    SOURCE_FILES=("$@")
elif [ $# -gt 1 ] && [ -d "${*: -1}" ] && lk_files_exist "${@:1:$#-1}"; then
    # <SOURCE_FILE>... <TARGET_DIR>
    SOURCE_FILES=("${@:1:$#-1}")
    TARGET_ROOT=${*: -1}
elif [ $# -le 3 ] && [ -d "${1-}" ] &&
    { [ $# -eq 1 ] || [ -d "${*: -1}" ]; }; then
    # <SOURCE_DIR>
    SOURCE_ROOT=$(realpath "$1")
    SOURCE_PARENT=${SOURCE_ROOT%/*}
    # <SOURCE_DIR> [<SOURCE_EXT>] <TARGET_DIR>
    [ $# -eq 1 ] || TARGET_ROOT=${*: -1}
    [ $# -lt 3 ] || SOURCE_EXT=${2#.}
    while IFS= read -rd '' SOURCE_FILE; do
        SOURCE_FILES[${#SOURCE_FILES[@]}]=$SOURCE_FILE
    done < <(find "$SOURCE_ROOT" -type f \
        ! -name ".*" -iname "*.${SOURCE_EXT:-mkv}" -print0 | sort -z)
fi

[ -n "${SOURCE_FILES+1}" ] || lk_usage

TARGET_ROOT=${TARGET_ROOT:-${LK_HANDBRAKE_TARGET:-$PWD}}
TARGET_ROOT=${TARGET_ROOT%/}
[ -d "$TARGET_ROOT" ] || mkdir -pv "$TARGET_ROOT" ||
    lk_die "directory not found: $TARGET_ROOT"
TARGET_FILES=()
ENCODE_LIST=()

lk_tty_print "Preparing batch"
for SOURCE_FILE in "${SOURCE_FILES[@]}"; do
    TARGET_SUBFOLDER=
    if [ -n "${SOURCE_ROOT:+1}" ]; then
        TARGET_SUBFOLDER=${SOURCE_FILE%/*}
        TARGET_SUBFOLDER=${TARGET_SUBFOLDER#$SOURCE_PARENT}
    fi
    TARGET_FILE=$TARGET_ROOT$TARGET_SUBFOLDER/${SOURCE_FILE##*/}
    TARGET_FILE=${TARGET_FILE%.*}.$TARGET_EXT
    if [ -e "$TARGET_FILE" ]; then
        lk_tty_warning "Skipping (target already exists):" "$SOURCE_FILE"
        TARGET_FILE=
    else
        ENCODE_LIST[${#ENCODE_LIST[@]}]="$SOURCE_FILE -> $TARGET_FILE"
    fi
    TARGET_FILES[${#TARGET_FILES[@]}]=$TARGET_FILE
done

[ "${#ENCODE_LIST[@]}" -gt "0" ] ||
    lk_die "nothing to encode"

lk_tty_list_detail ENCODE_LIST "Queued:" encode encodes
lk_tty_detail "HandBrake preset:" "$PRESET"
lk_confirm "Proceed?" Y || lk_die

SUCCESS_FILES=()
ERROR_FILES=()

{
    for i in "${!SOURCE_FILES[@]}"; do
        [ ! -e ~/.lk-handbrake-stop ] || break
        TARGET_FILE=${TARGET_FILES[i]}
        [ -n "${TARGET_FILE:+1}" ] || continue
        SOURCE_FILE=${SOURCE_FILES[i]}
        TARGET_DIR=${TARGET_FILE%/*}
        [ -d "$TARGET_DIR" ] || mkdir -pv "$TARGET_DIR" ||
            lk_die "could not create directory: $TARGET_DIR"
        LOG_FILE=${SOURCE_FILE%/*}/.${SOURCE_FILE##*/}-HandBrakeCLI.log
        STATUS=0
        if ! lk_run HandBrakeCLI --preset-import-gui --preset "$PRESET" \
            --input "$SOURCE_FILE" --output "$TARGET_FILE" \
            2> >(tee "$LOG_FILE" >&2); then
            STATUS=$?
            ERROR_FILES[${#ERROR_FILES[@]}]=$SOURCE_FILE
        else
            SUCCESS_FILES[${#SUCCESS_FILES[@]}]=$SOURCE_FILE
        fi
        echo "$(lk_date_log) HandBrakeCLI exit code: $STATUS" |
            tee -a "$LOG_FILE"
    done

    [ ${#SUCCESS_FILES[@]} -eq 0 ] ||
        lk_tty_list SUCCESS_FILES "Encoded successfully:" file files "$LK_GREEN"
    [ ${#ERROR_FILES[@]} -eq 0 ] ||
        lk_tty_list ERROR_FILES "Failed to encode:" file files "$LK_RED"

    rm -f ~/.lk-handbrake-stop

    [ ${#ERROR_FILES[@]} -eq 0 ] || lk_die ""
    exit
}
