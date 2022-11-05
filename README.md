# lk-platform

## Configuration

Settings are loaded in the following order, with later values overriding earlier
ones. If `lk-platform.conf` exists, it is expected to contain a series of shell
variable assignments compatible with Bash and POSIX `sh`.

1. `<LK_BASE>/etc/lk-platform/lk-platform.conf`
2. `~/.config/lk-platform/lk-platform.conf`
3. Environment variables

### Global settings

- `LK_ACCEPT_OUTPUT_HOSTS`
- `LK_ADD_TO_PATH`
- `LK_ADD_TO_PATH_FIRST`
- `LK_ADMIN_EMAIL`
- `LK_APT_DEFAULT_MIRROR`
- `LK_APT_DEFAULT_SECURITY_MIRROR`
- `LK_ARCH_AUR_CHROOT_DIR`
- `LK_ARCH_AUR_REPO_NAME`
- `LK_ARCH_MIRROR`
- `LK_ARCH_REPOS`
- `LK_AUTO_BACKUP`
- `LK_AUTO_BACKUP_SCHEDULE`
- `LK_AUTO_REBOOT`
- `LK_AUTO_REBOOT_TIME`
- `LK_AWS_PROFILE`
- `LK_BACKUP_BASE_DIRS`
- `LK_BACKUP_MAIL`
- `LK_BACKUP_MAIL_ERROR_ONLY`
- `LK_BACKUP_MAIL_FROM`
- `LK_BACKUP_ROOT`
- `LK_BACKUP_TIMESTAMP`
- `LK_BIN_DIR`
- `LK_BRIDGE_INTERFACE`
- `LK_CERTBOT_EMAIL`
- `LK_CERTBOT_INSTALLED`
- `LK_CERTBOT_OPTIONS`
- `LK_CLIP_LINES`
- `LK_CLOUDIMG_DIRECT_KERNEL_BOOT`
- `LK_CLOUDIMG_SESSION_ROOT`
- `LK_COMPLETION`
- `LK_CURL_OPTIONS`
- `LK_DEBUG`
- `LK_DIM_AFTER`
- `LK_DIM_TIME`
- `LK_DNS_SEARCH`
- `LK_DNS_SERVERS`
- `LK_DRY_RUN`
- `LK_EMAIL_DESTINATION`
- `LK_EXEC`
- `LK_FEATURES`
- `LK_FILE_BACKUP_MOVE`
- `LK_FILE_BACKUP_TAKE`
- `LK_FILE_KEEP_ORIGINAL`
- `LK_FILE_NO_DIFF`
- `LK_FORCE_INPUT`
- `LK_GIT_REF`
- `LK_GIT_REPOS`
- `LK_GRUB_CMDLINE`
- `LK_HANDBRAKE_TARGET`
- `LK_HASH_COMMAND`
- `LK_INNODB_BUFFER_SIZE`
- `LK_IPV4_ADDRESS`
- `LK_IPV4_GATEWAY`
- `LK_LAUNCHPAD_PPA_MIRROR`
- `LK_LINODE_IGNORE_REGEX`
- `LK_LINODE_SSH_KEYS`
- `LK_LINODE_SSH_KEYS_FILE`
- `LK_LINODE_USER`
- `LK_MAIL_FROM`
- `LK_MEDIAINFO_FORMAT`
- `LK_MEDIAINFO_LABEL`
- `LK_MEDIAINFO_NO_VALUE`
- `LK_MEMCACHED_MEMORY_LIMIT`
- `LK_MY_CNF`
- `LK_MY_CNF_OPTIONS`
- `LK_MYSQL_ELEVATE`
- `LK_MYSQL_ELEVATE_USER`
- `LK_MYSQL_HOST`
- `LK_MYSQL_MAX_CONNECTIONS`
- `LK_NODE_FQDN`
- `LK_NODE_HOSTNAME`
- `LK_NODE_LANGUAGE`
- `LK_NODE_LOCALES`
- `LK_NODE_TIMEZONE`
- `LK_NO_INPUT`
- `LK_NO_STACK_TRACE`
- `LK_NOTE_DIR`
- `LK_NTP_SERVER`
- `LK_OPCACHE_MEMORY_CONSUMPTION`
- `LK_OPENCONNECT_PROTOCOL`
- `LK_OWASP_CRS_BRANCH`
- `LK_PACKAGES`
- `LK_PACKAGES_FILE`
- `LK_PATH_PREFIX`
- `LK_PHP_ADMIN_SETTINGS`
- `LK_PHP_DEFAULT_VERSION`
- `LK_PHP_SETTINGS`
- `LK_PHP_VERSIONS`
- `LK_PLATFORM_BRANCH`
- `LK_PROMPT`
- `LK_PROMPT_TAG`
- `LK_REJECT_OUTPUT`
- `LK_SAMBA_WORKGROUP`
- `LK_SFTP_ONLY_GROUP`
- `LK_SITE_DISABLE_HTTPS`
- `LK_SITE_DISABLE_WWW`
- `LK_SITE_ENABLE`
- `LK_SITE_ENABLE_STAGING`
- `LK_SITE_PHP_FPM_MAX_CHILDREN`
- `LK_SITE_PHP_FPM_MAX_REQUESTS`
- `LK_SITE_PHP_FPM_MEMORY_LIMIT`
- `LK_SITE_PHP_FPM_TIMEOUT`
- `LK_SITE_SMTP_CREDENTIALS`
- `LK_SITE_SMTP_RELAY`
- `LK_SITE_SMTP_SENDERS`
- `LK_SMTP_CREDENTIALS`
- `LK_SMTP_RELAY`
- `LK_SMTP_SENDERS`
- `LK_SMTP_TRANSPORT_MAPS`
- `LK_SMTP_UNKNOWN_SENDER_TRANSPORT`
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
- `LK_SUDO_ON_FAIL`
- `LK_TRUSTED_IP_ADDRESSES`
- `LK_TTY_HOSTNAME`
- `LK_TTY_NO_COLOUR`
- `LK_UBUNTU_CLOUDIMG_HOST`
- `LK_UBUNTU_CLOUDIMG_SHA_URL`
- `LK_UBUNTU_MIRROR`
- `LK_UBUNTU_PORTS_MIRROR`
- `LK_UPGRADE_EMAIL`
- `LK_VERBOSE`
- `LK_WIFI_REGDOM`
- `LK_WP_APPLY`
- `LK_WP_FLUSH`
- `LK_WP_MIGRATE`
- `LK_WP_MODE_DIR`
- `LK_WP_MODE_FILE`
- `LK_WP_MODE_WRITABLE_DIR`
- `LK_WP_MODE_WRITABLE_FILE`
- `LK_WP_OLD_URL`
- `LK_WP_REPLACE`
- `LK_WP_REPLACE_WITHOUT_SCHEME`
- `LK_WP_SYNC_EXCLUDE`
- `LK_WP_SYNC_KEEP_LOCAL`

#### Check code for settings used

To generate the list above, run the following in `<LK_BASE>`:

```bash
lk_find_shell_scripts -print0 |
    xargs -0 gnu_grep -Pho '((?<=\$\{)|(?<=lk_is_true )|(?<=lk_is_false )|(?<=lk_true )|(?<=lk_false ))LK_[a-zA-Z0-9_]+\b(?!(\[[^]]+\])?[#%}])' |
    sort -u |
    sed -Ee '/^LK_(.+_(UPDATED|DECLINED|NO_CHANGE)|BASE|USAGE|VERSION|Z|ADMIN_USERS|HOST_.+|MYSQL_(USERNAME|PASSWORD)|SHUTDOWN_ACTION|BOLD|DIM|RESET)$/d' -e 's/.*/- `&`/'
```

### Site settings

Each site on a [hosting server](bin/lk-provision-hosting.sh) is configured in
`<LK_BASE>/etc/lk-platform/sites/<DOMAIN>.conf`, where `<DOMAIN>` is the site's
primary domain. Available settings:

- **`SITE_ALIASES`** (comma-separated secondary domains; do not use for
  `www.DOMAIN`)
- **`SITE_ROOT`** (either `/srv/www/<USER>` or `/srv/www/<USER>/<CHILD>`)
- **`SITE_ENABLE`** (`Y` or `N`; default: `Y`)
- **`SITE_ORDER`** (default: `-1`)
- **`SITE_DISABLE_WWW`** (`Y` or `N`; default: `N`)
- **`SITE_DISABLE_HTTPS`** (`Y` or `N`; default: `N`)
- **`SITE_ENABLE_STAGING`** (`Y` or `N`; default: `N`)
- **`SITE_CANONICAL_DOMAIN`** (`<FQDN>`; if set, requests for other domains will
  be redirected)
- **`SITE_SSL_CERT_FILE`** (obtained automatically unless `SITE_DISABLE_HTTPS`
  is set)
- **`SITE_SSL_KEY_FILE`**
- **`SITE_SSL_CHAIN_FILE`** (only required if `SITE_SSL_CERT_FILE` doesn't
  contain a valid certificate chain)
- **`SITE_PHP_FPM_POOL`** (default: `<USER>`)
- **`SITE_PHP_FPM_USER`** (usually `www-data` or `<USER>`; default: `www-data`
  if `<USER>` is an administrator, otherwise `<USER>`)
- **`SITE_PHP_FPM_MAX_CHILDREN`** (default: `30`)
- **`SITE_PHP_FPM_MEMORY_LIMIT`** (in MiB; default: `80`)
- **`SITE_PHP_FPM_MAX_REQUESTS`** (default: `10000`)
- **`SITE_PHP_FPM_TIMEOUT`** (in seconds; default: `300`)
- **`SITE_PHP_FPM_OPCACHE_SIZE`** (in MiB; default: `128`)
- **`SITE_PHP_FPM_ADMIN_SETTINGS`**
- **`SITE_PHP_FPM_SETTINGS`**
- **`SITE_PHP_FPM_ENV`**
- **`SITE_PHP_VERSION`** (`5.6`, `7.0`, `7.1`, `7.2`, `7.3`, `7.4`, `8.0`,
  `8.1`, or `-1` to disable; default: `LK_PHP_DEFAULT_VERSION` if set, otherwise
  *system-dependent*)
- **`SITE_DOWNSTREAM_FROM`** (`cloudflare` or
  `<HTTP_HEADER>:<PROXY_CIDR>[,<PROXY_CIDR>...]`, e.g.
  `X-Forwarded-For:172.105.171.229,103.31.4.0/22`)
- **`SITE_DOWNSTREAM_FORCE`** (`Y` or `N`; default: `N`; if set, requests are
  rejected except from an upstream proxy)

#### Internal variables

The following variables are used by various `lk_hosting_*` functions. They can't
be set via `<DOMAIN>.conf`. Don't change them unless you know exactly what
you're doing.

1. Set by `_lk_hosting_site_assign_settings`:
   - **`_SITE_DOMAIN`**
   - **`_SITE_FILE`**
2. Set by `_lk_hosting_site_check_root`:
   - **`_SITE_INODE`**
   - **`_SITE_USER`**
   - **`_SITE_GROUP`**
   - **`_SITE_CHILD`**
   - **`_SITE_IS_CHILD`** (`Y` or `N`)
   - **`_SITE_NAME`**
3. Set by `_lk_hosting_site_load_settings`:
   - **`_SITE_ORDER`**
   - **`_SITE_PHP_FPM_POOL`**
   - **`_SITE_PHP_FPM_USER`**
   - **`_SITE_PHP_FPM_MAX_CHILDREN`**
   - **`_SITE_PHP_FPM_MEMORY_LIMIT`**
   - **`_SITE_PHP_FPM_MAX_REQUESTS`**
   - **`_SITE_PHP_FPM_TIMEOUT`**
   - **`_SITE_PHP_FPM_OPCACHE_SIZE`**
   - **`_SITE_PHP_VERSION`**
   - **`_SITE_SMTP_RELAY`**
   - **`_SITE_SMTP_CREDENTIALS`**
   - **`_SITE_SMTP_SENDERS`**
4. Set by `_lk_hosting_site_load_dynamic_settings`:
   - **`_SITE_ROOT_IS_SHARED`** (`Y` if multiple sites are served from the same
     `SITE_ROOT`, otherwise `N`)
   - **`_SITE_PHP_FPM_PM`** (`static`, `ondemand` or `dynamic`)

## Conventions

### Command usage template

There must be at least two spaces between a command-line option and its
definition.

It isn't mandatory to use a full stop (period) at the end of each definition,
but all definitions must be consistent.

```
What the command does, in one or two lines.

Usage:
  ${0##*/} [options] <ARG>...
  ${0##*/} [options] --exclude <ARG>...

Options:
  -f, --flag            A setting that can be enabled.
  -v, --value=<VALUE>   A value that can be set.

Environment:
  ENV_VARIABLE    Something different happens if this variable is in the
                  environment.

A further explanation of the command, possibly including example invocations.
```

### Parameter expansion

Bash 3.2 expands `"${@:2}"` to the equivalent of `"$(IFS=" "; echo "${*:2}")"`
unless `IFS` contains a space. The following workaround should generally be
used:

```bash
local IFS=$' \t\n'
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
