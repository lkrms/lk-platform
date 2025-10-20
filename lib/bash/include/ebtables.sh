#!/usr/bin/env bash

# lk_ebtables_save
#
# Normalise ebtables rules.
function lk_ebtables_save() {
    local t
    for t in filter nat broute; do
        lk_elevate ebtables-save -t "$t" || return
    done | sed -E '/^#/d'
}
