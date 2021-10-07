#!/bin/bash

# lk_hosting_php_get_settings PREFIX SETTING=VALUE...
#
# Print each PHP setting as a PHP-FPM pool directive. If the same SETTING is
# given more than once, only use the first VALUE.
#
# Example:
#
#     $ lk_hosting_php_get_settings php_admin_ log_errors=On memory_limit=80M
#     php_admin_flag[log_errors] = On
#     php_admin_value[memory_limit] = 80M
function lk_hosting_php_get_settings() {
    [ $# -gt 1 ] || lk_warn "no settings" || return
    printf '%s\n' "${@:2}" | awk -F= -v prefix="$1" -v null='""' '
/^[^[:space:]=]+=/ {
  setting = $1
  if(!arr[setting]) {
    sub("^[^=]+=", "")
    arr[setting] = $0 ? $0 : null
    keys[i++] = setting }
  next }
{ status = 2 }
END {
  for (i = 0; i < length(keys); i++) {
    setting = keys[i]
    if(prefix == "env") {
      suffix = "" }
    else if(tolower(arr[setting]) ~ "^(on|true|yes|off|false|no)$") {
      suffix = "flag" }
    else {
      suffix = "value" }
    if (arr[setting] == null) {
      arr[setting] = "" }
    printf("%s%s[%s] = %s\n", prefix, suffix, setting, arr[setting]) }
  exit status }'
}

#### Reviewed: 2021-10-07
