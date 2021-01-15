function print_server() {
    if (!server_printed)
        print NTP_SERVER
    server_found = 0
    server_printed = 1
    previous = ""
}

function print_previous() {
    if (!previous)
        return
    print previous
    previous = ""
}

$1 ~ "^#?(server|pool)$" {
    server_found = 1
    next
}

$0 ~ "^# " {
    # Collect comments to replace along with adjacent server/pool definitions
    previous = (previous ? previous "\n" : "") $0
    next
}

server_found {
    print_server()
}

{
    print_previous()
    print
}

END {
    if (!server_found)
        print_previous()
    print_server()
}
