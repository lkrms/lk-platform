#!/bin/bash

function lk_systemctl_enable() {
    systemctl is-enabled --quiet "$@" ||
        sudo systemctl enable --now "$@"
}
