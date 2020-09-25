BEGIN {
    log_time="[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2}( [-+][0-9]{4})?"
    FS="^(" log_time " )?(  ){,3}"
}
$2 ~ "^(==> |   -> )?Environment:$" {
    env_started = 1
    next
}
env_started && $0 ~ ("^(" log_time " )?(  ){1,3}[a-zA-Z_][a-zA-Z0-9_]*=") {
    print $2;
    next
}
env_started {
    exit
}
