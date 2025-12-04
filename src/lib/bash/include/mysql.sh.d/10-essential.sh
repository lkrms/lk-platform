#!/usr/bin/env bash

function lk_mysql_is_quiet() {
    [[ -n ${_LK_MYSQL_QUIET:+1} ]]
}

#### Reviewed: 2025-09-03
