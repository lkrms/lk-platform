#!/bin/bash

. lk-bash-load.sh || exit

shopt -s nullglob

UNISON=~/.unison
if lk_is_linux; then
    lk_include linux
elif lk_is_macos; then
    [ -d "$UNISON" ] ||
        UNISON=~/"Library/Application Support/Unison"
    lk_include macos
else
    lk_die "${0##*/} not implemented on this platform"
fi

PROFILES=()
while [ $# -gt 0 ] && [[ $1 != -* ]]; do
    FILE=$UNISON/${1%.prf}
    FILE=$(lk_first_existing "$FILE.prf.template" "$FILE.prf") ||
        lk_die "profile not found: $1"
    PROFILES[${#PROFILES[@]}]=$FILE
    shift
done

[ ${#PROFILES[@]} -gt 0 ] ||
    PROFILES=("$UNISON"/*.prf{.template,})
[ ${#PROFILES[@]} -gt 0 ] || lk_die "no profiles found"

UNISONLOCALHOSTNAME=${UNISONLOCALHOSTNAME:-$(lk_hostname)}
export UNISONLOCALHOSTNAME

PROCESSED=()
FAILED=()
SKIPPED=()
i=0
for FILE in "${PROFILES[@]}"; do
    PROFILE=${FILE##*/}
    [ "$PROFILE" != default.prf ] || continue
    PROFILE=${PROFILE%.template}
    PROFILE=${PROFILE%.prf}
    # e.g. for temp.prf, look for ~/Temp, ~/Temp.local, ~/temp, ~/.temp
    for p in \
        "$(lk_upper_first "$PROFILE")"{,.local} \
        "$PROFILE" \
        ".$PROFILE"; do
        DIR=~/$p
        [ ! -d "$DIR" ] || break
    done
    [ -d "$DIR" ] &&
        [ ! -e "$DIR/.unison-skip" ] || {
        SKIPPED[${#SKIPPED[@]}]=$PROFILE
        continue
    }
    ! ((i++)) || lk_tty_print
    lk_tty_print "Syncing" "~${DIR#$HOME}"
    if [[ $FILE == *.prf.template ]]; then
        _FILE=${FILE%.prf.template}.$(lk_hostname)~
        lk_file_replace "$_FILE" "$(lk_expand_template -e "$FILE")"
    else
        _FILE=$FILE
    fi
    if unison -source "${_FILE##*/}" \
        -root "$DIR" \
        -auto \
        -logfile "$UNISON/unison.$(lk_hostname).$(lk_date_ymd).log" \
        "$@"; then
        PROCESSED[${#PROCESSED[@]}]=$PROFILE
    else
        FAILED[${#FAILED[@]}]="$PROFILE($?)"
    fi
done

[ ${#SKIPPED[@]} -eq 0 ] || {
    ! ((i++)) || lk_tty_print
    lk_tty_list SKIPPED "Skipped:" profile profiles
}

[ ${#PROCESSED[@]} -eq 0 ] || {
    ! ((i++)) || lk_tty_print
    lk_tty_list PROCESSED "Synchronised:" profile profiles \
        "$LK_BOLD$LK_GREEN"
}

[ ${#FAILED[@]} -eq 0 ] || {
    ! ((i++)) || lk_tty_print
    lk_tty_list FAILED "Failed:" profile profiles \
        "$LK_BOLD$LK_RED"
    lk_tty_print
    lk_tty_pause
    lk_die ""
}
