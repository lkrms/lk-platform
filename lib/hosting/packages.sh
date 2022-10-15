#!/bin/bash

APT_PACKAGES=(
    #
    ubuntu-minimal

    # Services
    atop
    cron
    fail2ban
    ntp
    openssh-server
    postfix

    # Utilities
    apt
    apt-listchanges
    apticron
    bash
    bash-completion
    bc
    bsdmainutils
    bsdutils
    byobu
    ca-certificates
    certbot
    coreutils
    curl
    debconf
    debsums
    diffutils
    dnsutils
    dpkg
    file
    findutils
    gawk
    git
    grep
    gzip
    hostname
    htop
    icdiff
    iproute2
    iptables
    iptables-persistent
    iputils-ping
    iputils-tracepath
    #jc
    jq
    less
    libc-bin
    logrotate
    lsof
    mutt
    nano
    ncurses-bin
    net-tools
    netcat-openbsd
    openssh-client
    openssl
    passwd
    perl
    procps
    psmisc
    pv
    rdfind
    rsync
    s3cmd
    sed
    sqlite3
    sudo
    tar
    tcpdump
    telnet
    time
    tzdata
    unattended-upgrades
    unzip
    util-linux
    uuid-runtime
    vim
    wget
    whiptail
    xxhash

    #
    build-essential
    python3
    python3-dev
    python3-pip
    python3-setuptools
    python3-wheel

    #
    ${APT_PACKAGES[@]+"${APT_PACKAGES[@]}"}
)

APT_REMOVE=(
    #
    ${APT_REMOVE[@]+"${APT_REMOVE[@]}"}
)

function process_feature_packages() {
    if lk_feature_enabled "$1"; then
        APT_PACKAGES+=("${@:2}")
    else
        APT_REMOVE+=("${@:2}")
    fi
}

process_feature_packages apache2 \
    apache2 \
    libapache2-mod-qos \
    python3-certbot-apache

process_feature_packages php-fpm \
    php-apcu \
    php-apcu-bc \
    php-bcmath \
    php-cli \
    php-curl \
    php-fpm \
    php-gd \
    php-gettext \
    php-igbinary \
    php-imagick \
    php-imap \
    php-intl \
    php-json \
    php-ldap \
    php-mbstring \
    php-memcache \
    php-memcached \
    php-msgpack \
    php-mysql \
    php-opcache \
    php-pear \
    php-pspell \
    php-readline \
    php-redis \
    php-soap \
    php-sqlite3 \
    php-xml \
    php-xmlrpc \
    php-yaml \
    php-zip

process_feature_packages mariadb \
    mariadb-client \
    mariadb-server

process_feature_packages memcached \
    memcached
