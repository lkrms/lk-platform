#!/bin/bash

set -euo pipefail

((EUID == 0)) || {
    echo "${0##*/}: not running as root" >&2
    exit 1
}

modprobe msr

msr=0x1fc
current=0x$(rdmsr "$msr")
current=$((current))
expected=$((current & 0xfffffe))
printf '%s MSR: 0x%x\n' \
    Current "$current" \
    Expected "$expected"

if ((current != expected)); then
    echo "==> Disabling BD PROCHOT"
    wrmsr "$msr" "$(printf '0x%x\n' "$expected")"
else
    echo "==> No action required"
fi
