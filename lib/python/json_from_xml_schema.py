#!/usr/bin/env python

# Notes:
# - Used by lk_json_from_xml_schema in core.sh
# - Not intended to be invoked directly

import xmlschema
import sys

schema = None if len(sys.argv) < 2 else sys.argv[1]
xml = sys.stdin.read() if len(sys.argv) < 3 else sys.argv[2]
converter = xmlschema.XMLSchemaConverter(
    preserve_root=True,
    strip_namespaces=True
)
print(xmlschema.to_json(xml, schema=schema, converter=converter))
