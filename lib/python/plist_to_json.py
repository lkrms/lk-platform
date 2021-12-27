#!/usr/bin/env python3

import base64
import json
import plistlib
import sys


def get_serializable(obj):
    try:
        return {"@type": "plist",
                "__plist": plistlib.loads(obj)}
    except:
        pass

    try:
        return {"@type": "bytes",
                "__bytes": base64.b64encode(obj).decode('ascii')}
    except:
        raise TypeError('Unable to serialize object in plist')


def plist_to_json(in_file, out_file):
    plist = plistlib.loads(in_file.read())
    json.dump(plist, out_file, default=get_serializable, indent=2)


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] == "-":
        in_file = sys.stdin
    else:
        in_file = open(sys.argv[1], 'rb')

    if len(sys.argv) < 3 or sys.argv[2] == "-":
        out_file = sys.stdout
    else:
        out_file = open(sys.argv[2], 'w')

    plist_to_json(in_file, out_file)

    in_file.close()
    out_file.close()
