#!/usr/bin/env bash

lk_require mysql

# lk_mysql_escape
assert_output_equals "''" lk_mysql_escape
assert_output_equals "'MariaDB\\'s new features'" lk_mysql_escape "MariaDB's new features"
assert_output_equals "'\"Double\"'" lk_mysql_escape '"Double"'
assert_output_equals "'EOF on Windows: \\Z'" lk_mysql_escape $'EOF on Windows: \x1a'

# lk_mysql_escape_like
assert_output_equals '' lk_mysql_escape_like
assert_output_equals "MariaDB\\'s new features" lk_mysql_escape_like "MariaDB's new features"
assert_output_equals '"double\_quote"' lk_mysql_escape_like '"double_quote"'
assert_output_equals 'EOF on \%os\%: \_\_\Z\_\_' lk_mysql_escape_like $'EOF on %os%: __\x1a__'

# lk_mysql_escape_identifier
assert_output_equals '``' lk_mysql_escape_identifier
assert_output_equals "\`MariaDB's new features\`" lk_mysql_escape_identifier "MariaDB's new features"
assert_output_equals '```back_q``s are 100% allowed`' lk_mysql_escape_identifier '`back_q`s are 100% allowed'
assert_output_equals '`desc`' lk_mysql_escape_identifier desc
assert_output_equals '`long_desc`' lk_mysql_escape_identifier long_desc

# lk_mysql_option_escape
assert_output_equals '""' lk_mysql_option_escape
assert_output_equals '"\"Double\""' lk_mysql_option_escape '"Double"'
assert_output_equals '"With\r\nCRLF\r\nand\thorizontal whitespace.\b\r\n"' \
    lk_mysql_option_escape $'With\r\nCRLF\r\nand\thorizontal whitespace.\b\r\n'
