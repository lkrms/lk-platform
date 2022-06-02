#!/bin/awk -f

# Print a list of changes to make lines in <file1> identical to <file2>
#
# Usage: table-diff.awk <exclude_list> <match_list> <file1> <file2>
#
# TL;DR: a field-friendly `diff` that preserves ignored fields (columns) and
# minimises inserts and deletes by updating existing records (lines) if
# possible. May contain traces of `cut` and `comm`.
#
# Compares <file1> and <file2> line-by-line, ignoring fields in <exclude_list>
# and detecting records to update by comparing fields in <match_list>, before
# printing updates ("="), deletions ("-") and additions ("+") as follows:
#
#     = <line from file2, with excluded fields from file1>
#     - <line from file1>
#     + <line from file2, with excluded fields empty>
#
# <exclude_list> and <match_list> must be either
# - the empty string (""), or
# - a comma-delimited list of fields (1-based, e.g. "1" or "2,5")
#
# The order of input and output lines is not specified.

function split_list(value, list, _a, _i) {
  split(value, _a, /,/)
  for (_i in _a) {
    list[_a[_i]] = 1
  }
}

BEGIN {
  STDERR  = "/dev/stderr"
  list_regex = "^([1-9][0-9]*(,[1-9][0-9]*)*)?$"
  if (ARGC < 5 || ARGV[1] !~ list_regex || ARGV[2] !~ list_regex) {
    printf("Usage: %s <exclude_field[,...]> <match_field[,...]> <file1> <file2>\n",
      "table-diff.awk") > STDERR
    exit 1
  }

  exclude_arg = ARGV[1]
  match_arg = ARGV[2]
  ARGV[1] = ARGV[2] = ""

  OFS = FS = "\t"
  field_glue = field_glue ? field_glue : RS

  # These are the next-best thing to awk array declarations (needed to prevent
  # runtime errors when uninitialised variables are used as arrays)
  split("", exclude_list)
  split("", include_list)
  split("", include_index)
  split("", include_index_c)
  split("", match_list)
  split("", match_index)
  split("", match_index_c)

  split_list(exclude_arg, exclude_list)
  split_list(match_arg, match_list)
}

function implode_fields(fields, _f, _i, _s) {
  for (_f in fields) {
    _s = (_i++ ? _s field_glue : "") $_f
  }
  return _s
}

function invert_exclude_list(_i) {
  for (_i = 1; _i <= NF; _i++) {
    if (!(_i in exclude_list)) {
      include_list[_i] = 1
    }
  }
  exclude_list_inverted = 1
}

function add_to_index(fields, index_arr, index_arr_c, _key){
  _key = implode_fields(fields)
  index_arr[_key][index_arr_c[_key]++] = FNR
}

function get_from_index(fields, index_arr, index_arr_c, arr, _key, _i, _NR) {
  for (_i in arr) {
    delete arr[_i]
  }
  _key = implode_fields(fields)
  while (_key in index_arr_c && (_i = --index_arr_c[_key]) > -1) {
    _NR = index_arr[_key][_i]
    if (_NR in file1_line) {
      arr["line"] = file1_line[_NR]
      delete file1_line[_NR]
      return 1
    }
  }
  return 0
}

function save_fields_to(fields, arr, _f) {
  for (_f in fields) {
    arr[_f] = $_f
  }
}

function set_fields_to(fields, value, _f) {
  for (_f in fields) {
    $_f = value
  }
}

function set_fields_from(fields, source, _f) {
  for (_f in fields) {
    $_f = source[_f]
  }
}

FNR == NR {
  file1_line[FNR] = $0
  if (match_arg) {
    add_to_index(match_list, match_index, match_index_c)
  }
  if (exclude_arg) {
    set_fields_to(exclude_list, "")
  }
  if (!exclude_list_inverted) {
    invert_exclude_list()
  }
  add_to_index(include_list, include_index, include_index_c)
  next
}

{
  if (!exclude_list_inverted) {
    invert_exclude_list()
  }
  # 1. Discard an identical record
  if (get_from_index(include_list, include_index, include_index_c)) {
    next
  }
  # 2. Update a matching record
  if (match_arg) {
    if (get_from_index(match_list, match_index, match_index_c, found)) {
      # "= <line from file2, with excluded fields from file1>"
      if (exclude_arg) {
        current_line = $0
        $0 = found["line"]
        save_fields_to(exclude_list, previous_line)
        $0 = current_line
        set_fields_from(exclude_list, previous_line)
      }
      print "=", $0
      next
    }
  }
  # 3. "+ <line from file2, with excluded fields empty>"
  if (exclude_arg) {
    set_fields_to(exclude_list, "")
  }
  print "+", $0
  next
}

END {
  # 4. "- <line from file1>"
  for (i in file1_line) {
    print "-", file1_line[i]
    delete file1_line[i]
  }
}
