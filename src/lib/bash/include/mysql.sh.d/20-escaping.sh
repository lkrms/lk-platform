#!/usr/bin/env bash

# lk_mysql_escape [<string>]
#
# Escape a string for use in SQL and enclose it in single quotes.
function lk_mysql_escape() {
    local s=${1-}
    s=${s//\\/\\\\}
    s=${s//"'"/"\\'"}
    s=${s//$'\x1a'/\\Z}
    printf "'%s'\n" "$s"
}

# lk_mysql_escape_like [<string>]
#
# Escape a string for use with the SQL `LIKE` operator. Callers MUST enclose
# output in single quotes.
function lk_mysql_escape_like() {
    local s=${1-}
    s=${s//\\/\\\\}
    s=${s//"'"/"\\'"}
    s=${s//'%'/'\%'}
    s=${s//_/\\_}
    s=${s//$'\x1a'/\\Z}
    printf '%s\n' "$s"
}

# lk_mysql_escape_identifier [<identifier>]
#
# Escape an identifier and enclose it in backticks.
function lk_mysql_escape_identifier() {
    local s=${1-}
    s=${s//\`/\`\`}
    printf '`%s`' "$s"
}

# lk_mysql_option_escape [<value>]
#
# Escape a value for use in an option file and enclose it in double quotes.
function lk_mysql_option_escape() {
    local s=${1-}
    s=${s//\\/\\\\}
    s=${s//'"'/'\"'}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    s=${s//$'\b'/\\b}
    printf '"%s"\n' "$s"
}

#### Reviewed: 2025-09-03
