<?php

function ip_addr()
{
    $sh =
<<<'SH'
{ /usr/bin/ip addr || /sbin/ip addr || /sbin/ifconfig; } 2>/dev/null |
    awk '
$1 ~ /^inet6?$/ {
  sub(FS "addr:", FS)
  sub("[/%].*", "", $2)
  if ($2 !~ /^(127\.|::1$)/) {
    print $2
    i++
  } }
END { exit (i == 0) }'
SH;

    exec($sh, $output, $result);

    if ($result)
    {
        throw new RuntimeException("Local IP address check failed");
    }

    return $output;
}

echo json_encode([
    "hostname" => gethostname(),
    "fqdn"     => gethostbyaddr('127.0.1.1'),
    "ip_addr"  => ip_addr(),
]);
