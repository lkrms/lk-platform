# References:
# - https://github.com/Atoptool/atop/blob/master/parseable.c

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

function min(val1, val2) {
    return val1 < val2 ? val1 : val2;
}

function set_max(arr, i, val) {
    arr[i] = (arr[i] > val) ? arr[i] : val
}

function quote(str, _q, _q_count, _arr, _i, _out) {
    # \47 = single quote
    _q = "\47"
    _q_count = split(str, _arr, _q)
    for (_i in _arr) {
        _out = _out _q _arr[_i] _q (_i < _q_count ? "\\" _q : "")
    }
    return _out
}

function readable_kib(kib, width, _i) {
    _i = 1
    while (kib > 1024 && u[_i]) {
        kib /= 1024
        _i++
    }
    return sprintf("%" width ".1f%s", kib, u[_i])
}

function readable_max_kib(kib, max, suppress_kib, _kib, _max) {
    _kib = readable_kib(kib)
    _max = readable_kib(max)
    return (suppress_kib ? "" : _kib) (_kib == _max ? "" : " [^" _max "]")
}

function readable_percent_kib(kib, total) {
    if (total)
        return readable_kib(total) " total, " int(100 * kib / total) "% used"
}

function readable_max(val, max, suppress_val) {
    return (suppress_val ? "" : val) (val == max ? "" : " [^" max "]")
}

function between_brackets() {
    if (match($0, /\(.*\)/)) {
        bb = substr($0, RSTART + 1, RLENGTH - 2)
        $0 = substr($0, 1, RSTART) substr($0, RSTART + RLENGTH - 1)
        return 1
    }
}

function load() {
    f_label     = $1    # label (the name of the label)
    f_host      = $2    # host (the name of this machine)
    f_epoch     = $3    # epoch (the time of this interval as number of seconds since 1-1-1970)
    f_date      = $4    # date (date of this interval in format YYYY/MM/DD)
    f_time      = $5    # time (time of this interval in format HH:MM:SS)
    f_interval  = $6    # interval (number of seconds elapsed for this interval)
    if (!interval_time) {
        interval = f_interval
        interval_time = f_date " " f_time
    }
}

function load_low_watermark() {
    mem_low_watermark = LOW * f_pagesize / 1024
}

function load_CPL() {
    load()
    f_nrcpu = f_lavg1 = f_lavg5 = f_lavg15 = f_csw = f_devint = 0
    if (NF >= 12) {
        f_nrcpu         = $7            # number of processors
        f_lavg1         = $8            # load average for last minute
        f_lavg5         = $9            # load average for last five minutes
        f_lavg15        = $10           # load average for last fifteen minutes
        f_csw           = $11           # number of context-switches
        f_devint        = $12           # number of device interrupts
        return 1
    }
}

function load_MEM(_kb, _hkb) {
    load()
    f_pagesize = f_physmem = f_freemem = f_cachemem = f_buffermem = \
        f_slabmem = f_cachedrt = f_slabreclaim = f_vmwballoon = f_shmem = \
        f_shmrss = f_shmswp = f_hugepagesz = f_tothugepage = f_freehugepage = \
        f_zfsarcsize = 0
    if (NF >= 21) {
        _kb             = $7 / 1024
        _hkb            = $19 / 1024
        f_pagesize      = $7            # page size for this machine (in bytes)
        f_physmem       = $8 * _kb      # {MemTotal} size of physical memory (pages)
        f_freemem       = $9 * _kb      # {MemFree} size of free memory (pages)
        f_cachemem      = $10 * _kb     # {Cached} size of page cache (pages)
        f_buffermem     = $11 * _kb     # {Buffers} size of buffer cache (pages)
        f_slabmem       = $12 * _kb     # {Slab} size of slab (pages)
        f_cachedrt      = $13 * _kb     # {Dirty} dirty pages in cache (pages)
        f_slabreclaim   = $14 * _kb     # {SReclaimable} reclaimable part of slab (pages)
        f_vmwballoon    = $15 * _kb     # total size of vmware's balloon pages (pages)
        f_shmem         = $16 * _kb     # {Shmem} total size of shared memory (pages)
        f_shmrss        = $17 * _kb     # size of resident shared memory (pages)
        f_shmswp        = $18 * _kb     # size of swapped shared memory (pages)
        f_hugepagesz    = $19           # huge page size (in bytes)
        f_tothugepage   = $20 * _hkb    # total size of huge pages (huge pages)
        f_freehugepage  = $21 * _hkb    # size of free huge pages (huge pages)
        f_zfsarcsize    = $22 * _kb     # size of ARC (cache) of ZFSonlinux (pages)
        load_low_watermark()
        return 1
    }
}

function load_SWP(_kb) {
    load()
    f_pagesize = f_totswap = f_freeswap = f_swapcached = \
        f_committed = f_commitlim = 0
    if (NF >= 12) {
        _kb             = $7 / 1024
        f_pagesize      = $7            # page size for this machine (in bytes)
        f_totswap       = $8 * _kb      # size of swap (pages)
        f_freeswap      = $9 * _kb      # size of free swap (pages)
        f_swapcached    = $10 * _kb     # size of swap cache (pages)
        f_committed     = $11 * _kb     # size of committed space (pages)
        f_commitlim     = $12 * _kb     # limit for committed space (pages)
        load_low_watermark()
        return 1
    }
}

function load_PAG() {
    load()
    f_pagesize = f_pgscans = f_allocstall = f_swins = f_swouts = 0
    if (NF >= 12) {
        f_pagesize      = $7            # page size for this machine (in bytes)
        f_pgscans       = $8            # number of page scans
        f_allocstall    = $9            # number of allocstalls
        f_swins         = $11           # number of swapins
        f_swouts        = $12           # number of swapouts
        load_low_watermark()
        return 1
    }
}

function load_PRM() {
    load()
    f_name = f_state = f_isproc = ""
    f_pid = f_pagesize = f_vmem = f_rmem = f_vexec = f_vgrow = f_rgrow = \
        f_minflt = f_majflt = f_vlibs = f_vdata = f_vstack = f_vswap = \
        f_tgid = f_pmem = f_vlock = 0
    if (between_brackets() && NF >= 24) {
        f_pid           = $7            # PID
        f_name          = bb            # name (between brackets)
        f_state         = $9            # state
        f_pagesize      = $10           # page size for this machine (in bytes)
        f_vmem          = $11           # virtual memory size (Kbytes)
        f_rmem          = $12           # resident memory size (Kbytes)
        f_vexec         = $13           # shared text memory size (Kbytes)
        f_vgrow         = $14           # virtual memory growth (Kbytes)
        f_rgrow         = $15           # resident memory growth (Kbytes)
        f_minflt        = $16           # number of minor page faults
        f_majflt        = $17           # number of major page faults
        f_vlibs         = $18           # virtual library exec size (Kbytes)
        f_vdata         = $19           # virtual data size (Kbytes)
        f_vstack        = $20           # virtual stack size (Kbytes)
        f_vswap         = $21           # swap space used (Kbytes)
        f_tgid          = $22           # TGID (group number of related tasks/threads)
        f_isproc        = $23           # is_process (y/n)
        f_pmem          = $24           # proportional set size (Kbytes) if in 'R' option is specified
        f_vlock         = $25           # virtually locked memory space (Kbytes)
        return 1
    }
}

$1 == "CPL" {
    if (load_CPL()) {
        cpu_count = f_nrcpu
        cpu_load[1] = f_lavg1
        cpu_load[2] = f_lavg5
        cpu_load[3] = f_lavg15
    }
}

$1 == "MEM" {
    if (load_MEM()) {
        mem_physical = f_physmem
        mem_free = f_freemem
        mem_used = mem_physical - mem_free
        mem_available = mem_free - mem_low_watermark + \
            (f_cachemem - min(f_cachemem / 2, mem_low_watermark)) + \
            (f_slabreclaim - min(f_slabreclaim / 2, mem_low_watermark)) + \
            f_buffermem - f_shmem
    }
}

$1 == "SWP" {
    if (load_SWP()) {
        swap_size = f_totswap
        swap_free = f_freeswap
        swap_used = swap_size - swap_free
    }
}

$1 == "PAG" {
    if (load_PAG()) {
        mem_page_scans = f_pgscans
        mem_page_stalls = f_allocstall
        swap_si = f_swins
        swap_so = f_swouts
    }
}

$1 == "PRM" {
    if (load_PRM() && f_pmem) {
        pss[f_name] += f_pmem
        count[f_name] += 1
        set_max(maxpss, f_name, f_pmem)
    }
}

$1 == "SEP" {
    run += 1
    pss_grand_total = 0
    for (program in pss) {
        pss_total = pss[program]
        pss_count = count[program]
        pss_max = maxpss[program]
        pss_average = pss_total / pss_count
        pss_grand_total += pss_total
        set_max(max_pss_total, program, pss_total)
        set_max(max_pss_count, program, pss_count)
        set_max(max_pss_max, program, pss_max)
        set_max(max_pss_average, program, pss_average)
        print readable_kib(pss_total, 10),
            program readable_max_kib(pss_total, max_pss_total[program], 1),
            "(" (pss_count + max_pss_count[program] == 2 ? "" :
                    readable_max(pss_count, max_pss_count[program]) ", ") \
                "avg " readable_max_kib(pss_average, max_pss_average[program]) \
                ", max " readable_max_kib(pss_max, max_pss_max[program]) ")" \
                > TEMP
        delete pss[program]
        delete count[program]
        delete maxpss[program]
    }
    close(TEMP)
    system("sort -h " quote(TEMP))
    set_max(max_pss_grand_total, 0, pss_grand_total)
    print "-----------"
    print readable_kib(pss_grand_total, 10), "total memory used",
        (run < 2 ? "at " : "in " readable_seconds(interval) " interval to ") \
        interval_time \
        readable_max_kib(pss_grand_total, max_pss_grand_total[0], 1)
    print readable_kib(mem_available, 10), "available", \
        "(" readable_percent_kib(mem_used, mem_physical) (swap_size ?
            "; swap: " readable_percent_kib(swap_used, swap_size) (run < 2 ?
            "" : ", " swap_si " in, " swap_so " out") : "; no swap") ")"
    print sprintf("%10.1f%%", 100 * cpu_load[3] / cpu_count), "load average", \
        sprintf("(%.2f, %.2f, %.2f; cpus: %s)", \
            cpu_load[1], cpu_load[2], cpu_load[3], cpu_count)
    print "==========="
    interval = 0
    interval_time = ""
}
