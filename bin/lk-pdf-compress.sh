#!/bin/bash

. lk-bash-load.sh || exit

lk_assert_command_exists gs

lk_test_many lk_is_pdf "$@" || lk_usage "\
Usage: ${0##*/} PDF..."

lk_log_start

lk_console_message "Compressing $# $(lk_plural $# file files)"

# Adobe Distiller defaults (see:
# https://www.adobe.com/content/dam/acom/en/devnet/acrobat/pdfs/distillerparameters.pdf)
DISTILLER_MINIMUM_QUALITY="<< /HSamples [2 1 1 2] /VSamples [2 1 1 2] /QFactor 2.40 /Blend 1 >>"
DISTILLER_LOW_QUALITY="<< /HSamples [2 1 1 2] /VSamples [2 1 1 2] /QFactor 1.30 /Blend 1 >>"
DISTILLER_MEDIUM_QUALITY="<< /HSamples [2 1 1 2] /VSamples [2 1 1 2] /QFactor 0.76 /Blend 1 >>"
DISTILLER_HIGH_QUALITY="<< /HSamples [1 1 1 1] /VSamples [1 1 1 1] /QFactor 0.40 /Blend 1 >>"
DISTILLER_MAXIMUM_QUALITY="<< /HSamples [1 1 1 1] /VSamples [1 1 1 1] /QFactor 0.15 /Blend 1 >>"

# Ghostscript defaults (see:
# https://www.ghostscript.com/doc/VectorDevices.htm#note_7)
GS_DEFAULT="<< /HSamples [2 1 1 2] /VSamples [2 1 1 2] /QFactor 0.9 /Blend 1 >>"
GS_PRINTER_ACS="<< /HSamples [1 1 1 1] /VSamples [1 1 1 1] /QFactor 0.4 /Blend 1 /ColorTransform 1 >>"
GS_PREPRESS_ACS="<< /HSamples [1 1 1 1] /VSamples [1 1 1 1] /QFactor 0.15 /Blend 1 /ColorTransform 1 >>"
GS_SCREEN_EBOOK_ACS="<< /HSamples [2 1 1 2] /VSamples [2 1 1 2] /QFactor 0.76 /Blend 1 /ColorTransform 1 >>"

IMAGE_DICT=${IMAGE_DICT:-GS_DEFAULT}
ACS_IMAGE_DICT=${ACS_IMAGE_DICT:-IMAGE_DICT}

# In my unscientific testing, 144 didn't quite cut it with handwriting
COLOR_DPI=${COLOR_DPI:-200}
GRAY_DPI=${GRAY_DPI:-200}
MONO_DPI=${MONO_DPI:-300}

# Only downsample when the ratio of input resolution to output resolution
# exceeds:
COLOR_DPI_THRESHOLD=${COLOR_DPI_THRESHOLD:-1}
GRAY_DPI_THRESHOLD=${GRAY_DPI_THRESHOLD:-1}
MONO_DPI_THRESHOLD=${MONO_DPI_THRESHOLD:-1}

# Keep the original PDF unless file size is reduced by at least this much
PERCENT_SAVED_THRESHOLD=${PERCENT_SAVED_THRESHOLD:-2}

IMAGE_DICT=${!IMAGE_DICT}
ACS_IMAGE_DICT=${!ACS_IMAGE_DICT}

DISTILLER_PARAMS=(
    "/ColorImageDict $IMAGE_DICT"
    "/ColorACSImageDict $ACS_IMAGE_DICT"
    "/ColorImageResolution $COLOR_DPI"
    "/ColorImageDownsampleThreshold $COLOR_DPI_THRESHOLD"
    "/ColorImageDownsampleType /Bicubic"
    "/GrayImageDict $IMAGE_DICT"
    "/GrayACSImageDict $ACS_IMAGE_DICT"
    "/GrayImageResolution $GRAY_DPI"
    "/GrayImageDownsampleThreshold $GRAY_DPI_THRESHOLD"
    "/GrayImageDownsampleType /Bicubic"
    "/MonoImageResolution $MONO_DPI"
    "/MonoImageDownsampleThreshold $MONO_DPI_THRESHOLD"

    # Default: true
    "/EmbedAllFonts false"

    # Re-encode even if not downsampling
    "/PassThroughJPEGImages false"
)

NPROC=$(nproc 2>/dev/null) || NPROC=
MEM=$(lk_system_memory_free 0) && [ "$MEM" -gt $((256 * 1024 ** 2)) ] || MEM=
GS_OPTIONS=(
    -dSAFER
    -sDEVICE=pdfwrite
    "-dPDFSETTINGS=${PDFSETTINGS:-/screen}"
    ${NPROC:+-dNumRenderingThreads="$NPROC"}
    ${MEM:+-dBufferSpace="$(lk_echo_args \
        $((MEM / 2)) \
        $((2 * 1024 ** 3)) | sort -n | head -n1)"}
    -c "33554432 setvmthreshold << ${DISTILLER_PARAMS[*]} >> setdistillerparams"
)

lk_console_detail "Command line:" "$(lk_quote_args_folded \
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
    OLD_SIZE=$(gnu_stat -Lc %s -- "$FILE")
    NEW_SIZE=$(gnu_stat -Lc %s -- "$TEMP")
    ((SAVED = OLD_SIZE - NEW_SIZE)) || true
    if [ "$SAVED" -ge 0 ]; then
        ((PERCENT_SAVED = (SAVED * 100 + (OLD_SIZE - 1)) / OLD_SIZE)) || true
        lk_console_detail "File size" \
            "reduced by $PERCENT_SAVED% ($SAVED bytes)" "$LK_GREEN"
    else
        ((PERCENT_SAVED = -((OLD_SIZE - 1) - SAVED * 100) / OLD_SIZE)) || true
        lk_console_detail "File size" \
            "increased by $((-PERCENT_SAVED))% ($((-SAVED)) bytes)" "$LK_RED"
    fi
    if [ "$PERCENT_SAVED" -lt "$PERCENT_SAVED_THRESHOLD" ]; then
        lk_console_detail "Keeping original:" "$FILE"
        continue
    fi
    if lk_command_exists trash-put; then
        trash-put -- "$FILE"
    else
        lk_file_backup -m "$FILE"
        rm -- "$FILE"
    fi
    mv -- "$TEMP" "$FILE"
    lk_console_detail "Compressed successfully:" "$FILE"
done

[ ${#ERRORS[@]} -eq 0 ] ||
    lk_console_error -r \
        "Unable to process ${#ERRORS[@]} $(lk_plural \
            ${#ERRORS[@]} file files):" $'\n'"$(lk_echo_array ERRORS)" ||
    lk_die ""
