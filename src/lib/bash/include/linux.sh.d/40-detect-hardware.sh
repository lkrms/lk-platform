#!/usr/bin/env bash

function lk_system_has_bluetooth() {
    awk -v module=bluetooth '$1==module{f=1;exit}END{exit 1-f}' /proc/modules
}

function lk_system_has_intel_cpu() {
    grep -Eq '\<GenuineIntel\>' /proc/cpuinfo 2>/dev/null
}

function lk_system_has_amd_cpu() {
    grep -Eq '\<AuthenticAMD\>' /proc/cpuinfo 2>/dev/null
}

function lk_system_is_thinkpad() {
    ! lk_system_is_vm &&
        grep -iq ThinkPad /sys/devices/virtual/dmi/id/product_family 2>/dev/null
}

function lk_system_is_star_labs() {
    ! lk_system_is_vm &&
        grep -Fxiq 'Star Labs' /sys/devices/virtual/dmi/id/*_vendor 2>/dev/null
}
