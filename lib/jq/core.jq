def to_array:
  if type == "array" then .
  elif . == null then []
  else [.] end;

def to_bool:
  if . == true then true else false end;

def _to_sh:
  if type == "array" then "(\(@sh))"
  elif type == "boolean" then if . then "1" else "0" end
  else @sh end;

def to_sh(prefix):
  prefix as $prefix |
    to_entries[] |
    "\($prefix)\(.key | ascii_upcase)=\(.value | _to_sh)";

def to_sh:
  to_sh("");

def counts:
  . as $a | unique | map([., . as $v | [$a[] | select(. == $v)] | length]);
