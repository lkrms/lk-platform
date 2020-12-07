function print_unit(val, unit) {
    val = int(val)
    if (printed)
        unit = substr(unit, 1, 1)
    else {
        if (val != 1)
            unit = unit "s"
        unit = " " unit
    }
    if (val || unit ~ /^ m/) {
        if (printed == 1)
            printf ", "
        printf val unit
        printed++
    }
}

{
    printed = 0
    print_unit($1 / 86400, "day")
    print_unit(($1 % 86400) / 3600, "hour")
    print_unit(($1 % 3600) / 60, "minute")
    printf "\n"
}
