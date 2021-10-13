# lk-platform

## Configuration

Settings are loaded in the following order, with later values overriding earlier
ones. If `lk-platform.conf` exists, it is expected to contain a series of shell
variable assignments compatible with Bash and POSIX `sh`.

1. `$LK_BASE/etc/lk-platform/lk-platform.conf`
2. `~/.config/lk-platform/lk-platform.conf`
3. Environment variables

### Global settings

- `LK_ACCEPT_OUTPUT_HOSTS`
- `LK_ADD_TO_PATH`
- `LK_ADD_TO_PATH_FIRST`
- `LK_ADMIN_EMAIL`
- `LK_APT_DEFAULT_MIRROR`
- `LK_APT_DEFAULT_SECURITY_MIRROR`
- `LK_ARCH_MIRROR`
- `LK_ARCH_REPOS`
- `LK_AUTO_BACKUP`
- `LK_AUTO_BACKUP_SCHEDULE`
- `LK_AUTO_REBOOT`
- `LK_AUTO_REBOOT_TIME`
- `LK_BACKUP_BASE_DIRS`
- `LK_BACKUP_MAIL`
- `LK_BACKUP_MAIL_ERROR_ONLY`
- `LK_BACKUP_MAIL_FROM`
- `LK_BACKUP_ROOT`
- `LK_BACKUP_TIMESTAMP`
- `LK_BIN_PATH`
- `LK_BRIDGE_INTERFACE`
- `LK_CERTBOT_OPTIONS`
- `LK_CERTBOT_PLUGIN`
- `LK_CLIP_LINES`
- `LK_CLOUDIMG_SESSION_ROOT`
- `LK_COMPLETION`
- `LK_CURL_OPTIONS`
- `LK_DEBUG`
- `LK_DIM_AFTER`
- `LK_DIM_TIME`
- `LK_DNS_SEARCH`
- `LK_DNS_SERVERS`
- `LK_DRY_RUN`
- `LK_EMAIL_BLACKHOLE`
- `LK_EXEC`
- `LK_FILE_BACKUP_MOVE`
- `LK_FILE_BACKUP_TAKE`
- `LK_FILE_KEEP_ORIGINAL`
- `LK_FILE_NO_DIFF`
- `LK_FORCE_INPUT`
- `LK_GIT_REF`
- `LK_GIT_REPOS`
- `LK_GRUB_CMDLINE`
- `LK_HASH_COMMAND`
- `LK_INNODB_BUFFER_SIZE`
- `LK_IPV4_ADDRESS`
- `LK_IPV4_GATEWAY`
- `LK_LETSENCRYPT_EMAIL`
- `LK_LETSENCRYPT_IGNORE_DNS`
- `LK_LINODE_SKIP_REGEX`
- `LK_LINODE_SSH_KEYS`
- `LK_LINODE_SSH_KEYS_FILE`
- `LK_MAIL_FROM`
- `LK_MEDIAINFO_FORMAT`
- `LK_MEDIAINFO_LABEL`
- `LK_MEDIAINFO_NO_VALUE`
- `LK_MEMCACHED_MEMORY_LIMIT`
- `LK_MYSQL_ELEVATE`
- `LK_MYSQL_ELEVATE_USER`
- `LK_MYSQL_HOST`
- `LK_MYSQL_MAX_CONNECTIONS`
- `LK_MY_CNF`
- `LK_MY_CNF_OPTIONS`
- `LK_NODE_FQDN`
- `LK_NODE_HOSTNAME`
- `LK_NODE_LANGUAGE`
- `LK_NODE_LOCALES`
- `LK_NODE_PACKAGES`
- `LK_NODE_SERVICES`
- `LK_NODE_TIMEZONE`
- `LK_NO_INPUT`
- `LK_NO_LOG`
- `LK_NTP_SERVER`
- `LK_OPCACHE_MEMORY_CONSUMPTION`
- `LK_OPENCONNECT_PROTOCOL`
- `LK_OWASP_CRS_BRANCH`
- `LK_PACKAGES_FILE`
- `LK_PATH_PREFIX`
- `LK_PHP_ADMIN_SETTINGS`
- `LK_PHP_SETTINGS`
- `LK_PLATFORM_BRANCH`
- `LK_PROMPT`
- `LK_REJECT_OUTPUT`
- `LK_SAMBA_WORKGROUP`
- `LK_SFTP_ONLY_GROUP`
- `LK_SITE_DISABLE_HTTPS`
- `LK_SITE_DISABLE_WWW`
- `LK_SITE_ENABLE`
- `LK_SITE_ENABLE_STAGING`
- `LK_SITE_PHP_FPM_MAX_CHILDREN`
- `LK_SITE_PHP_FPM_TIMEOUT`
- `LK_SMTP_RELAY`
- `LK_SNAPSHOT_DAILY_MAX_AGE`
- `LK_SNAPSHOT_FAILED_MAX_AGE`
- `LK_SNAPSHOT_HOURLY_MAX_AGE`
- `LK_SNAPSHOT_WEEKLY_MAX_AGE`
- `LK_SSH_HOME`
- `LK_SSH_JUMP_HOST`
- `LK_SSH_JUMP_KEY`
- `LK_SSH_JUMP_USER`
- `LK_SSH_PREFIX`
- `LK_SSH_PRIORITY`
- `LK_SSH_TRUSTED_ONLY`
- `LK_SSH_TRUSTED_PORT`
- `LK_SSL_CA`
- `LK_SSL_CA_KEY`
- `LK_STACKSCRIPT_EXPORT_DEFAULT`
- `LK_SUDO`
- `LK_TRUSTED_IP_ADDRESSES`
- `LK_TTY_NO_COLOUR`
- `LK_UBUNTU_CLOUDIMG_HOST`
- `LK_UBUNTU_MIRROR`
- `LK_UBUNTU_PORTS_MIRROR`
- `LK_UPGRADE_EMAIL`
- `LK_VERBOSE`
- `LK_WIFI_REGDOM`
- `LK_WP_FLUSH`
- `LK_WP_MODE_DIR`
- `LK_WP_MODE_FILE`
- `LK_WP_MODE_WRITABLE_DIR`
- `LK_WP_MODE_WRITABLE_FILE`
- `LK_WP_OLD_URL`
- `LK_WP_REAPPLY`
- `LK_WP_REPLACE`
- `LK_WP_REPLACE_WITHOUT_SCHEME`
- `LK_WP_SYNC_EXCLUDE`
- `LK_WP_SYNC_KEEP_LOCAL`

#### Check code for settings used

To generate the list above, run the following in `$LK_BASE`:

```bash
lk_bash_find_scripts -print0 |
    xargs -0 gnu_grep -Pho '((?<=\$\{)|(?<=lk_is_true )|(?<=lk_is_false ))LK_[a-zA-Z0-9_]+\b(?!(\[[^]]+\])?[#%}])' |
    sort -u |
    sed -Ee '/^LK_(.+_(UPDATED|DECLINED|NO_CHANGE)|BASE|USAGE|VERSION|Z|ADMIN_USERS|HOST_.+|MYSQL_(USERNAME|PASSWORD)|SHUTDOWN_ACTION)$/d' -e 's/.*/- `&`/'
```

### Site settings

Each site on a [hosting server](bin/lk-provision-hosting.sh) is configured in
`$LK_BASE/etc/sites/DOMAIN.conf`, where `DOMAIN` is the site's primary domain.
Available settings:

- **`SITE_ALIASES`** (comma-separated secondary domains; do not use for
  `www.DOMAIN`)
- **`SITE_ROOT`** (`/srv/www/USER` or `/srv/www/USER/CHILD`)
- **`SITE_ENABLE`** (`Y` or `N`; default: `Y`)
- **`SITE_ORDER`** (default: `-1`)
- **`SITE_DISABLE_WWW`** (`Y` or `N`; default: `N`)
- **`SITE_DISABLE_HTTPS`** (`Y` or `N`; default: `N`)
- **`SITE_ENABLE_STAGING`** (`Y` or `N`; default: `N`)
- **`SITE_PHP_FPM_POOL`** (default: `USER`)
- **`SITE_PHP_FPM_USER`** (usually `www-data` or `USER`; default: `www-data` if
  `USER` is an administrator, otherwise `USER`)
- **`SITE_PHP_FPM_MAX_CHILDREN`**
- **`SITE_PHP_FPM_TIMEOUT`** (in seconds; default: `300`)
- **`SITE_PHP_FPM_OPCACHE_SIZE`** (in MiB; default: `128`)
- **`SITE_PHP_FPM_ADMIN_SETTINGS`**
- **`SITE_PHP_FPM_SETTINGS`**
- **`SITE_PHP_FPM_ENV`**
- **`SITE_PHP_VERSION`** (e.g. `7.0`, `7.2`, `7.4`; default: *system-dependent*)

## Conventions

### Parameter expansion

Bash 3.2 expands `"${@:2}"` to the equivalent of `"$(IFS=" "; echo "${*:2}")"`
unless `IFS` contains a space. The following workaround should generally be
used:

```bash
local IFS
unset IFS
some_command "${@:2}"
```

Or, if changing IFS could have side-effects:

```bash
local ARG=$1
shift
some_command "$@"
```

### File descriptors

`lk_fd_next` is used if possible, otherwise the following conventions are used:

- 3: `_LK_FD`: output from `lk_tty_*` functions
- 4: `BASH_XTRACEFD`
- 5: \<reserved by Bash\>
- 6: original stdout
- 7: original stderr
- 8: FIFO
- 9: lock file (passed to `flock -n`)
