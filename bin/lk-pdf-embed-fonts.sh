#!/bin/bash

. lk-bash-load.sh || exit
lk_include provision

lk_assert_command_exists gs

lk_test_many lk_is_pdf "$@" || lk_usage "\
Usage: ${0##*/} PDF..."

lk_log_start

lk_console_message "Embedding fonts in $# $(lk_plural $# file files)"

! lk_is_macos ||
    export GS_FONTPATH=${GS_FONTPATH-~/Library/Fonts:/Library/Fonts:/System/Library/Fonts}

DISTILLER_PARAMS=(
    "/AutoFilterColorImages false"
    "/AutoFilterGrayImages false"
    "/ColorConversionStrategy /LeaveColorUnchanged"
    "/ColorImageFilter /FlateEncode"
    "/DownsampleColorImages false"
    "/DownsampleGrayImages false"
    "/DownsampleMonoImages false"
    "/EmbedAllFonts true"
    "/GrayImageFilter /FlateEncode"
    "/NeverEmbed []"
)

NPROC=$(nproc 2>/dev/null) || NPROC=
MEM=$(lk_system_memory_free 0) && [ "$MEM" -gt $((256 * 1024 ** 2)) ] || MEM=
GS_OPTIONS=(
    -dSAFER
    -sDEVICE=pdfwrite
    ${NPROC:+-dNumRenderingThreads="$NPROC"}
    ${MEM:+-dBufferSpace="$(lk_echo_args \
        $((MEM / 2)) \
        $((2 * 1024 ** 3)) | sort -n | head -n1)"}
    -c "33554432 setvmthreshold << ${DISTILLER_PARAMS[*]} >> setdistillerparams"
)

lk_console_detail "Command line:" "$(lk_fold_quote_args \
    gs "${GS_OPTIONS[@]}")"

ERRORS=()

i=0
for FILE in "$@"; do
    lk_console_item "Processing $((++i)) of $#:" "$FILE"
    TEMP=$(lk_file_prepare_temp -n "$FILE")
    lk_delete_on_exit "$TEMP"
    gs -q -o "$TEMP" "${GS_OPTIONS[@]}" -f "$FILE" &&
        touch -r "$FILE" -- "$TEMP" || {
        ERRORS+=("$FILE")
        continue
    }
    lk_rm -- "$FILE"
    mv -- "$TEMP" "$FILE"
    lk_console_detail "Fonts embedded successfully:" "$FILE"
done

[ ${#ERRORS[@]} -eq 0 ] ||
    lk_console_error -r \
        "Unable to process ${#ERRORS[@]} $(lk_plural \
            ${#ERRORS[@]} file files):" $'\n'"$(lk_echo_array ERRORS)" ||
    lk_die ""
