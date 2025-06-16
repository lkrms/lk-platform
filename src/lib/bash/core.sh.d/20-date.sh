#!/usr/bin/env bash

# lk_date FORMAT [TIMESTAMP]
function lk_date() {
    # Take advantage of printf support for strftime in Bash 4.2+
    if lk_bash_at_least 4 2; then
        function lk_date() {
            printf "%($1)T\n" "${2:--1}"
        }
    elif ! lk_is_macos; then
        function lk_date() {
            if (($# < 2)); then
                date "+$1"
            else
                date -d "@$2" "+$1"
            fi
        }
    else
        function lk_date() {
            if (($# < 2)); then
                date "+$1"
            else
                date -jf '%s' "$2" "+$1"
            fi
        }
    fi
    lk_date "$@"
}

# lk_date_log [TIMESTAMP]
function lk_date_log() { lk_date "%Y-%m-%d %H:%M:%S %z" "$@"; }

# lk_date_ymdhms [TIMESTAMP]
function lk_date_ymdhms() { lk_date "%Y%m%d%H%M%S" "$@"; }

# lk_date_ymd [TIMESTAMP]
function lk_date_ymd() { lk_date "%Y%m%d" "$@"; }

# lk_date_http [TIMESTAMP]
function lk_date_http() { TZ=UTC lk_date "%a, %d %b %Y %H:%M:%S %Z" "$@"; }

# lk_timestamp
function lk_timestamp() { lk_date "%s"; }

# _lk_duration_unit VALUE UNIT
function _lk_duration_unit() {
    ((UNITS < 3)) || return 0
    local UNIT=$2
    if ((UNITS)); then
        UNIT=${2:0:1}
    else
        (($1 == 1)) || UNIT+=s
        UNIT=" $UNIT"
    fi
    ((!$1)) && [[ $UNIT != " s"* ]] || {
        ((UNITS != 1)) || DUR+=", "
        DUR+=$1$UNIT
        ((++UNITS))
    }
}

# lk_duration SECONDS
#
# Format SECONDS as a user-friendly duration.
function lk_duration() {
    local UNITS=0 DUR=
    _lk_duration_unit $(($1 / 86400)) day
    _lk_duration_unit $((($1 % 86400) / 3600)) hour
    _lk_duration_unit $((($1 % 3600) / 60)) minute
    _lk_duration_unit $(($1 % 60)) second
    echo "$DUR"
}

#### Reviewed: 2022-10-14
