import "regex" as $regex;

def to_array:
  if type == "array" then .
  elif . == null then []
  else [.] end;

def to_bool:
  if type == "boolean" then .
  elif type == "number" then . != 0
  elif type == "string" then
    if test("^(y(es)?|1|true|on)$"; "i") then true
    elif test("^(no?|0|false|off)$"; "i") then false
    else . != "" end
  elif type == "array" then . != []
  elif type == "object" then . != {}
  elif . == null then null
  else false end;

def to_number:
  if type == "number" then .
  elif type == "boolean" then if . then 1 else 0 end
  elif type == "string" and . == "" then null
  elif . == null then null
  else . | tonumber end;

# Takes an array as input, evaluates `key` and `value` for each element, and
# outputs a lookup table as an array of [key, value] arrays that map each unique
# key to the last value it appeared with.
def to_hash(key; val):
  [ [ .[] | { (key): val } ] | add // [] | to_entries[] | [.key, .value] ];

def to_hash:
  to_hash(.[0]; .[1]);

def _to_sh:
  if type == "array" then "(\(@sh))"
  elif type == "object" then tostring | @sh
  elif type == "boolean" then if . then "1" else "0" end
  else @sh end;

def to_sh($prefix):
  to_entries[] |
    "\($prefix)\(.key | ascii_upcase)=\(.value | _to_sh)";

def to_sh:
  to_sh("");

def maybe_null:
  if . == "" then null else . end;

def maybe_split($str):
  if . == "" then null else split($str) end;

def in_arr($arr):
  . as $v | $arr | index($v) != null;

def counts:
  . as $a | unique | map([., . as $v | [$a[] | select(. == $v)] | length]);

def regex:
  $regex::regex[];

def regex($re):
  $regex::regex[][$re];

def cpanel_error:
  .metadata.reason? // .errors? // "cPanel request failed" | to_array |
    join("\n") + "\n" | halt_error;
