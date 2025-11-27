#!/usr/bin/env bash

function __usage() {
    cat <<EOF
Analyse Apache logs on a hosting server, reporting request count and bytes sent
by IP address after retrieving ASN, country and/or city data from one or more
MaxMind GeoIP2 databases.

Usage:
  ${0##*/} [USER@]<SOURCE>[:PORT] <DB_PATH>... [<SOURCE_LOG_PATH>...]

Each <DB_PATH> must resolve to a local file with the \`mmdb\` extension.

If given, each <SOURCE_LOG_PATH> must resolve to a readable \`access.log\` file
on the hosting server, otherwise every available \`access.log\` file in
\`~/log\` on the remote system is included in the analysis.
EOF
}

lk_bin_depth=2 . lk-bash-load.sh || exit
lk_require provision

{
    (($#)) || lk_usage

    SOURCE=$1
    shift

    DB=()
    while [[ -f ${1-} ]]; do
        FILE=$(realpath "$1")
        [[ $FILE == *.mmdb ]] || break
        DB[${#DB[@]}]=$FILE
        shift
    done
    [[ ${DB+1} ]] || lk_usage -e "invalid or missing DB_PATH"

    function summarise_access_log() {
        shopt -s nullglob extglob
        (($#)) || set -- ~/log/access.log{,.+([0-9]),.+([0-9]).gz}
        while (($#)); do
            [[ -e $1 ]] || continue
            if [[ $1 == *.gz ]]; then
                zcat "$1"
            else
                cat "$1"
            fi
            shift
        done | awk '
{
  request_count[$1]++
  bytes_sent[$1] += $10
  last_request_time[$1] = $4 " " $5
  if (! first_request_time[$1]) {
    first_request_time[$1] = last_request_time[$1]
  }
  last_line[$1] = $0
}

END {
  OFS = "\t"
  for (ip in request_count) {
    split(last_line[ip], parts, /"/)
    last_user_agent = parts[6]
    print request_count[ip], bytes_sent[ip], ip, first_request_time[ip], last_request_time[ip], last_user_agent
  }
}' | gzip
    }

    lk_mktemp_with SUMMARY
    lk_tty_print "Retrieving access.log summary"
    lk_ssh_run_on_host "$SOURCE" summarise_access_log "$@" | gunzip | sort -n -k1,1 >"$SUMMARY"

    lk_mktemp_with DATA
    lk_tty_print "Extracting IP address data"
    awk '{ print $3 }' "$SUMMARY" |
        xargs mmdbinspect "${DB[@]/#/-db=}" -jsonl |
        jq -rs '
reduce(.[] | {
    (.requested_lookup):
        if .record.autonomous_system_number != null then
            {
                "as_number": .record.autonomous_system_number,
                "as_organization": .record.autonomous_system_organization,
                "network": .network
            }
        else
            {
                "country": .record.country.names.en
            } + if .record.city.names.en != null then
                {
                    "city": .record.city.names.en
                }
            else
                {}
            end
        end
}) as $record ({}; . * $record) |
    to_entries[] |
    [
        .key,
        .value.country // "-",
        .value.city // "-",
        .value.network // "-",
        .value.as_number // "-",
        .value.as_organization // "-"
    ] |
    @tsv' >"$DATA"

    BACKUP=~/.lk-platform/cache/log/${0##*/}-$(lk_date_ymdhms).gz
    install -d -m 00700 "${BACKUP%/*}"
    lk_tty_print "Merging data"
    awk '
FILENAME == ARGV[1] {
  ip = $1
  sub(/^[^\t]+/, "", $0)
  data[ip] = $0
  next
}

{
  print $0 data[$3]
}
' "$DATA" "$SUMMARY" | tee >(gzip >"$BACKUP")
    lk_tty_detail "Output also written to" "$BACKUP"

    exit
}
