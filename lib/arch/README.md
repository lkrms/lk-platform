# Arch Linux

## `bootstrap.sh`

This script:

- bootstraps Arch Linux on the given disk or partitions
- clones the `lk-platform` repository from GitHub to `/opt/lk-platform`
- runs `lk-provision-arch.sh` to finalise setup

For convenience, you can download it from <https://lkr.ms/bs> (or from
<https://lkr.ms/bs-dev> if you're testing the `develop` branch).

To get started:

1. [Download][download], verify and [create bootable media][bootable media] for
   a recent Arch Linux release
2. In your system's firmware settings, disable Secure Boot and check UEFI boot
   is enabled
3. Boot Arch Linux from the install media prepared earlier
4. Connect to the internet if not already connected

   For example:

   ```shell
   ip link
   # If no passphrase is given, it is read from standard input
   wpa_supplicant -B -i wlan0 -c <(wpa_passphrase "<ssid>" "<passphrase>")
   ping ping.archlinux.org
   ```

   > [!NOTE]
   >
   > The Arch Linux [installation guide][] recommends `iwctl` for Wi-Fi
   > authentication in live systems, but `iwctl station wlan0 connect <ssid>`
   > connects without starting a DHCP client. Launching `wpa_supplicant` instead
   > ensures the DHCP client provided by `systemd-networkd` is used.

5. Download and run the script

   ```shell
   curl -fLo bootstrap.sh https://lkr.ms/bs
   # Run without arguments to print usage information
   bash bootstrap.sh
   ```

### Settings

`bootstrap.sh` settings can be configured via command-line options or by
assigning values to the environment variables below.

Values for critical settings are requested interactively if not configured.

#### Transient

Only used while `bootstrap.sh` is running:

- `BOOTSTRAP_PING_HOST` (default: [`one.one.one.one`][1dot1dot1dot1])
- `BOOTSTRAP_TIME_URL`: System time is set from the `Date` header of the
  response from this URL (default: `https://$BOOTSTRAP_PING_HOST`)
- `BOOTSTRAP_MOUNT_OPTIONS`: On VMs with TRIM support, `discard` is added
  automatically (default: `defaults`)
- `BOOTSTRAP_USERNAME` (default: `arch`)
- `BOOTSTRAP_PASSWORD` (critical; randomly generated and logged to TTY if not
  configured and user input is off)
- `BOOTSTRAP_KEY`
- `BOOTSTRAP_FULL_NAME` (default: `Arch Linux`)

#### Persistent

Written to the bootstrapped system's `lk-platform.conf` file:

- `LK_IPV4_ADDRESS`
- `LK_IPV4_GATEWAY`
- `LK_DNS_SERVERS`: Space- or semicolon-delimited
- `LK_DNS_SEARCH`: Space- or semicolon-delimited
- `LK_BRIDGE_INTERFACE`: Ignored on laptops, otherwise configured on the first
  Ethernet port
- `LK_BRIDGE_IPV6_PD`: If set, the bridge is used to delegate an IPv6 prefix
- `LK_WIFI_REGDOM`: e.g. `AU` (see `/etc/conf.d/wireless-regdom`)
- `LK_TIMEZONE`: See `timedatectl list-timezones` (default: `UTC`)
- `LK_FEATURES`
- `LK_LOCALES`: `en_US.UTF-8` is always added (default:
  `en_AU.UTF-8 en_GB.UTF-8`)
- `LK_LANGUAGE` (default: `en_AU:en_GB:en`)
- `LK_SMB_CONF`
- `LK_SMB_WORKGROUP`
- `LK_GRUB_CMDLINE` (default: `quiet splash audit=0`, then
  `console=tty0 console=ttyS0` on VMs)
- `LK_NTP_SERVER` (default: `time.apple.com`)
- `LK_ARCH_MIRROR`
- `LK_ARCH_REPOS`: `<name>|<server>|<keyId>|<keyUrl>,...`
- `LK_ARCH_AUR_REPO_NAME`: If set, a local `aurutils` repo is provisioned
- `LK_ARCH_AUR_CHROOT_DIR` (default: `/var/lib/aurbuild`)
- `LK_PLATFORM_BRANCH` (default: `main`)
- `LK_PACKAGES_FILE`

[1dot1dot1dot1]: https://blog.cloudflare.com/dns-resolver-1-1-1-1/
[bootable media]: https://wiki.archlinux.org/title/USB_flash_installation_medium
[download]: https://archlinux.org/download/
[installation guide]: https://wiki.archlinux.org/title/Installation_guide
