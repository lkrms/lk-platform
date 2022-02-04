#!/bin/bash

# lk_date FORMAT [TIMESTAMP]
function lk_date() {
    # Take advantage of printf support for strftime in Bash 4.2+
    if lk_bash_at_least 4 2; then
        function lk_date() {
            printf "%($1)T\n" "${2:--1}"
        }
    elif ! lk_is_macos; then
        function lk_date() {
            if [ $# -lt 2 ]; then
                date "+$1"
            else
                date -d "@$2" "+$1"
            fi
        }
    else
        function lk_date() {
            if [ $# -lt 2 ]; then
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

#### Reviewed: 2021-11-16
