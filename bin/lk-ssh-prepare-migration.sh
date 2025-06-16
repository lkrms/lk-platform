#!/usr/bin/env bash

lk_bin_depth=1 . lk-bash-load.sh || exit
lk_require provision

function __usage() {
    cat <<EOF
Configure SSH access to <SOURCE> from <TARGET>.

Usage:
  ${0##*/} [options] [USER@]<SOURCE>[:PORT] [USER@]<TARGET>[:PORT]

Options:
  -n, --source-name=<NAME>          on <TARGET>, refer to <SOURCE> as <NAME>
  -k, --source-key=<KEY_FILE>       use <KEY_FILE> with <SOURCE>
  -p, --source-password=<PASSWORD>  use <PASSWORD> with <SOURCE>

SSH options for <SOURCE> and <TARGET> are taken from ~/.ssh/config unless
overridden by command-line options.

Private keys are NEVER installed on remote systems. If no public key is found,
\`ssh-keygen -y\` is used to generate one to install on <TARGET> and <SOURCE>.
EOF
}

# process_host [USER@]<HOST>[:PORT] <VAR_PREFIX> [SSH_PARAMETER...]
function process_host() {
    local _SH
    _SH=$(lk_ssh_host_parameter_sh "$@") &&
        eval "$_SH" &&
        eval "${2}IDENTITYFILE=\$(lk_expand_path \"\$${2}IDENTITYFILE\")"
}

lk_getopt "n:k:p:" "source-name:,source-key:,source-password:"
eval "set -- $LK_GETOPT"

SOURCE_NAME=
SOURCE_KEY=
SOURCE_PASSWORD=

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -n | --source-name)
        SOURCE_NAME=$1
        ;;
    -k | --source-key)
        [[ -f $1 ]] || lk_warn "file not found: $1" || lk_usage
        lk_mktemp_with -r SOURCE_KEY lk_ssh_get_public_key "$1" 2>/dev/null ||
            lk_warn "invalid key file: $1" || lk_usage
        ;;
    -p | --source-password)
        SOURCE_PASSWORD=$1
        ;;
    --)
        break
        ;;
    esac
    shift
done

(($# == 2)) || lk_usage

process_host "$1" SOURCE_
process_host "$2" TARGET_
TARGET_HOST=$2

declare -p "${!SOURCE_@}" "${!TARGET_@}"
