#!/usr/bin/env bash

lk_linode_linodes() { linode-cli-json linodes list "$@"; }
lk_linode_ips() { linode-cli-json networking ips-list "$@"; }
lk_linode_domains() { linode-cli-json domains list "$@"; }
lk_linode_domain_records() { linode-cli-json domains records-list "$@"; }
lk_linode_firewalls() { linode-cli-json firewalls list "$@"; }
lk_linode_firewall_devices() { linode-cli-json firewalls devices-list "$@"; }
lk_linode_stackscripts() { linode-cli-json stackscripts list --is_public false "$@"; }
