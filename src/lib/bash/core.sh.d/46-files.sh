#!/bin/bash

# lk_file_list_duplicates [DIR]
#
# Print a list of files in DIR or the current directory that would be considered
# duplicates on a case-insensitive filesystem. Only useful on case-sensitive
# filesystems.
function lk_file_list_duplicates() {
    find "${1:-.}" -print0 | sort -zf | gnu_uniq -zDi | tr '\0' '\n'
}
