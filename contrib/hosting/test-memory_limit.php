<?php

function to_bytes($ini_value) {

    if (preg_match('/^(.+?)([KMG]?)$/', strtoupper($ini_value), $match) && is_numeric($match[1])) {

        $power = [
            ''  => 0,
            'K' => 1,
            'M' => 2,
            'G' => 3,
        ];

        return $match[1] * (1024**$power[$match[2]]);

    } else {

        return 0;

    }

}

$memory_limit = to_bytes(ini_get('memory_limit'));
printf("memory_limit: %d bytes\n", $memory_limit);

if ($memory_limit > 0) {

    $bytes = $memory_limit / 5;
    $string = [];

    while (true) {

        $usage = memory_get_usage(true);

        if ($usage + $bytes > $memory_limit) {

            $bytes = $memory_limit - $usage - 32;

        }

        $bytes = $bytes < 0 ? 0 : $bytes;
        printf("allocating %d bytes (current usage: %d bytes)\n", $bytes, $usage);

        if ( ! $bytes) {

            break;

        }

        $string[] = str_repeat('0', $bytes);

    }

}

