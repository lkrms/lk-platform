#!/usr/bin/env python3

"""
Sort a property list or one of its nested lists.

Usage:
  plist_sort.py [in_file]
  plist_sort.py <in_file> <out_file> [to_sort [sort_by]]

`in_file` and `out_file` default to stdin and stdout respectively, including
when they are set to '-'. Use '.' between parent and child properties in
`to_sort` and `sort_by` if needed.

Example:
  # Sort Dash docsets alphabetically
  plist_sort.py com.kapeli.dashdoc.plist - docsets docsetName
"""

import plistlib
import sys
from types import BuiltinMethodType


def has_builtin_method(obj, name):
    try:
        return isinstance(getattr(obj, name), BuiltinMethodType)
    except BaseException:
        return False


def dict_get(dct, path):
    path = path.split(".")
    for key in path:
        if key:
            dct = dct[key]
    return dct


def dict_set(dct, path, val):
    path = path.split(".")
    for key in path[:-1]:
        if key:
            dct = dct[key]
    if path:
        key = path[-1]
        if key:
            dct[key] = val
            return
    # We should only end up here if path is empty or "."
    if val is not dct:
        dct.clear()
        dct.update(val)


def maybe_lower(val):
    if isinstance(val, str):
        return val.lower()
    else:
        return val


def plist_sort(in_file, out_file, sort, by):
    in_file = sys.stdin.buffer if in_file == "-" else open(in_file, "rb")
    plist = plistlib.loads(in_file.read())
    in_file.close()
    data = dict_get(plist, sort)
    if isinstance(data, dict):
        data = dict(sorted(data.items(), key=lambda item: maybe_lower(item[0])))
    else:
        if has_builtin_method(data, "copy"):
            data = data.copy()
        data = sorted(data, key=lambda item: maybe_lower(dict_get(item, by)))
    dict_set(plist, sort, data)
    format = (
        plistlib.PlistFormat.FMT_XML
        if out_file == "-"
        else plistlib.PlistFormat.FMT_BINARY
    )
    out_file = sys.stdout.buffer if out_file == "-" else open(out_file, "wb")
    plistlib.dump(plist, out_file, fmt=format, sort_keys=False)
    out_file.close()


if __name__ == "__main__":
    in_file = "-" if len(sys.argv) < 2 else sys.argv[1]
    out_file = "-" if len(sys.argv) < 3 else sys.argv[2]
    sort = sys.argv[3] if len(sys.argv) > 3 else ""
    by = sys.argv[4] if len(sys.argv) > 4 else ""

    plist_sort(in_file, out_file, sort, by)
