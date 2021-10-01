BEGIN {
    FS = "[[:blank:]=]+"
    S = "[[:blank:]]"
    NS = "[^[:blank:]]"
    php_setting_regex = "\\[[^]]+\\]" S "*=" S "*"
    php_admin_regex = "^" S "*php_admin_(flag|value)" php_setting_regex
    php_regex = "^" S "*php_(flag|value)" php_setting_regex
    env_regex = "^" S "*env" php_setting_regex
    disable_https = "Y"
    disable_www = "Y"
    enable_staging = "N"
}

function quote(str, _q, _q_count, _arr, _i, _out) {
    # \47 = single quote
    _q = "\47"
    _q_count = split(str, _arr, _q)
    for (_i in _arr) {
        _out = _out _q _arr[_i] _q (_i < _q_count ? "\\" _q : "")
    }
    return _out
}

function join_keys(sep, arr, _k, _i, _out) {
    for (_k in arr) {
        if (_i++)
            _out = _out sep
        _out = _out _k
    }
    return _out
}

function join_settings(sep, arr, _k, _i, _out) {
    for (_k in arr) {
        if (index(arr[_k], sep)) {
            print "hosting-get-site-settings.awk: cannot serialize '" arr[_k] "' in " FILENAME > "/dev/stderr"
            e = 1
            continue
        }
        if (_i++)
            _out = _out sep
        _out = _out _k "=" arr[_k]
    }
    return _out
}

function apache_value(_) {
    _ = $0
    sub("^" S "*" NS "+" S "+", "", _)
    sub(S "*$", "", _)
    return _
}

function php_value(_) {
    _ = $0
    sub("^[^=]+=" S "*", "", _)
    sub(S "*$", "", _)
    return _
}

function php_setting_name(_) {
    _ = $1
    sub("^[^[]+\\[", "", _)
    sub("\\].*$", "", _)
    return _
}

function php_setting_value(_) {
    _ = $0
    sub("^[^[]+\\[[^]]+\\]" S "*=" S "*", "", _)
    sub(S "*$", "", _)
    return _
}

function delete_php_setting(name) {
    delete php_admin_settings[name]
    delete php_settings[name]
}

function get_php_setting(name, _) {
    if (php_admin_settings[name]) {
        _ = php_admin_settings[name];
    } else {
        _ = php_settings[name];
    }
    delete_php_setting(name)
    return _
}

function maybe_print(name, value) {
    if (value) {
        printf("%s=%s\n", name, quote(value))
    }
}

{
    is_apache = 1
    is_php = 1
    sub("^" S "+", "")
}

FILENAME ~ "^/etc/apache2/sites-(available|enabled)/" {
    is_php = 0
}

FILENAME ~ "^/etc/php/[^/]+/fpm/pool\\.d/" {
    is_apache = 0
}

is_apache && tolower($1) == "servername" {
    $2 = tolower($2)
    domains[$2] = 1
    sub("^www\\.", "", $2)
    domain = $2
}

is_apache && tolower($1) == "serveralias" {
    $2 = tolower($2)
    domains[$2] = 1
}

is_apache && tolower($1) == "sslcertificatefile" {
    ssl_cert_file = apache_value()
}

is_apache && tolower($1) == "sslcertificatekeyfile" {
    ssl_key_file = apache_value()
}

is_apache && tolower($1) == "sslcertificatechainfile" {
    ssl_chain_file = apache_value()
}

is_apache && tolower($1) == "use" && tolower($2) == "staging" {
    enable_staging = "Y"
}

function check_downstream() {
    downstream_force = tolower($2) ~ "^require" ? "Y" : "N"
}

is_apache && tolower($1) == "use" && tolower($2) ~ "^(trust|require)proxy$" {
    gsub("\"", "")
    s = ""
    for (i = 3; i < NF; i++) {
        s = s (i > 3 ? "," : "") $i
    }
    if (s) {
        downstream_from = $NF ":" s
        check_downstream()
    }
}

is_apache && tolower($1) == "use" && tolower($2) ~ "^(trust|require)cloudflare$" {
    downstream_from = "cloudflare"
    check_downstream()
}

is_apache && tolower($1) == "use" && tolower($2) ~ /^phpfpmproxy[0-9]+$/ {
    sitename = $3
    timeout = $4
    $2 = tolower($2)
    sub("^phpfpmproxy", "", $2)
    phpversion = substr($2, 1, 1) "." substr($2, 2)
}

is_apache && tolower($1) == "use" && tolower($2) == "phpfpmproxy" {
    phpversion = $3
    poolname = $4
    sitename = $5
    customroot = $6
    timeout = $7
}

is_apache && tolower($1) == "use" && tolower($2) ~ /^phpfpmvirtualhost(ssl)?[0-9]*$/ {
    sitename = $3
    site_root = "/srv/www/" $3
    if (tolower($2) ~ /ssl/)
        disable_https = "N"
}

is_apache && tolower($1) == "use" && tolower($2) ~ /^phpfpmvirtualhost(ssl)?[0-9]*child[0-9]*$/ {
    sitename = $3
    childname = $4
    site_root = "/srv/www/" $3 "/" $4
    if (tolower($2) ~ /ssl/)
        disable_https = "N"
}

is_apache && tolower($1) == "sslengine" && tolower($2) == "on" {
    disable_https = "N"
}

is_php && $1 ~ "^\\[[^][]+\\]$" {
    gsub(/[][]/, "", $1)
    poolname = $1
}

is_php && $1 == "pm.max_children" {
    max_children = php_value()
}

is_php && $1 == "user" {
    fpm_user = php_value()
    if (fpm_user == "$pool")
        fpm_user = poolname
}

is_php && $1 == "request_terminate_timeout" {
    timeout = php_value()
}

is_php && $1 == "listen" {
    if (match($0, "[0-9]+\\.[0-9]+")) {
        phpversion = substr($0, RSTART, RLENGTH)
    }
}

is_php && $0 ~ php_admin_regex {
    php_admin_settings[php_setting_name()] = php_setting_value()
}

is_php && $0 ~ php_regex {
    php_settings[php_setting_name()] = php_setting_value()
}

is_php && $0 ~ env_regex {
    env[php_setting_name()] = php_setting_value()
}

END {
    if (!site_root) {
        if (sitename && childname) {
            site_root = "/srv/www/" sitename "/" childname
        } else if (sitename && customroot) {
            site_root = "/srv/www/" sitename customroot
        } else if (sitename) {
            site_root = "/srv/www/" sitename
        }
    }
    if (domain) {
        if (domains["www." domain] == 1) {
            disable_www = "N"
        }
        delete domains[domain]
        delete domains["www." domain]
    }
    opcache_size = get_php_setting("opcache.memory_consumption")
    delete_php_setting("opcache.file_cache")
    delete_php_setting("opcache.validate_permission")
    delete_php_setting("error_log")
    delete_php_setting("log_errors")
    delete_php_setting("display_errors")
    delete_php_setting("display_startup_errors")
    delete env["TMPDIR"]
    maybe_print("_SITE_DOMAIN", domain)
    maybe_print("SITE_ALIASES", join_keys(",", domains))
    maybe_print("SITE_ROOT", site_root)
    maybe_print("SITE_DISABLE_WWW", disable_www)
    maybe_print("SITE_DISABLE_HTTPS", disable_https)
    maybe_print("SITE_SSL_CERT_FILE", ssl_cert_file)
    maybe_print("SITE_SSL_KEY_FILE", ssl_key_file)
    maybe_print("SITE_SSL_CHAIN_FILE", ssl_chain_file)
    maybe_print("SITE_ENABLE_STAGING", enable_staging)
    maybe_print("SITE_DOWNSTREAM_FROM", downstream_from)
    maybe_print("SITE_DOWNSTREAM_FORCE", downstream_force)
    maybe_print("SITE_PHP_FPM_POOL", poolname)
    maybe_print("SITE_PHP_FPM_ADMIN_SETTINGS", join_settings(",", php_admin_settings))
    maybe_print("SITE_PHP_FPM_SETTINGS", join_settings(",", php_settings))
    maybe_print("SITE_PHP_FPM_ENV", join_settings(",", env))
    maybe_print("SITE_PHP_FPM_MAX_CHILDREN", max_children)
    maybe_print("SITE_PHP_FPM_USER", fpm_user)
    maybe_print("SITE_PHP_FPM_TIMEOUT", timeout)
    maybe_print("SITE_PHP_FPM_OPCACHE_SIZE", opcache_size)
    maybe_print("SITE_PHP_VERSION", phpversion)
    maybe_print("_SITE_CHILDNAME", childname)
    maybe_print("_SITE_CUSTOMROOT", customroot)
    maybe_print("_SITE_SITENAME", sitename)
    exit e
}
