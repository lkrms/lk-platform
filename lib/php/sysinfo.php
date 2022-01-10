<?php

header("Content-Type: application/json; charset=UTF-8");

$hostname = gethostname();
$fqdn     = gethostbyaddr('127.0.1.1');
$alt_fqdn = [];
$ip_addr  = [];

if ($interfaces = net_get_interfaces())
{
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

                if (($host = gethostbyaddr($address)) &&
                    strpos($host, ".") !== false &&
                    !in_array($host, [$hostname, $fqdn]) && !in_array($host, $alt_fqdn))
                {
                    $alt_fqdn[] = $host;
                }
            }
        }
    }
}

echo json_encode([
    "hostname" => $hostname,
    "fqdn"     => $fqdn,
    "alt_fqdn" => $alt_fqdn,
    "ip_addr"  => $ip_addr,
]);
