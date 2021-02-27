#!/bin/sh

if [ "$(id -u)" -ne 0 ]; then
    umask 002
else
    umask 022
fi
