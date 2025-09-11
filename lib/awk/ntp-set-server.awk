server && $1 ~ /^#?(server|pool)$/ {
  server_found = 1
  next
}

interfaces && $1 ~ /^#?(interface|nic)$/ {
  next
}

/^# / {
  # Collect comments to replace along with adjacent server/pool definitions
  previous = (previous ? previous "\n" : "") $0
  next
}

{
  if (server_found) {
    print_server()
  } else {
    print_previous()
  }
  print
}

END {
  if (server_found) {
    print_server()
  } else {
    print_previous()
  }
  if (interfaces) {
    # "all" does not include localhost or wildcard addresses
    print "interface", "ignore", "all"
    split(interfaces, iface, ",")
    for (i in iface) {
      print "interface", "listen", iface[i]
    }
  }
}

function print_previous()
{
  if (previous) {
    print previous
    previous = ""
  }
}

function print_server()
{
  if (! server_printed) {
    print "server", server, "iburst"
    server_printed = 1
  }
  server_found = 0
  previous = ""
}
