#!/usr/bin/env bash

# shellcheck disable=2329
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

Output (tab-delimited):
   1. IP address
   2. Request count
   3. Request count (%)
   4. Bytes sent
   5. Bytes sent (%)
   6. First request time (e.g. \`[03/Oct/2025:06:27:02 +1000]\`)
   7. Last request time
   8. User agent (extracted from last request per IP)
   9. Country (or \`-\`)
  10. City (or \`-\`)
  11. Network (or \`-\`)
  12. ASN (or \`-\`)
  13. Organisation (or \`-\`)

Output by network (tab-delimited, written to separate file):
   1. Network (or \`-\`)
   2. Request count
   3. Request count (%)
   4. Bytes sent
   5. Bytes sent (%)
   6. Country (or \`-\`)
   7. City (or \`-\`)
   8. ASN (or \`-\`)
   9. Organisation (or \`-\`)
  10. First request time (e.g. \`[03/Oct/2025:06:27:02 +1000]\`)
  11. Last request time (from last output entry per network)
  12. User agent (from last output entry per network)
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

    # shellcheck disable=2329
    function summarise_access_log() {
        shopt -s nullglob extglob
        (($#)) || set -- ~/log/access.log{,.+([0-9]),.+([0-9]).gz}
        local FILE
        while IFS= read -r FILE; do
            echo "Reading $FILE" >&2
            if [[ $FILE == *.gz ]]; then
                zcat "$FILE"
            else
                cat "$FILE"
            fi
        done < <(
            # Sort files by modified date
            if [[ $OSTYPE != darwin* ]]; then
                stat -c '%Y :%n' -- "$@"
            else
                stat -t '%s' -f '%Sm :%N' -- "$@"
            fi | sort -n | cut -d: -f2-
        ) | awk '
{
  if (! request_count[$1]) {
    total_ips++
    ips[total_ips] = $1
  }
  request_count[$1]++
  bytes_sent[$1] += $10
  last_request_time[$1] = $4 " " $5
  if (! first_request_time[$1]) {
    first_request_time[$1] = last_request_time[$1]
  }
  last_line[$1] = $0
  total_request_count++
  total_bytes_sent += $10
}

END {
  OFS = "\t"
  print "IP address", "Request count", "Request count (%)", "Bytes sent", "Bytes sent (%)", "First request time", "Last request time", "User agent (last seen)", "Country", "City", "Network", "ASN", "Organisation"
  for (i in ips) {
    ip = ips[i]
    split(last_line[ip], parts, /"/)
    last_user_agent = parts[6]
    print ip, request_count[ip], sprintf("%.6f", request_count[ip] * 100 / total_request_count), bytes_sent[ip], sprintf("%.6f", bytes_sent[ip] * 100 / total_bytes_sent), first_request_time[ip], last_request_time[ip], last_user_agent
  }
}
' | gzip
    }

    lk_mktemp_with SUMMARY
    lk_tty_print "Retrieving access.log summary"
    lk_ssh_run_on_host "$SOURCE" summarise_access_log "$@" | gunzip >"$SUMMARY"

    lk_mktemp_with DATA
    lk_tty_print "Extracting IP address data"
    awk 'NR > 1 { print $1 }' "$SUMMARY" |
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

    BACKUP=~/.lk-platform/cache/log/${0##*/}-$(lk_date_ymdhms).csv.gz
    install -d -m 00700 "${BACKUP%/*}"
    lk_tty_print "Merging data"
    awk '
FILENAME == ARGV[1] {
  ip = $1
  sub(/^[^\t]+/, "", $0)
  data[ip] = $0
  next
}

FNR == 1 {
  print
  next
}

{
  print $0 data[$1]
}
' "$DATA" "$SUMMARY" | tee >(gzip >"$BACKUP")
    lk_tty_detail "Output:" "$BACKUP"

    BACKUP2=${BACKUP%.csv.gz}-by-network.csv.gz
    cat "$BACKUP" | gunzip | awk '
BEGIN {
  FS = "\t"
}

NR > 1 {
  if (! request_count[$11]) {
    total_networks++
    networks[total_networks] = $11
  }
  request_count[$11]++
  bytes_sent[$11] += $4
  if (! first_request_time[$11]) {
    first_request_time[$11] = $6
    country[$11] = $9
    city[$11] = $10
    asn[$11] = $12
    organisation[$11] = $13
  }
  # TODO: convert to timestamp and keep most recent
  last_request_time[$11] = $7
  last_user_agent[$11] = $8
  total_request_count++
  total_bytes_sent += $4
}

END {
  OFS = "\t"
  print "Network", "Request count", "Request count (%)", "Bytes sent", "Bytes sent (%)", "Country", "City", "ASN", "Organisation", "First request time", "Last request time", "User agent (last seen)"
  for (i in networks) {
    n = networks[i]
    print n, request_count[n], sprintf("%.6f", request_count[n] * 100 / total_request_count), bytes_sent[n], sprintf("%.6f", bytes_sent[n] * 100 / total_bytes_sent), country[n], city[n], asn[n], organisation[n], first_request_time[n], last_request_time[n], last_user_agent[n]
  }
}
' | gzip >"$BACKUP2"
    lk_tty_detail "Output by network:" "$BACKUP2"

    exit
}
