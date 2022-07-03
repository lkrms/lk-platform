# Parse output from `ssh -G` and print a shell variable assignment for the
# (first) value of each parameter named on the command line, in addition to
# <user>, <hostname>, <port>, and <identityfile>.
#
# - Shell variable names are derived from a prefix (default: `SSH_HOST_`) and an
#   uppercase parameter name, e.g. `SSH_HOST_IDENTITYFILE`
# - Set awk variable `prefix` to override `SSH_HOST_`
function quote(str) {
  gsub(/'/, "'\\''", str)
  return "'" str "'"
}
BEGIN {
  prefix = prefix ? prefix : "SSH_HOST_"
  p["USER"] = 1
  p["HOSTNAME"] = 1
  p["PORT"] = 1
  p["IDENTITYFILE"] = 1
  for (i = 1; i < ARGC; i++) {
    p[toupper(ARGV[i])] = 1
    delete ARGV[i]
  }
}
{ _p = toupper($1) }
p[_p] {
  $1 = ""
  sub(/^[ \t]+/, "")
  print prefix _p "=" quote($0)
  delete p[_p]
}
END {
  for (_p in p) {
    if (p[_p]) {
      print prefix _p "="
    }
  }
}
