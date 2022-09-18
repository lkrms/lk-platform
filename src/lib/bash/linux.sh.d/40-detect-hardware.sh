#!/bin/bash

function lk_system_has_intel_cpu() {
    ! lk_is_virtual &&
        grep -Eq '\<GenuineIntel\>' /proc/cpuinfo 2>/dev/null
}

function lk_system_has_amd_cpu() {
    ! lk_is_virtual &&
        grep -Eq '\<AuthenticAMD\>' /proc/cpuinfo 2>/dev/null
}

function lk_system_is_thinkpad() {
    ! lk_is_virtual &&
        grep -iq ThinkPad /sys/devices/virtual/dmi/id/product_family 2>/dev/null
}

function lk_system_is_star_labs() {
    ! lk_is_virtual &&
        grep -Fxiq 'Star Labs' /sys/devices/virtual/dmi/id/*_vendor 2>/dev/null
}
