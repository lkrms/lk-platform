import "regex" as $regex;

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

def to_sh($prefix):
  to_entries[] |
    "\($prefix)\(.key | ascii_upcase)=\(.value | _to_sh)";

def to_sh:
  to_sh("");

def in_arr($arr):
  . as $v | $arr | index($v) != null;

def counts:
  . as $a | unique | map([., . as $v | [$a[] | select(. == $v)] | length]);

def regex:
  $regex::regex[];

def regex($re):
  $regex::regex[][$re];
