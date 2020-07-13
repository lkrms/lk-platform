#!/bin/bash
# shellcheck disable=SC1090,SC2015,SC2207

set -euo pipefail
lk_die() { echo "$1" >&2 && exit 1; }
[ -n "${LK_BASE:-}" ] || { BS="${BASH_SOURCE[0]}" && [ ! -L "$BS" ] &&
    LK_BASE="$(cd "${BS%/*}/.." && pwd -P)" &&
    [ -d "$LK_BASE/lib/bash" ] || lk_die "${BS:+$BS: }LK_BASE not set"; }

include=iptables . "$LK_BASE/lib/bash/common.sh"

lk_elevate

[ -r "$LK_BASE/etc/firewall.conf" ] ||
    lk_die "cannot read file: $LK_BASE/etc/firewall.conf"
. "$LK_BASE/etc/firewall.conf"

S="[[:space:]]"

if [ -n "${ACCEPT_OUTPUT_CHAIN:-}" ]; then
    lk_console_message "Applying outgoing traffic policy to firewall"
    OUTPUT_ALLOW=(
        ${ACCEPT_OUTPUT_HOSTS[@]+"${ACCEPT_OUTPUT_HOSTS[@]}"}
    )
    [ "${#OUTPUT_ALLOW[@]}" -eq "0" ] ||
        lk_console_detail "Added to whitelist from firewall.conf:" \
            "$(lk_implode $'\n' "${OUTPUT_ALLOW[@]}")"
    if lk_is_ubuntu; then
        APT_SOURCE_HOSTS=($(
            grep -Eo "^[^#]+${S}https?://[^/[:space:]]+" "/etc/apt/sources.list" |
                sed -E 's/^.*:\/\///' | sort | uniq
        )) || lk_die "no active package sources in /etc/apt/sources.list"
        OUTPUT_ALLOW+=("${APT_SOURCE_HOSTS[@]}")
        lk_console_detail "Added to whitelist from APT source list:" \
            "$(lk_implode $'\n' "${APT_SOURCE_HOSTS[@]}")"
    fi
    # TODO: add temporary entry for api.github.com to /etc/hosts and flush
    # chain with static hosts first (otherwise api.github.com may be
    # unreachable)
    if lk_in_array "api.github.com" ACCEPT_OUTPUT_HOSTS; then
        GITHUB_META="$(curl --silent --show-error "https://api.github.com/meta")" &&
            GITHUB_IPS=($(jq -r ".web[],.api[]" <<<"$GITHUB_META" | sort | uniq)) &&
            OUTPUT_ALLOW+=("${GITHUB_IPS[@]}") &&
            lk_console_detail "Added to whitelist from GitHub API:" "${#GITHUB_IPS[@]} IP $(lk_maybe_plural "${#GITHUB_IPS[@]}" range ranges)" || {
            lk_console_warning "Unable to retrieve IP ranges from GitHub API"
            unset GITHUB_IPS
        }
    fi
    OUTPUT_ALLOW_IPV4=()
    OUTPUT_ALLOW_IPV6=()
    if [ "${#OUTPUT_ALLOW[@]}" -gt "0" ]; then
        OUTPUT_ALLOW_RESOLVED="$(lk_resolve "${OUTPUT_ALLOW[@]}")" ||
            lk_die "unable to resolve domain names"
        OUTPUT_ALLOW_IPV4=($(echo "$OUTPUT_ALLOW_RESOLVED" | lk_grep_ipv4 || :))
        OUTPUT_ALLOW_IPV6=($(echo "$OUTPUT_ALLOW_RESOLVED" | lk_grep_ipv6 || :))
    fi
    lk_console_detail "Flushing iptables chain:" "$ACCEPT_OUTPUT_CHAIN"
    lk_iptables_both lk_iptables_flush_chain "$ACCEPT_OUTPUT_CHAIN"
    [ "${#OUTPUT_ALLOW_IPV4[@]}" -eq "0" ] ||
        lk_console_detail "Adding" "${#OUTPUT_ALLOW_IPV4[@]} IP $(lk_maybe_plural "${#OUTPUT_ALLOW_IPV4[@]}" rule rules)"
    for IPV4 in ${OUTPUT_ALLOW_IPV4[@]+"${OUTPUT_ALLOW_IPV4[@]}"}; do
        iptables -A "$ACCEPT_OUTPUT_CHAIN" -d "$IPV4" -j ACCEPT
    done
    [ "${#OUTPUT_ALLOW_IPV6[@]}" -eq "0" ] ||
        lk_console_detail "Adding" "${#OUTPUT_ALLOW_IPV6[@]} IPv6 $(lk_maybe_plural "${#OUTPUT_ALLOW_IPV6[@]}" rule rules)"
    for IPV6 in ${OUTPUT_ALLOW_IPV6[@]+"${OUTPUT_ALLOW_IPV6[@]}"}; do
        ip6tables -A "$ACCEPT_OUTPUT_CHAIN" -d "$IPV6" -j ACCEPT
    done
fi
