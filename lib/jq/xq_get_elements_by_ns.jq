def entry_is_xmlns:
    .key | test("^@xmlns(:|$)");

def ns_declaration_entries:
    to_entries[] | select(entry_is_xmlns and (.value == $ns));

def in_ns($prefix):
    .["#name"] |
        if $prefix == "" then contains(":") | not
        else startswith($prefix + ":")
        end;

# Add each element's name to its JSON representation
[ walk(
    if type == "object" then with_entries(
        if (.value | type != "object") and (entry_is_xmlns | not) then
            .value |= { "$": . }
        else . end | if .value | type == "object" then
            .key as $name | .value["#name"] = $name
        else . end
    ) else . end
) |
.. |
# Find each element where $ns is declared
select(type == "object" and (ns_declaration_entries | length > 0)) |
# Store its prefix (if any)
(ns_declaration_entries.key | split(":")[1]) as $prefix |
# Find each element where $ns is used (without descending into its children)
recurse(if in_ns($prefix) then null else .[] end; type == "object") |
select(in_ns($prefix)) |
# Restore root element
{ key: .["#name"], value: . } ] |
from_entries |
walk(
    if type == "object" then
        [ to_entries[] |
            # Remove xmlns attributes and element names
            select((entry_is_xmlns or .key == "#name") | not) ] |
            map(
                # Remove namespace prefixes
                .key |= (sub("^[^:]+:"; "") |
                    # Replace xmltodict's "#text" keys with "$"
                    sub("^#text$"; "$")) |
                # Flatten objects only created to store element names
                if (.value | type == "object") and
                    (.value | length == 1) and
                    (.value | has("$")) then
                    .value |= .["$"]
                else . end
            ) | from_entries
    elif type == "string" then
        # Perform basic type conversion
        if . == "true" then true
        elif . == "false" then false
        else (tonumber)? // .
        end
    else .
    end
)
