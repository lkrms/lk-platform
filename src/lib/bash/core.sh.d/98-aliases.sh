#!/bin/bash

lk_delete_on_exit() { lk_on_exit_delete "$@"; }
lk_kill_on_exit() { lk_on_exit_kill "$@"; }
lk_undo_delete_on_exit() { lk_on_exit_undo_delete "$@"; }
