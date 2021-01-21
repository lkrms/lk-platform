BEGIN {
    u[1] = "K"
    u[2] = "M"
    u[3] = "G"
    u[4] = "T"
    u[5] = "P"
    u[6] = "E"
    u[7] = "Z"
    u[8] = "Y"
}

function _readable_unit(val, unit, _) {
    val = int(val)
    if (_["i"] < 2 && (val || (! _["i"] && unit ~ _["r"]))) {
        if (_["i"])
            _["s"] = _["s"] ", "
        _["s"] = _["s"] val unit
        _["i"]++
    }
}

function readable_seconds(s, _) {
    _["r"] = "^s"
    _readable_unit(s / 86400, "d", _)
    _readable_unit((s % 86400) / 3600, "h", _)
    _readable_unit((s % 3600) / 60, "m", _)
    _readable_unit(s % 60, "s", _)
    return _["s"]
}

function max(arr, i, val) {
    arr[i] = (arr[i] > val) ? arr[i] : val
}

function quote(str, q, q_count, arr, i, outstr) {
    # \47 = single quote
    q = "\47"
    q_count = split(str, arr, q)
    for (i in arr) {
        outstr = outstr q arr[i] q (i < q_count ? "\\" q : "")
    }
    return outstr
}

function readable_kib(kib, width, i) {
    i = 1
    while (kib > 1024 && u[i]) {
        kib /= 1024
        i++
    }
    return sprintf("%" width ".1f%s", kib, u[i])
}

/^PRM[[:blank:]]/ {
    if (match($0, /\(.*\)/)) {
        program = substr($0, RSTART + 1, RLENGTH - 2)
        $0 = substr($0, 1, RSTART) substr($0, RSTART + RLENGTH - 1)
        if ($24) {
            pss[program] += $24
            count[program] += 1
            max(max_pss, program, $24)
            interval = $6
            interval_time = $4 " " $5
        }
    }
}

/^SEP([[:blank:]]|$)/ {
    run += 1
    used = 0
    for (program in pss) {
        if (pss[program]) {
            used += pss[program]
            avg = pss[program] / count[program]
            max(max_total, program, pss[program])
            max(max_count, program, count[program])
            max(max_avg, program, avg)
            max(max_pss2, program, max_pss[program])
            _pss = readable_kib(pss[program])
            _max_total = readable_kib(max_total[program])
            _avg = readable_kib(avg)
            _max_avg = readable_kib(max_avg[program])
            _max_pss = readable_kib(max_pss[program])
            _max_pss2 = readable_kib(max_pss2[program])
            print readable_kib(pss[program], 10),
                program, \
                (_max_total == _pss ? "" : ("[^" _max_total "] ")) \
                "(" (count[program] == 1 && max_count[program] == 1 ? "" :
                        (count[program] \
                            (count[program] == max_count[program] ? "" :
                                (" [^" max_count[program] "]")) \
                            ", ")) \
                    "avg " _avg \
                    (_max_avg == _avg ? "" : (" [^" _max_avg "]")) \
                    ", max " _max_pss \
                    (_max_pss2 == _max_pss ? "" : (" [^" _max_pss2 "]")) ")" \
                    > TEMP
        }
        delete pss[program]
        delete count[program]
        delete max_pss[program]
    }
    close(TEMP)
    system("sort -h " quote(TEMP))
    max(max_used, 0, used)
    _used = readable_kib(used)
    _max_used = readable_kib(max_used[0])
    print "-----------"
    print readable_kib(used, 10), "total memory used " (run < 2 ? "at " :
        "in " readable_seconds(interval) " interval to ") interval_time \
        (_max_used == _used ? "" : (" [^" _max_used "]"))
    print "==========="
}
