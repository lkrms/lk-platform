#!/usr/bin/env bash

_LK_ENV=$(declare -x)

lk_bin_depth=1 . lk-bash-load.sh || exit
lk_require validate

# `local -n` was added in Bash 4.3
lk_bash_is 4 3 || lk_die "Bash 4.3 or higher required"

IMAGE=ubuntu-24.04
VM_PACKAGES=
VM_FILESYSTEM_MAPS=
VM_MEMORY=2048
VM_CPUS=2
VM_DISK_SIZE=80G
VM_IPV4_CIDR=
VM_MAC_ADDRESS="52:54:00$(printf ':%02x' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))"
DIRECT_KERNEL_BOOT=
REFRESH_CLOUDIMG=
FORWARD_XML=()
HOSTFWD=()
ISOLATE=
ISOLATE_ACTION_XML=
ALLOW_HOST_XML=
ALLOW_HOST_NET_XML=
ALLOW_HOSTS_XML=()
ALLOW_URL_XML=()
STACKSCRIPT=
METADATA=()
METADATA_URLS=()
POWEROFF=
FORCE_DELETE=

LK_USAGE="\
${0##*/} [OPTIONS] VM_NAME

Boot a new libvirt VM from the current release of a cloud-init image.

OPTIONS

    -i, --image=IMAGE               boot from IMAGE (default: $IMAGE)
    -k, --direct-kernel-boot        boot guest directly from a kernel and initrd
    -r, --refresh-image             download latest IMAGE if cached version
                                    is out-of-date
    -p, --packages=PACKAGE,...      install each PACKAGE in guest
    -f, --fs-maps=PATHS|...         export HOST_PATH as GUEST_PATH for each
                                    HOST_PATH,GUEST_PATH
    -P, --preset=PRESET             use PRESET to configure -m, -c, -s
    -m, --memory=SIZE               allocate memory (MiB, default: $VM_MEMORY)
    -c, --cpus=COUNT                allocate virtual CPUs (default: $VM_CPUS)
    -s, --disk-size=SIZE            resize disk image (GiB, default: ${VM_DISK_SIZE%G})
    -n, --network=NETWORK           connect guest to libvirt network NETWORK
                                    (or IFNAME if bridge=IFNAME specified)
    -I, --ip-address=CIDR           use CIDR to configure static IP in guest
    -R, --forward=PORTS|...         add custom metadata to forward each
                                    PROTO:<HOST-PORT[:GUEST-PORT],...>
    -O, --isolate                   add custom metadata to block outgoing
                                    traffic from guest
    -M, --mac=52:54:00:xx:xx:xx     set MAC address of guest network
                                    interface (default: <random>)
    -S, --stackscript=SCRIPT        use cloud-init to run SCRIPT in guest
    -x, --metadata=URL,KEY,XML      add custom metadata XML
    -H, --poweroff                  shut down guest after first boot
    -u, --session                   launch guest as user instead of system
    -y, --yes                       do not prompt for input
    -F, --force                     delete existing guest VM_NAME without
                                    prompting (implies -y)

If --isolate is set:

        --no-reject-log             don't log blocked traffic
        --no-reject                 don't block anything, just log traffic
                                    that would be blocked
    -g, --allow-gateway             allow traffic to host system
    -l, --allow-gateway-lan         allow traffic to host's default LAN
    -h, --allow-host=HOST,...       allow traffic to each name, IP or CIDR
    -U, --allow-url=URL,FILTER      allow traffic to each host returned by
                                    passing JSON from URL to \`jq -r FILTER\`

SUPPORTED IMAGES

    ubuntu-24.04        ubuntu-24.04-minimal
    ubuntu-22.04        ubuntu-22.04-minimal
    ubuntu-20.04        ubuntu-20.04-minimal
    ubuntu-18.04        ubuntu-18.04-minimal
    ubuntu-16.04        ubuntu-16.04-minimal
    ubuntu-14.04

PRESETS

    linode16gb      (6 CPUs, 16GiB memory, 320G storage)
    linode8gb       (4 CPUs,  8GiB memory, 160G storage)
    linode4gb       (2 CPUs,  4GiB memory,  80G storage)
    linode2gb       (1 CPUs,  2GiB memory,  50G storage)
    linode1gb       (1 CPUs,  1GiB memory,  25G storage)

FILTERING

If --forward or --isolate are set, custom metadata similar to the following
is added to the domain XML. It only takes effect if a libvirt hook applies
the relevant firewall changes.

    <lk:lk xmlns:lk=\"http://linacreative.com/xmlns/libvirt/domain/1.0\">
      <lk:ip>
        <lk:address>192.168.122.10</lk:address>
        <lk:forward>
          <lk:protocol>tcp</lk:protocol>
          <lk:port>80</lk:port>
          <lk:port>443</lk:port>
          <lk:from-host>2210</lk:from-host>
          <lk:to-guest>22</lk:to-guest>
        </lk:forward>
        <lk:isolate>
          <lk:allow>
            <lk:gateway />
            <lk:host>10.1.1.1</lk:host>
            <lk:from-url>
              <lk:url>https://api.github.com/meta</lk:url>
              <lk:filter>.web[],.api[],.git[]</lk:filter>
            </lk:from-url>
          </lk:allow>
        </lk:isolate>
      </lk:ip>
    </lk:lk>

STACKSCRIPTS

If --stackscript is set, the user is prompted for any UDF tags, cloud-init
is configured to create a Linode-like environment, and the entire script is
added to the runcmd module. The --packages option is ignored.

EXAMPLE

\\    ${0##*/} -y -i ubuntu-18.04-minimal -r -c 2 -m 2048 -s 10G \\
      -n bridge=virbr0 -I 192.168.122.184/24 -Ogl --no-reject demo-server"

lk_getopt "i:krp:f:P:m:c:s:n:I:R:OM:S:x:HuyFglh:U:" \
    "image:,direct-kernel-boot,refresh-image,packages:,fs-maps:,preset:,memory:,\
cpus:,disk-size:,network:,ip-address:,forward:,isolate,mac:,stackscript:,\
metadata:,poweroff,session,force,allow-gateway,allow-gateway-lan,allow-host:,\
allow-url:,no-log,no-reject"
eval "set -- $LK_GETOPT"

UBUNTU_HOST=${LK_UBUNTU_CLOUDIMG_HOST:-cloud-images.ubuntu.com}
UBUNTU_SHA_URL=${LK_UBUNTU_CLOUDIMG_SHA_URL:-https://cloud-images.ubuntu.com}
UBUNTU_MIRROR=${LK_UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}

SYSTEM_SOCKET=
SESSION_SOCKET=
POOL_ROOT=/var/lib/libvirt/images
IMAGE_ARCH=amd64
QEMU_ARCH=x86_64
QEMU_MACHINE=
! lk_system_is_macos || {
    # Use explicit sockets to ensure x86_64 virt-install connects to native
    # libvirtd on arm64
    SYSTEM_SOCKET=$HOMEBREW_PREFIX/var/run/libvirt/libvirt-sock
    SESSION_SOCKET=${XDG_RUNTIME_DIR:-~/.cache}/libvirt/libvirt-sock
    POOL_ROOT=$HOMEBREW_PREFIX/var/lib/libvirt/images
    QEMU_MACHINE=q35
    ! lk_system_is_apple_silicon || {
        IMAGE_ARCH=arm64
        QEMU_ARCH=aarch64
        QEMU_MACHINE=virt
    }
}
[[ $IMAGE_ARCH == amd64 ]] ||
    UBUNTU_MIRROR=${LK_UBUNTU_PORTS_MIRROR:-http://ports.ubuntu.com}

VM_NETWORK_DEFAULT=default
LIBVIRT_URI=qemu:///system${SYSTEM_SOCKET:+?socket=$SYSTEM_SOCKET}
LK_SUDO=1
XMLNS=http://linacreative.com/xmlns/libvirt/domain/1.0

eval "$(lk_get_regex HOST_OPT_PREFIX_REGEX URI_REGEX_REQ_SCHEME_HOST)"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -i | --image)
        IMAGE=$1
        ;;
    -k | --direct-kernel-boot)
        DIRECT_KERNEL_BOOT=yes
        continue
        ;;
    -r | --refresh-image)
        REFRESH_CLOUDIMG=yes
        continue
        ;;
    -p | --packages)
        [[ -n $STACKSCRIPT ]] ||
            VM_PACKAGES=$1
        ;;
    -f | --fs-maps)
        VM_FILESYSTEM_MAPS=$1
        ;;
    -P | --preset)
        case "$1" in
        linode1gb)
            VM_CPUS=1
            VM_MEMORY=1024
            VM_DISK_SIZE=25G
            ;;
        linode2gb)
            VM_CPUS=1
            VM_MEMORY=2048
            VM_DISK_SIZE=50G
            ;;
        linode4gb)
            VM_CPUS=2
            VM_MEMORY=4096
            VM_DISK_SIZE=80G
            ;;
        linode8gb)
            VM_CPUS=4
            VM_MEMORY=8192
            VM_DISK_SIZE=160G
            ;;
        linode16gb)
            VM_CPUS=6
            VM_MEMORY=16384
            VM_DISK_SIZE=320G
            ;;
        *)
            lk_warn "invalid preset: $1"
            lk_usage
            ;;
        esac
        ;;
    -m | --memory)
        [[ $1 =~ ^[1-9][0-9]*$ ]] ||
            lk_warn "invalid memory size: $1" || lk_usage
        VM_MEMORY=$1
        ;;
    -c | --cpus)
        [[ $1 =~ ^[1-9][0-9]*$ ]] ||
            lk_warn "invalid CPU count: $1" || lk_usage
        VM_CPUS=$1
        ;;
    -s | --disk-size)
        [[ $1 =~ ^([0-9]+)([bkKMGT]?)$ ]] ||
            lk_warn "invalid disk size: $1" || lk_usage
        VM_DISK_SIZE=${BASH_REMATCH[1]}${BASH_REMATCH[2]:-G}
        ;;
    -n | --network)
        VM_NETWORK=$1
        ;;
    -I | --ip-address)
        [[ $1 =~ ^([0-9]+(\.[0-9]+){3})/([0-9]+)$ ]] ||
            lk_warn "invalid IPv4 CIDR: $1" || lk_usage
        VM_IPV4_CIDR=$1
        VM_IPV4_ADDRESS=${BASH_REMATCH[1]}
        VM_IPV4_NETWORK=
        VM_IPV4_MASK=
        VM_IPV4_GATEWAY=
        bits=${BASH_REMATCH[3]}
        bytes=4
        IFS=.
        for byte in $VM_IPV4_ADDRESS; do
            mask=0
            for b in {1..8}; do
                ((mask <<= 1, mask += (bits-- > 0 ? 1 : 0))) || true
            done
            ((byte &= mask, gw_quad = byte)) || true
            ((--bytes)) && dot=. || { dot= && ((gw_quad |= 1)); }
            VM_IPV4_NETWORK+=$byte$dot
            VM_IPV4_MASK+=$mask$dot
            VM_IPV4_GATEWAY+=$gw_quad$dot
        done
        unset IFS
        ;;
    -R | --forward)
        REGEX='(tcp|udp)(:[0-9]+){1,2}(,[0-9]+(:[0-9]+)?)*'
        [[ $1 =~ ^$REGEX(\|$REGEX)*$ ]] ||
            lk_warn "invalid ports: $1" || lk_usage
        IFS="|"
        PORTS=($1)
        unset IFS
        REGEX='((tcp|udp):)?([0-9]+)(:([0-9]+))?(,(.*))?'
        for FORWARD in "${PORTS[@]}"; do
            _XML=()
            while [[ $FORWARD =~ ^$REGEX ]]; do
                PROTOCOL=${BASH_REMATCH[2]}
                FROM_HOST=${BASH_REMATCH[3]}
                TO_GUEST=${BASH_REMATCH[5]}
                FORWARD=${BASH_REMATCH[7]}
                [[ -z $PROTOCOL ]] ||
                    _XML[${#_XML[@]}]="<protocol>$PROTOCOL</protocol>"
                [[ -z $TO_GUEST ]] &&
                    _XML[${#_XML[@]}]="<port>$FROM_HOST</port>" ||
                    _XML+=("<from-host>$FROM_HOST</from-host>"
                        "<to-guest>$TO_GUEST</to-guest>")
                HOSTFWD+=("${PROTOCOL:-$_PROTOCOL}::$FROM_HOST-:${TO_GUEST:-$FROM_HOST}")
                _PROTOCOL=$PROTOCOL
            done
            XML=$(lk_arr _XML)
            XML="<forward>
  ${XML//$'\n'/$'\n'  }
</forward>"
            FORWARD_XML[${#FORWARD_XML[@]}]=$XML
        done
        ;;
    -O | --isolate)
        ISOLATE=1
        continue
        ;;
    -M | --mac)
        VM_MAC_ADDRESS=$1
        ;;
    -S | --stackscript)
        [[ -f $1 ]] ||
            lk_warn "invalid StackScript: $1" || lk_usage
        STACKSCRIPT=$1
        VM_PACKAGES=
        ;;
    -x | --metadata)
        IFS=, read -r -d '' URL KEY XML < <(printf '%s\0' "$1") &&
            [[ -n ${XML:+1} ]] ||
            lk_warn "invalid metadata: $1" || lk_usage
        [[ $URL != "$XMLNS" ]] ||
            lk_warn "metadata URL not allowed: $URL" || lk_usage
        ! lk_in_array "$URL" METADATA_URLS ||
            lk_warn "metadata URL not unique: $URL"
        for i in URL KEY XML; do
            METADATA[${#METADATA[@]}]=${!i}
        done
        METADATA_URLS[${#METADATA_URLS[@]}]=$URL
        ;;
    -H | --poweroff)
        POWEROFF=yes
        continue
        ;;
    -u | --session)
        POOL_ROOT=${LK_CLOUDIMG_SESSION_ROOT:-~/.local/share/libvirt/images}
        VM_NETWORK_DEFAULT=bridge=virbr0
        LIBVIRT_URI=qemu:///session${SESSION_SOCKET:+?socket=$SESSION_SOCKET}
        unset LK_SUDO
        continue
        ;;
    -y | --yes)
        LK_NO_INPUT=Y
        continue
        ;;
    -F | --force)
        FORCE_DELETE=1
        LK_NO_INPUT=Y
        continue
        ;;
    -g | --allow-gateway)
        ALLOW_HOST_XML="<gateway />"
        continue
        ;;
    -l | --allow-gateway-lan)
        ALLOW_HOST_NET_XML="<gateway-lan />"
        continue
        ;;
    -h | --allow-host)
        IFS=,
        for HOST in $1; do
            [[ $HOST =~ $HOST_OPT_PREFIX_REGEX ]] ||
                lk_warn "invalid host: $HOST" || lk_usage
            ALLOW_HOSTS_XML[${#ALLOW_HOSTS_XML[@]}]="<host>$HOST</host>"
        done
        unset IFS
        ;;
    -U | --allow-url)
        while IFS=, read -r -d '' URL FILTER; do
            [[ $URL =~ $URI_REGEX_REQ_SCHEME_HOST ]] ||
                lk_warn "invalid URL: $URL" || lk_usage
            ALLOW_URL_XML[${#ALLOW_URL_XML[@]}]="\
<from-url>
  <url>$URL</url>
  <filter>${FILTER:-.}</filter>
</from-url>"
        done < <(IFS="|" && printf '%s\0' $1)
        ;;
    --no-reject-log)
        ISOLATE_ACTION_XML="<no-log />"
        continue
        ;;
    --no-reject)
        ISOLATE_ACTION_XML="<no-reject />"
        continue
        ;;
    --)
        break
        ;;
    esac
    shift
done

VM_NETWORK=${VM_NETWORK:-$VM_NETWORK_DEFAULT}
! lk_system_is_macos || VM_NETWORK=user=

if [[ $VM_NETWORK == user=* ]]; then
    [[ -z $VM_IPV4_CIDR$ISOLATE ]] || lk_warn \
        "usermode networking cannot be used with --ip-address or --isolate" ||
        lk_usage
else
    XML=
    [[ -z $ISOLATE ]] || {
        XML=$(
            [[ -z $ALLOW_HOST_XML ]] || echo "$ALLOW_HOST_XML"
            [[ -z $ALLOW_HOST_NET_XML ]] || echo "$ALLOW_HOST_NET_XML"
            lk_arr ALLOW_HOSTS_XML
            lk_arr ALLOW_URL_XML
        )
        [[ -z ${XML:+1} ]] || XML="<allow>
  ${XML//$'\n'/$'\n'  }
</allow>"
        XML=${ISOLATE_ACTION_XML:+$ISOLATE_ACTION_XML
}$XML
        [[ -z ${XML:+1} ]] &&
            XML="<isolate />" ||
            XML="<isolate>
  ${XML//$'\n'/$'\n'  }
</isolate>"
    }
    XML=$(
        lk_arr FORWARD_XML
        echo "$XML"
    )
    [[ -z ${XML:+1} ]] || {
        [[ -n $VM_IPV4_CIDR ]] ||
            lk_warn "--ip-address required with --forward and --isolate" ||
            lk_usage
        XML="<lk>
  <ip>
    <address>$VM_IPV4_ADDRESS</address>
    ${XML//$'\n'/$'\n'    }
  </ip>
</lk>"
        METADATA+=("$XMLNS" lk "$XML")
        METADATA_URLS[${#METADATA_URLS[@]}]=$XMLNS
    }
fi

VM_HOSTNAME=${1-}
[[ -n $VM_HOSTNAME ]] || lk_usage

# boot_ubuntu RELEASE CODENAME [IMAGE_SUFFIX]
function boot_ubuntu() {
    IMAGE_NAME=ubuntu-$1
    IMAGE_URL=http://$UBUNTU_HOST/$2/current/$2-server-cloudimg-${IMAGE_ARCH}${3-}.img
    SHA_URLS=(
        "$UBUNTU_SHA_URL/$2/current/SHA256SUMS.gpg"
        "$UBUNTU_SHA_URL/$2/current/SHA256SUMS"
    )
    # On Apple Silicon, the default console (ttyAMA0) won't receive output if
    # the cloud image boots with "console=tty1 console=ttyS0" or similar, and
    # early Ubuntu 22.04 images for arm64 applied these options by default.
    # Direct kernel boot allows us to override the default cmdline.
    ! lk_is_true DIRECT_KERNEL_BOOT || {
        KERNEL_URL=http://$UBUNTU_HOST/$2/current/unpacked/$2-server-cloudimg-${IMAGE_ARCH}-vmlinuz-generic
        INITRD_URL=http://$UBUNTU_HOST/$2/current/unpacked/$2-server-cloudimg-${IMAGE_ARCH}-initrd-generic
        KERNEL_SHA_URLS=(
            "$UBUNTU_SHA_URL/$2/current/unpacked/SHA256SUMS.gpg"
            "$UBUNTU_SHA_URL/$2/current/unpacked/SHA256SUMS"
        )
        INITRD_SHA_URLS=("${KERNEL_SHA_URLS[@]}")
        # TODO: use `guestfish --ro -a img.qcow2 run : get-uuid /dev/sda1` to
        # retrieve the root partition's UUID
        KERNEL_ARGS=(root=LABEL=cloudimg-rootfs ro)
        [[ $IMAGE_ARCH == arm64 ]] || KERNEL_ARGS+=(console=tty1 console=ttyS0)
    }
    OS_VARIANT=ubuntu$1
}

# boot_ubuntu_minimal RELEASE CODENAME [IMAGE_SUFFIX]
function boot_ubuntu_minimal() {
    IMAGE_NAME=ubuntu-$1-minimal
    IMAGE_URL=http://$UBUNTU_HOST/minimal/releases/$2/release/ubuntu-$1-minimal-cloudimg-${IMAGE_ARCH}${3-}.img
    SHA_URLS=(
        "$UBUNTU_SHA_URL/minimal/releases/$2/release/SHA256SUMS.gpg"
        "$UBUNTU_SHA_URL/minimal/releases/$2/release/SHA256SUMS"
    )
    OS_VARIANT=ubuntu$1
}

KERNEL_URL=
INITRD_URL=
KERNEL_ARGS=()
SHA_KEYRING=/usr/share/keyrings/ubuntu-cloudimage-keyring.gpg
[[ -r $SHA_KEYRING ]] ||
    SHA_KEYRING=$LK_BASE/share/keys/ubuntu-cloudimage-keyring.gpg
[[ $IMAGE_ARCH == amd64 ]] || {
    [[ $IMAGE != *minimal ]] ||
        lk_die "minimal images are not available for $IMAGE_ARCH"
    [[ $IMAGE != *14.04* ]] ||
        lk_die "Ubuntu 14.04 is not supported on $IMAGE_ARCH"
}
case "$IMAGE" in
*24.04*minimal)
    boot_ubuntu_minimal 24.04 noble
    ;;
*24.04*)
    boot_ubuntu 24.04 noble
    ;;
*22.04*minimal)
    boot_ubuntu_minimal 22.04 jammy
    ;;
*22.04*)
    boot_ubuntu 22.04 jammy
    ;;
*20.04*minimal)
    boot_ubuntu_minimal 20.04 focal
    ;;
*20.04*)
    boot_ubuntu 20.04 focal
    ;;
*18.04*minimal)
    boot_ubuntu_minimal 18.04 bionic
    ;;
*18.04*)
    boot_ubuntu 18.04 bionic
    ;;
*16.04*minimal)
    boot_ubuntu_minimal 16.04 xenial -disk1
    ;;
*16.04*)
    boot_ubuntu 16.04 xenial -disk1
    ;;
*14.04*)
    boot_ubuntu 14.04 trusty -disk1
    ;;
*)
    lk_warn "invalid cloud image: $IMAGE"
    lk_usage
    ;;
esac

lk_input_is_off || [[ $VM_NETWORK != user=* ]] || [[ -n ${HOSTFWD+1} ]] || {
    lk_tty_warning "Unreachable guest detected:" "$VM_HOSTNAME"
    lk_tty_print \
        "Port forwarding is required to access guests with usermode networking"
    lk_tty_detail "Example:" "--forward tcp:2222:22"
    lk_tty_yn "Proceed anyway?" Y || lk_die ""
    lk_tty_print
}

if [[ -n $STACKSCRIPT ]]; then
    lk_mapfile SS_TAGS < <(grep -Eo \
        "<(lk:)?[uU][dD][fF]($LK_h+[a-zA-Z]+=\"[^\"]*\")*$LK_h*/>" \
        "$STACKSCRIPT")
    [[ -z ${SS_TAGS+1} ]] || lk_tty_log "Processing StackScript"
    SS_FIELDS=()
    TAG=0
    for SS_TAG in ${SS_TAGS+"${SS_TAGS[@]}"}; do
        ((++TAG))
        lk_mapfile SS_ATTRIBS < <(grep -Eo '[a-z]+="[^"]*"' <<<"$SS_TAG")
        unset NAME LABEL DEFAULT SELECT_OPTIONS SELECT_TEXT VALIDATE_COMMAND
        _LK_REQUIRED=1
        REQUIRED_TEXT=required
        for SS_ATTRIB in ${SS_ATTRIBS+"${SS_ATTRIBS[@]}"}; do
            [[ $SS_ATTRIB =~ ^([a-z]+)=\"([^\"]*)\"$ ]]
            case "${BASH_REMATCH[1]}" in
            name)
                NAME=${BASH_REMATCH[2]}
                ;;
            label)
                LABEL=${BASH_REMATCH[2]}
                ;;
            default)
                DEFAULT=${BASH_REMATCH[2]}
                _LK_REQUIRED=0
                REQUIRED_TEXT=optional
                ;;
            oneof | manyof)
                unset IFS
                SELECT_OPTIONS=(${BASH_REMATCH[2]//,/ })
                if [[ ${BASH_REMATCH[1]} == oneof ]]; then
                    SELECT_TEXT="Value must be one of the following"
                    VALIDATE_COMMAND=(
                        lk_validate_one_of VALUE "${SELECT_OPTIONS[@]}")
                else
                    SELECT_TEXT="Value must be one or more of the following (comma-delimited)"
                    VALIDATE_COMMAND=(
                        lk_validate_many_of VALUE "${SELECT_OPTIONS[@]}")
                fi
                ;;
            esac
        done
        ((!_LK_REQUIRED)) ||
            [[ -n ${VALIDATE_COMMAND+1} ]] ||
            VALIDATE_COMMAND=(lk_validate_not_null VALUE)
        lk_tty_print "Checking field $TAG of ${#SS_TAGS[@]}:" "$NAME"
        [[ -z ${SELECT_TEXT-} ]] ||
            lk_tty_list_detail SELECT_OPTIONS "$SELECT_TEXT:"
        [[ -z ${DEFAULT-} ]] ||
            lk_tty_detail "Default value:" "$DEFAULT"
        VALUE=$(lk_var_env "$NAME") || unset VALUE
        i=0
        while ((++i)); do
            IS_VALID=1
            [[ -z ${VALIDATE_COMMAND+1} ]] ||
                FIELD_ERROR=$(_LK_VALIDATE_FIELD_NAME=$NAME \
                    "${VALIDATE_COMMAND[@]}") ||
                IS_VALID=0
            INITIAL_VALUE=${VALUE-${DEFAULT-}}
            ((IS_VALID)) ||
                ! { lk_input_is_off || ((i > 1)); } ||
                lk_tty_error "$FIELD_ERROR"
            if ((IS_VALID)) && { lk_input_is_off || ((i > 1)); }; then
                lk_tty_detail "Using value:" "$INITIAL_VALUE" "$LK_GREEN"
                break
            else
                LK_FORCE_INPUT=Y lk_tty_read \
                    "-$REQUIRED_TEXT" \
                    "$LK_BOLD$LABEL$LK_UNBOLD_UNDIM:" VALUE \
                    "" ${INITIAL_VALUE:+-i "$INITIAL_VALUE"}
            fi
        done
        [[ ${VALUE:=} != "${DEFAULT-}" ]] ||
            lk_is_true LK_STACKSCRIPT_EXPORT_DEFAULT ||
            continue
        SS_FIELDS+=("$NAME=$VALUE")
    done
    STACKSCRIPT_ENV=
    [[ ${#SS_FIELDS[@]} -eq 0 ]] || {
        # This works because cloud-init does no unescaping
        STACKSCRIPT_ENV=$(lk_arr SS_FIELDS | sort)
    }
    [[ -z ${SS_TAGS+1} ]] || lk_tty_print
fi

KEYS_FILE=~/.ssh/authorized_keys
[[ -f $KEYS_FILE ]] || lk_die "file not found: $KEYS_FILE"
SSH_AUTHORIZED_KEYS=$(grep -Ev "^(#|$LK_h*\$)" "$KEYS_FILE" |
    jq -Rn '[ inputs | split("\n")[] ]') ||
    lk_die "no keys in $KEYS_FILE"

while VM_STATE=$(lk_sudo virsh domstate "$VM_HOSTNAME" 2>/dev/null); do
    [[ $VM_STATE != "shut off" ]] || unset VM_STATE
    lk_tty_error "Domain already exists:" "$VM_HOSTNAME"
    PROMPT=(
        "OK to"
        ${VM_STATE+"force off,"}
        "delete and permanently remove all storage volumes?"
    )
    lk_is_true FORCE_DELETE ||
        LK_FORCE_INPUT=Y lk_tty_yn "${PROMPT[*]}" N ||
        lk_die ""
    [[ -z ${VM_STATE+1} ]] ||
        lk_sudo virsh destroy "$VM_HOSTNAME" || true
    lk_sudo virsh undefine \
        --managed-save \
        --snapshots-metadata \
        --checkpoints-metadata \
        --nvram \
        --remove-all-storage \
        --tpm \
        "$VM_HOSTNAME" || true
done

lk_tty_print "Provisioning:"
_VM_PACKAGES=${VM_PACKAGES//,/, }
_VM_IPV4_ADDRESS=${VM_IPV4_CIDR:+$VM_IPV4_CIDR (gateway: $VM_IPV4_GATEWAY)}
_VM_NETWORK=$VM_NETWORK
[[ $VM_NETWORK != user=* ]] || _VM_NETWORK="<usermode networking>"
printf '%s\t%s\n' \
    "Name" "$LK_BOLD$VM_HOSTNAME$LK_RESET" \
    "Image" "$IMAGE_NAME" \
    "Direct kernel boot" "${DIRECT_KERNEL_BOOT:-no}" \
    "Refresh if cached" "${REFRESH_CLOUDIMG:-no}" \
    "Packages" "${_VM_PACKAGES:-<none>}" \
    "Filesystem maps" "${VM_FILESYSTEM_MAPS:-<none>}" \
    "Memory" "$VM_MEMORY" \
    "CPUs" "$VM_CPUS" \
    "Disk size" "$VM_DISK_SIZE" \
    "Network" "$_VM_NETWORK" \
    "IPv4 address" "${_VM_IPV4_ADDRESS:-<dhcp>}" \
    "MAC address" "$VM_MAC_ADDRESS" \
    "StackScript" "${STACKSCRIPT:-<none>}" \
    "Custom metadata" "${#METADATA_URLS[@]} namespace$(lk_plural \
        ${#METADATA_URLS[@]} "" s)" \
    "Shut down" "${POWEROFF:-no}" \
    "Libvirt service" "$LIBVIRT_URI" \
    "Disk image path" "$POOL_ROOT" | IFS=$'\t' lk_tty_pairs_detail
[[ -z $STACKSCRIPT ]] ||
    lk_tty_detail "StackScript environment:" \
        $'\n'"$([[ ${#SS_FIELDS[@]} -eq 0 ]] && echo "<empty>" ||
            lk_arr SS_FIELDS | sort)"
lk_tty_yn "OK to proceed?" Y || lk_die ""
lk_tty_print

{
    lk_elevate -f install -d -m 01777 \
        "$LK_BASE/var/cache/lk-platform"/{cloud-images,cloud-image-kernels,NoCloud} 2>/dev/null &&
        cd "$LK_BASE/var/cache/lk-platform/cloud-images" ||
        lk_die "error creating cache directories"

    # download_image URL SHA_URL...
    function download_image() {
        local URL=$1 FILE SUMS SUMS_GPG
        shift
        FILE=${URL##*/}
        IMAGE_FILE=$FILE
        if [[ ! -f $FILE ]] || lk_is_true REFRESH_CLOUDIMG; then
            lk_tty_detail "Downloading" "$FILE"
            wget --no-cache --timestamping \
                --no-verbose --show-progress "$URL" || {
                rm -f "$FILE"
                lk_die "error downloading $URL"
            }
        fi
        if [[ ! -f SHASUMS-${FILE%.*} ]] || lk_is_true REFRESH_CLOUDIMG; then
            lk_mktemp_with SUMS
            if (($# == 1)); then
                lk_curl "$1" |
                    gpg --no-default-keyring \
                        --keyring "$SHA_KEYRING" \
                        --decrypt \
                        >"$SUMS" 2>/dev/null
            else
                lk_curl "$2" >"$SUMS" &&
                    lk_mktemp_with SUMS_GPG lk_curl "$1" &&
                    gpg --no-default-keyring \
                        --keyring "$SHA_KEYRING" \
                        --verify "$SUMS_GPG" "$SUMS" 2>/dev/null
            fi || lk_die "error verifying $1"
            cp "$SUMS" "SHASUMS-${FILE%.*}" ||
                lk_die "error creating $PWD/SHASUMS-${FILE%.*}"
        fi
    }

    # maybe_verify_image IMAGE_FILE TARGET_PATH
    function maybe_verify_image() {
        lk_install -d -m 00755 "${2%/*}"
        if lk_sudo test -f "$2"; then
            lk_tty_detail "Already installed:" "$2"
            false
        else
            awk -F '[*[:blank:]]+' -v "img=$1" '$2 == img' "SHASUMS-${1%.*}" |
                shasum -a "${SHA_ALGORITHM:-256}" -c >/dev/null &&
                lk_tty_success "Verified" "$1" ||
                lk_die "verification failed: $PWD/$1"
        fi
        lk_pass lk_tty_print
    }

    lk_tty_print \
        "Acquiring image file${KERNEL_URL:+s} for" "$IMAGE_NAME"
    download_image "$IMAGE_URL" "${SHA_URLS[@]}"
    CLOUDIMG_NAME=${IMAGE_FILE%.*}-$(lk_file_modified "$IMAGE_FILE")
    CLOUDIMG_PATH=$POOL_ROOT/cloud-images/${CLOUDIMG_NAME}.qcow2

    if maybe_verify_image "$IMAGE_FILE" "$CLOUDIMG_PATH"; then
        CLOUDIMG_FORMAT=$(qemu-img info --output=json "$IMAGE_FILE" |
            jq -r .format)
        lk_tty_print "Installing verified image to" "${CLOUDIMG_PATH%/*}"
        if [[ $CLOUDIMG_FORMAT != qcow2 ]]; then
            lk_sudo qemu-img convert -pO qcow2 "$IMAGE_FILE" "$CLOUDIMG_PATH"
        else
            lk_sudo cp "$IMAGE_FILE" "$CLOUDIMG_PATH"
        fi
        lk_sudo touch -r "$IMAGE_FILE" "$CLOUDIMG_PATH"
        lk_sudo chmod 444 "$CLOUDIMG_PATH"
        lk_tty_success "Backing file installed successfully"
        lk_tty_print
    fi

    if [[ -n ${KERNEL_URL:+1} ]]; then
        cd "$LK_BASE/var/cache/lk-platform/cloud-image-kernels"

        download_image "$KERNEL_URL" "${KERNEL_SHA_URLS[@]}"
        KERNEL_FILE=$IMAGE_FILE
        KERNEL_PATH=$POOL_ROOT/cloud-image-kernels/${KERNEL_FILE%.*}-$(lk_file_modified "$KERNEL_FILE")
        KERNEL_VERIFIED=1
        maybe_verify_image "$KERNEL_FILE" "$KERNEL_PATH" || KERNEL_VERIFIED=0

        INITRD_VERIFIED=1
        unset INITRD_PATH
        if [[ -n ${INITRD_URL:+1} ]]; then
            download_image "$INITRD_URL" "${INITRD_SHA_URLS[@]}"
            INITRD_FILE=$IMAGE_FILE
            INITRD_PATH=$POOL_ROOT/cloud-image-kernels/${INITRD_FILE%.*}-$(lk_file_modified "$KERNEL_FILE")
            maybe_verify_image "$INITRD_FILE" "$INITRD_PATH" || INITRD_VERIFIED=0
        fi

        if ((KERNEL_VERIFIED && INITRD_VERIFIED)); then
            lk_sudo cp "$KERNEL_FILE" "$KERNEL_PATH"
            lk_sudo touch -r "$KERNEL_FILE" "$KERNEL_PATH"
            if [[ -n ${INITRD_URL:+1} ]]; then
                lk_sudo cp "$INITRD_FILE" "$INITRD_PATH"
                lk_sudo touch -r "$INITRD_FILE" "$INITRD_PATH"
            fi
            lk_sudo chmod 444 "$KERNEL_PATH" ${INITRD_PATH+"$INITRD_PATH"}
        fi
    fi

    IMAGE_BASENAME=$VM_HOSTNAME-$CLOUDIMG_NAME
    DISK_PATH=$POOL_ROOT/$IMAGE_BASENAME.qcow2
    NOCLOUD_PATH=$POOL_ROOT/$IMAGE_BASENAME-cloud-init.qcow2
    if [[ -e $DISK_PATH ]]; then
        lk_tty_error "Disk image already exists:" "$DISK_PATH"
        lk_is_true FORCE_DELETE ||
            LK_FORCE_INPUT=Y \
                lk_tty_yn "Destroy the existing image and start over?" N ||
            lk_die ""
    fi

    # add_json [-j JQ_OPERATOR] VAR [JQ_ARG...] JQ_OBJECT
    function add_json() {
        local JQ='.+='
        [[ ${1-} != -j ]] || { JQ=$2 && shift 2; }
        local -n JSON=$1
        JSON=$(jq "${@:2:$#-2}" "$JQ${*: -1}" <<<"$JSON")
    }

    function add_runcmd() {
        RUNCMD=$(jq --arg sh "$1" '.+=[
  ["bash", "-c", $sh]
]' <<<"$RUNCMD")
    }

    function add_write_files() {
        WRITE_FILES=$(jq --arg path "$1" --arg content "$2" '.+=[{
  "path": $path,
  "content": $content
}]' <<<"$WRITE_FILES")
    }

    NETWORK_CONFIG="{}"
    USER_DATA="{}"
    META_DATA="{}"
    RUNCMD="[]"
    WRITE_FILES="[]"
    VIRT_OPTIONS=()
    QEMU_COMMANDLINE=()

    [[ -z ${KERNEL_URL:+1} ]] || {
        unset IFS
        VIRT_OPTIONS+=(
            --boot
            "uefi,kernel=$KERNEL_PATH${INITRD_PATH+,initrd=$INITRD_PATH}${KERNEL_ARGS+,kernel_args=${KERNEL_ARGS[*]}}"
        )
    }
    [[ -z ${QEMU_MACHINE:+1} ]] ||
        VIRT_OPTIONS+=(--machine "$QEMU_MACHINE")
    [[ $IMAGE_ARCH != arm64 ]] ||
        VIRT_OPTIONS+=(--cpu cortex-a57)
    ! lk_system_is_macos || VIRT_OPTIONS+=(
        --xml ./devices/emulator="$LK_BASE/share/qemu/qemu-system-hvf"
    )

    add_json NETWORK_CONFIG --arg mac "$VM_MAC_ADDRESS" '{
  "version": 1,
  "config": [{
    "type": "physical",
    "name": "eth0",
    "mac_address": $mac,
    "subnets": [{
      "type": "dhcp"
    }]
  }]
}'

    if [[ -n $VM_IPV4_CIDR ]]; then
        add_json -j '.config[].subnets=' NETWORK_CONFIG \
            --arg cidr "$VM_IPV4_CIDR" \
            --arg gw "$VM_IPV4_GATEWAY" '[{
  "type": "static",
  "address": $cidr,
  "gateway": $gw,
  "dns_nameservers": [
    $gw
  ]
}]'
    fi

    FSTAB=()
    MOUNT_DIRS=()
    [[ -z $VM_FILESYSTEM_MAPS ]] || {
        IFS="|"
        FILESYSTEMS=($VM_FILESYSTEM_MAPS)
        for FILESYSTEM in "${FILESYSTEMS[@]}"; do
            IFS=,
            FILESYSTEM_DIRS=($FILESYSTEM)
            [[ ${#FILESYSTEM_DIRS[@]} -ge 2 ]] ||
                lk_die "invalid filesystem map: $FILESYSTEM"
            [[ -d ${FILESYSTEM_DIRS[0]} ]] ||
                lk_die "directory not found: ${FILESYSTEM_DIRS[0]}"
            SOURCE_DIR=${FILESYSTEM_DIRS[0]}
            MOUNT_DIR=${FILESYSTEM_DIRS[1]}
            MOUNT_NAME=qemufs${#MOUNT_DIRS[@]}
            FILESYSTEM_DIRS[1]=$MOUNT_NAME
            VIRT_OPTIONS+=(--filesystem "$(lk_implode_arr "," FILESYSTEM_DIRS)")
            FSTAB+=("$MOUNT_NAME $MOUNT_DIR 9p defaults,nofail,trans=virtio,version=9p2000.L,posixacl,msize=262144,_netdev 0 0")
            MOUNT_DIRS+=("$MOUNT_DIR")
        done
        unset IFS
        add_runcmd "$(
            function _run() {
                install -d -m 00755 "$@" &&
                    printf '%s\n' "${FSTAB[@]}" >>/etc/fstab &&
                    printf '%s\n' "$@" | xargs -n1 mount
            }
            declare -f _run
            declare -p FSTAB
            lk_quote_args _run "${MOUNT_DIRS[@]}"
        )"
    }

    if [[ -z $STACKSCRIPT ]]; then
        add_json USER_DATA \
            --arg uid "$(id -u)" \
            --arg name "$(id -un)" \
            --arg gecos "$(lk_full_name)" \
            --argjson keys "$SSH_AUTHORIZED_KEYS" '{
  "ssh_pwauth": false,
  "users": [{
    "name": $name,
    "gecos": $gecos,
    "shell": "/bin/bash",
    "sudo": "ALL=(ALL) NOPASSWD:ALL",
    "ssh_authorized_keys": $keys
  }],
  "package_upgrade": true,
  "package_reboot_if_required": true
}'
    else
        add_json USER_DATA --argjson keys "$SSH_AUTHORIZED_KEYS" '{
  "ssh_pwauth": true,
  "disable_root": false,
  "ssh_authorized_keys": $keys
}'
        _STACKSCRIPT=$(gzip <"$STACKSCRIPT" | lk_base64 | tr -d '\n')
        add_runcmd "$(
            function _run() {
                install -m 00700 /dev/null /root/StackScript &&
                    fold -w 64 <<<"$1" | lk_base64 -d |
                    gunzip >/root/StackScript &&
                    export "${@:2}"
                /root/StackScript </dev/null
            }
            declare -f lk_has lk_base64 _run
            lk_quote_args _run "$_STACKSCRIPT" "${SS_FIELDS[@]}"
        )"
    fi

    add_json USER_DATA --arg uri "$UBUNTU_MIRROR" '{
  "apt": {
    "primary": [{
      "arches": [
        "default"
      ],
      "uri": $uri
    }]
  }
}'

    PACKAGES=(qemu-guest-agent)
    [[ -z $VM_PACKAGES ]] || {
        IFS=,
        PACKAGES+=($VM_PACKAGES)
        unset IFS
    }
    [[ ${#PACKAGES[@]} -eq 0 ]] ||
        add_json USER_DATA "$(lk_arr PACKAGES | sort -u | jq -Rn '{
  "packages": [inputs]
}')"

    # ubuntu-16.04-minimal leaves /etc/resolv.conf unconfigured if a static IP
    # is assigned (no resolvconf package?)
    [[ -z $VM_IPV4_CIDR ]] ||
        [[ $IMAGE_NAME != ubuntu-16.04-minimal ]] ||
        add_write_files /etc/resolv.conf "nameserver $VM_IPV4_GATEWAY"

    # cloud-init on ubuntu-14.04 doesn't recognise the "apt" schema
    [[ $IMAGE_NAME != ubuntu-14.04 ]] ||
        add_json USER_DATA --arg uri "$UBUNTU_MIRROR" '{
  "apt_mirror": $uri
}'

    [[ $RUNCMD == "[]" ]] ||
        add_json USER_DATA --argjson runcmd "$RUNCMD" '{
  "runcmd": $runcmd
}'

    [[ $WRITE_FILES == "[]" ]] ||
        add_json USER_DATA --argjson writeFiles "$WRITE_FILES" '{
  "write_files": $writeFiles
}'

    ! lk_is_true POWEROFF || add_json USER_DATA '{
  "power_state": {
    "mode": "poweroff"
  }
}'

    add_json META_DATA \
        --arg uuid "$(uuidgen)" \
        --arg hostname "$VM_HOSTNAME" '{
  "dsmode": "local",
  "instance-id": $uuid,
  "local-hostname": $hostname
}'

    # cloud-init on ubuntu-14.04 ignores the network-config file
    [[ -z $VM_IPV4_CIDR ]] ||
        [[ $IMAGE_NAME != ubuntu-14.04 ]] ||
        add_json META_DATA --arg interfaces "auto eth0
iface eth0 inet static
address $VM_IPV4_ADDRESS
netmask $VM_IPV4_MASK
gateway $VM_IPV4_GATEWAY
dns-nameservers $VM_IPV4_GATEWAY" '{
  "network-interfaces": $interfaces
}'

    NOCLOUD_META_DIR=$LK_BASE/var/cache/lk-platform/NoCloud/$(lk_hostname)-$VM_HOSTNAME-$(lk_date_ymdhms)
    install -d -m 00755 "$NOCLOUD_META_DIR"

    # Quote MAC address to work around issue where numeric addresses are parsed
    # incorrectly by cloud-init
    yq -y <<<"$NETWORK_CONFIG" |
        awk '$1=="mac_address:"&&$2~/^[0-9a-fA-F:]+$/{sub($2,"\"&\"")}{print}' \
            >"$NOCLOUD_META_DIR/network-config"
    { echo "#cloud-config" && yq -y <<<"$USER_DATA"; } \
        >"$NOCLOUD_META_DIR/user-data"
    yq -y <<<"$META_DATA" \
        >"$NOCLOUD_META_DIR/meta-data"

    if lk_tty_yn "Customise cloud-init data source?" N -t 10; then
        ! OPEN=$(lk_runnable xdg-open open) ||
            "$OPEN" "$NOCLOUD_META_DIR" || true
        lk_tty_pause "Press return to continue after making changes in $NOCLOUD_META_DIR . . . "
    fi

    FILE=$(lk_mktemp)
    lk_delete_on_exit "$FILE"
    # If possible, create a vfat data source rather than a read-only ISO
    # https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html
    if lk_has mcopy; then
        # 128 x 1024 = 128KiB
        dd if=/dev/null of="$FILE" bs=1024 seek=128 status=none
        # "cidata" must be lowercase for Ubuntu 14.04
        mkfs.vfat -n cidata "$FILE" &>/dev/null
        mcopy -i "$FILE" \
            "$NOCLOUD_META_DIR"/{network-config,user-data,meta-data} ::
    else
        mkisofs -output "$FILE" -volid cidata -joliet -rock \
            "$NOCLOUD_META_DIR"/{network-config,user-data,meta-data}
    fi
    lk_sudo install -m 00644 /dev/null "$NOCLOUD_PATH"
    lk_sudo qemu-img convert -O qcow2 "$FILE" "$NOCLOUD_PATH"

    lk_tty_print "Creating virtual machine"
    lk_tty_run_detail lk_sudo qemu-img create -q \
        -f "qcow2" \
        -b "$CLOUDIMG_PATH" \
        -F "qcow2" \
        "$DISK_PATH"
    lk_tty_run_detail lk_sudo qemu-img resize -q \
        -f "qcow2" \
        "$DISK_PATH" \
        "$VM_DISK_SIZE" || lk_die ""

    VM_NETWORK_TYPE=${VM_NETWORK%%=*}
    if [[ $VM_NETWORK_TYPE == "$VM_NETWORK" ]]; then
        VM_NETWORK_TYPE=network
    else
        VM_NETWORK=${VM_NETWORK#*=}
    fi

    case "$VM_NETWORK_TYPE" in
    user)
        VIRT_OPTIONS+=(--network none)
        IFS=
        QEMU_COMMANDLINE+=(
            -netdev "user,id=lknet0${HOSTFWD[*]+${HOSTFWD[*]/#/,hostfwd=}}"
            -device virtio-net-pci,netdev=lknet0,mac="$VM_MAC_ADDRESS"
        )
        unset IFS
        ;;
    *)
        VIRT_OPTIONS+=(
            --network
            "$VM_NETWORK_TYPE=$VM_NETWORK,mac=$VM_MAC_ADDRESS,model=virtio"
        )
        ;;
    esac

    if [[ ${#QEMU_COMMANDLINE[@]} -gt 0 ]]; then
        unset IFS
        VIRT_OPTIONS+=(--qemu-commandline="${QEMU_COMMANDLINE[*]}")
    fi

    VIRT_TYPE=$(IFS= &&
        lk_sudo virsh --connect "$LIBVIRT_URI" capabilities |
        xq --arg arch "$QEMU_ARCH" \
            '.capabilities.guest[].arch|select(.["@name"] == $arch)' |
            lk_jq -r 'include "core"; .domain | to_array[]["@type"]' |
            grep -Fxv qemu ||
        { [[ ${PIPESTATUS[*]} =~ ^0+1$ ]] && echo qemu; })

    lk_mktemp_with FILE lk_tty_run_detail lk_sudo virt-install \
        --connect "$LIBVIRT_URI" \
        --name "$VM_HOSTNAME" \
        --memory "$VM_MEMORY" \
        --vcpus "$VM_CPUS" \
        --import \
        --os-variant "$OS_VARIANT" \
        --disk "$DISK_PATH",bus=virtio \
        --disk "$NOCLOUD_PATH",bus=virtio \
        --graphics none \
        --tpm none \
        --rng /dev/urandom \
        ${VIRT_OPTIONS+"${VIRT_OPTIONS[@]}"} \
        --virt-type "$VIRT_TYPE" \
        --print-xml
    lk_tty_run_detail lk_sudo virsh --connect "$LIBVIRT_URI" \
        define "$FILE" >/dev/null
    for i in $(
        [[ ${#METADATA[@]} -eq 0 ]] ||
            seq 0 3 $((${#METADATA[@]} - 1))
    ); do
        lk_tty_run_detail lk_sudo virsh --connect "$LIBVIRT_URI" \
            metadata "$VM_HOSTNAME" "${METADATA[@]:i:3}" >/dev/null
    done
    lk_tty_run_detail lk_sudo virsh --connect "$LIBVIRT_URI" \
        start "$VM_HOSTNAME" --console

    exit
}
