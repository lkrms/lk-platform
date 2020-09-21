#!/usr/bin/env -S jq -rf
#
# httpd_get_ssl_directives.jq OPTIONS
#
# Convert Mozilla's server-side TLS recommendations to Apache directives
#
# Options:
#
#   --arg config <modern|intermediate|old>          (required)
#
# Example:
#
#     curl -fs "https://ssl-config.mozilla.org/guidelines/latest.json" |
#         jq --arg config intermediate -rf \
#             "$LK_BASE/lib/jq/httpd_get_ssl_directives.jq"
#
# See: https://wiki.mozilla.org/Security/Server_Side_TLS

def maybe_add (checkFor; otherwiseAdd):
  [checkFor, otherwiseAdd] as [$c, $a] |
    if [ .[] | select(. == $c) ] | length > 0 then "" else " " + $a end;

.configurations[$config] | {
  "SSLProtocol": .tls_versions | ("all" +
    maybe_add("SSLv2"; "-SSLv2") +
    maybe_add("SSLv3"; "-SSLv3") +
    maybe_add("TLSv1"; "-TLSv1") +
    maybe_add("TLSv1.1"; "-TLSv1.1") +
    maybe_add("TLSv1.2"; "-TLSv1.2") +
    maybe_add("TLSv1.3"; "-TLSv1.3")),
  "SSLCipherSuite": (.ciphersuites + .ciphers.openssl) | join(":"),
  "SSLHonorCipherOrder": (
    if .server_preferred_order then
      "on"
    else
      "off"
    end
  ) } | "<IfModule mod_ssl.c>
    SSLProtocol \(.SSLProtocol)
    SSLCipherSuite \(.SSLCipherSuite):!aNULL:!eNULL:!EXP
    SSLHonorCipherOrder \(.SSLHonorCipherOrder)
    SSLSessionTickets off
    SSLUseStapling on
    SSLStaplingCache \"shmcb:logs/ssl_stapling(32768)\"
    SSLOptions +StrictRequire
</IfModule>"
