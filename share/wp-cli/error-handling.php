<?php

function lk_ini_set_error_reporting()
{
    ini_set("error_reporting", E_ALL & ~E_WARNING & ~E_NOTICE & ~E_USER_WARNING & ~E_USER_NOTICE & ~E_STRICT & ~E_DEPRECATED & ~E_USER_DEPRECATED);
    ini_set("display_errors", "stderr");
    ini_set("log_errors", false);
}

lk_ini_set_error_reporting();

// Prevent WordPress applying its preferred `error_reporting` value, and work
// around poorly-behaved plugins that don't restore the configured value
$GLOBALS['wp_filter'] = [
    'enable_wp_debug_mode_checks' => [
        10 => [
            [
                'function'      => function () { return false; },
                'accepted_args' => 0,
            ],
        ],
    ],
    'plugin_loaded' => [
        10          => [
            [
                'function'      => 'lk_ini_set_error_reporting',
                'accepted_args' => 0,
            ],
        ],
    ],
];
