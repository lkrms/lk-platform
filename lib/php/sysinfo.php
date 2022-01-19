<?php

header("Content-Type: application/json; charset=UTF-8");

$hostname = gethostname();
$fqdn     = gethostbyaddr('127.0.1.1');
$alt_fqdn = [];

if (function_exists("net_get_interfaces") && $interfaces = net_get_interfaces())
{
    $ip_addr = [];

    foreach ($interfaces as $interface)
    {
        foreach ($interface["unicast"] as $unicast)
        {
            if ($address = $unicast["address"] ?? null)
            {
                if (!preg_match('/^(127\.|::1$)/', $address))
                {
                    $ip_addr[] = $address;
                }
            }
        }
    }
}
else
{
    $sh =
<<<'SH'
{ /usr/bin/ip addr || /sbin/ip addr || /sbin/ifconfig; } 2>/dev/null | awk '
$1 ~ /^inet6?$/ {
  sub(FS "addr:", FS)
  sub("[/%].*", "", $2)
  if ($2 !~ /^(127\.|::1$)/) {
    print $2
    i++
  } }
END { exit (i == 0) }'
SH;
    exec($sh, $ip_addr, $result);

    if ($result)
    {
        throw new RuntimeException("Unable to retrieve local IP addresses");
    }
}

foreach ($ip_addr as $address)
{
    if (($host = gethostbyaddr($address)) &&
        strpos($host, ".") !== false &&
        !in_array($host, [$hostname, $fqdn]) && !in_array($host, $alt_fqdn))
    {
        $alt_fqdn[] = $host;
    }
}

echo json_encode([
    "hostname" => $hostname,
    "fqdn"     => $fqdn,
    "alt_fqdn" => $alt_fqdn,
    "ip_addr"  => $ip_addr,
]);
