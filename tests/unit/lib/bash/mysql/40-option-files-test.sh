#!/usr/bin/env bash

lk_require mysql

# lk_mysql_option_bytes
assert_output_equals -1 '' lk_mysql_option_bytes 2>/dev/null
assert_output_equals -1 '' lk_mysql_option_bytes 'G' 2>/dev/null
assert_output_equals -1 '' lk_mysql_option_bytes '0B' 2>/dev/null
assert_output_equals 576 lk_mysql_option_bytes 576
assert_output_equals 0 lk_mysql_option_bytes 0K
assert_output_equals 1073741824 lk_mysql_option_bytes 1g
assert_output_equals 1572864000 lk_mysql_option_bytes 1500M
assert_output_equals 4398046511104 lk_mysql_option_bytes 4T
assert_output_equals 2305843009213693952 lk_mysql_option_bytes 2E
