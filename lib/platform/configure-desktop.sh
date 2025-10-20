#!/usr/bin/env bash

if lk_is_linux; then

    lk_require linux

    if lk_systemctl_exists libvirtd && lk_systemctl_enabled libvirtd; then
        lk_tty_print "Checking libvirt"
        if ! virsh net-list --name | grep -Fxq default; then
            lk_tty_detail "Starting network:" "default"
            virsh net-start default || true
        fi
        if ! virsh net-list --name --autostart | grep -Fxq default; then
            lk_tty_detail "Enabling network autostart:" "default"
            virsh net-autostart default || true
        fi
        if ! virsh net-list --name --all | grep -Fxq isolated; then
            lk_tty_detail "Adding network:" "isolated"
            virsh net-define <(
                cat <<"EOF"
<network>
  <name>isolated</name>
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
        lk_tty_print "Checking autorandr"
        DIR=/etc/xdg/autorandr
        lk_install -d -m 00755 "$DIR"
        for FILE in postsave postswitch predetect; do
            lk_install -m 00755 "$DIR/$FILE"
            lk_file_replace -f "$LK_BASE/lib/autorandr/$FILE" "$DIR/$FILE"
        done
    fi

fi
