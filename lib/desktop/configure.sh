#!/bin/bash

if lk_is_linux; then

    if systemctl is-enabled --quiet "libvirtd.service"; then
        lk_console_message "Configuring libvirt"
        if ! virsh net-list --name | grep -Fx "default" >/dev/null; then
            lk_console_detail "Activating default network"
            virsh net-start default || true
        fi
        if ! virsh net-list --name --autostart |
            grep -Fx "default" >/dev/null; then
            lk_console_detail "Enabling autostart for default network"
            virsh net-autostart default || true
        fi
        if ! virsh net-list --name --all | grep -Fx "isolated" >/dev/null; then
            lk_console_detail "Creating isolated network"
            virsh net-define <(
                cat <<EOF
<network>
  <name>isolated</name>
  <domain name='isolated'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.128' end='192.168.100.254'/>
    </dhcp>
  </ip>
</network>
EOF
            )
        fi
    fi

    if lk_command_exists autorandr; then
        lk_console_message "Configuring autorandr hooks"
        lk_symlink "$LK_BASE/lib/autorandr/postsave" \
            "/etc/xdg/autorandr/postsave"
        lk_symlink "$LK_BASE/lib/autorandr/postswitch" \
            "/etc/xdg/autorandr/postswitch"
    fi

fi
