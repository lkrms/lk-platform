#!/bin/bash

# Usage:
#   update-server.sh [options] <SSH_HOST>...
#
# Options:
#   --force-provision           Run provisioning script without revision change.
#   --upgrade                   Upgrade apt packages on each host.
#   --no-tls                    Skip TLS certificate checks.
#   --no-wordpress              Skip WordPress checks.
#   --no-test                   Skip site reachability test.
#   --set <SETTING> <VALUE>     }
#   --add <SETTING> <VALUE>     } Pass lk-platform settings changes to the
#   --remove <SETTING> <VALUE>  } provisioning script.
#   --unset <SETTING>           }
#
# Environment:
#   UPDATE_SERVER_BRANCH        Override 'main'.
#   UPDATE_SERVER_REPO          Override the default GitHub web URL.
#   UPDATE_SERVER_HOSTING_KEYS  Update the SSH keys used to authorise provider
#                               access to hosting accounts.
#
# Take the following actions on each <SSH_HOST>, creating an output log locally
# and in ~root/ on the remote system:
# 1. Ignore SIGHUP, SIGINT and SIGTERM to prevent, say, a dropped SSH connection
#    killing a long-running `apt-get` process.
# 2. Update or reset the lk-platform Git repository after stashing any
#    uncommitted changes.
# 3. Install icdiff for more readable log output.
# 4. Replace /etc/skel.<PREFIX>/.ssh/authorized_keys_* with the value of
#    UPDATE_SERVER_HOSTING_KEYS.
# 5. Run lk-provision-hosting.sh with the specified arguments (--set, etc).
# 6. Try to obtain Let's Encrypt TLS certificates for any public-facing sites
#    that don't have one.
# 7. Enable system cron on any WordPress sites that aren't using it.

lk_bin_depth=2 . lk-bash-load.sh || exit

{
  function keep-alive() {
    local OUT_FILE
    # To make the running script resistant to broken connections (SIGHUP),
    # Ctrl+C (SIGINT) and kill signals (SIGTERM):
    # 1. Copy stdout and stderr to FD 6 and FD 7
    # 2. Redirect stdout and stderr to OUT_FILE
    # 3. Redirect stdin from /dev/null
    # 4. Run `tail -f OUT_FILE` in the background to display the script's output
    #    on FD 6 without tying it to a possibly fragile TTY
    # 5. Ignore SIGHUP, SIGINT and SIGTERM (ignored signals cannot be trapped by
    #    child processes)
    OUT_FILE=$(mktemp -- \
      ~/update-server.sh-keep-alive.nohup.out.XXXXXXXXXX) &&
      echo "Logging output to $(hostname -s):$OUT_FILE" >&2 &&
      exec 6>&1 7>&2 8>"$OUT_FILE" &&
      exec >&8 2>&1 </dev/null || return
    tail -fn+1 "$OUT_FILE" >&6 2>&7 &
    trap "kill $!" EXIT
    trap "" SIGHUP SIGINT SIGTERM
  }

  # update-server BRANCH [--set SETTING]...
  function update-server() {
    function update-wp() {
      local CRONTAB DISABLE_WP_CRON
      cd "$1" &&
        . /opt/lk-platform/lib/bash/rc.sh || return
      [[ ! -e ~/.lk-archived ]] || {
        lk_tty_print "Not checking archived WordPress at" "$1"
        return
      }
      lk_tty_print "Checking WordPress at" "$1"
      if CRONTAB=$(crontab -l 2>/dev/null | grep -F "$(printf \
        ' -- wp_if_running --path=%q cron event run --due-now' "$1")" |
        grep -F _LK_LOG_FILE | grep -F WP_CLI_PHP) &&
        DISABLE_WP_CRON=$(lk_wp \
          config get DISABLE_WP_CRON --type=constant) &&
        lk_is_true DISABLE_WP_CRON; then
        ! lk_verbose 2 || {
          lk_tty_detail "WP-Cron appears to be configured correctly"
          lk_tty_detail "crontab command:" $'\n'"$CRONTAB"
        }
      else
        ! lk_verbose 2 ||
          lk_tty_detail "WP-Cron: valid job not found in crontab"
        lk_wp_enable_system_cron
      fi
    }

    set -uo pipefail

    export LC_ALL=C

    local INSTALL KEYS_FILE HEAD_FILE LAST_HEAD HEAD SH \
      CERT_LIST NO_CERT WP OWNER STATUS=0

    cd /opt/lk-platform 2>/dev/null ||
      cd /opt/*-platform ||
      return

    chown -c :adm . &&
      chmod -c 02775 . ||
      return

    { git config --system --get-all safe.directory || true; } |
      sed -E 's/\/+$//' |
      grep -Fx "$PWD" >/dev/null ||
      git config --system --add safe.directory "$PWD" ||
      return

    (IFS= && umask 002 &&
      # Remove every remote that isn't origin
      { git remote | grep -Fxv origin | tr '\n' '\0' |
        xargs -0 -n1 -r git remote remove ||
        [ "${PIPESTATUS[*]}" = 0100 ]; } &&
      # Add origin or update its URL
      if git remote | grep -Fx origin >/dev/null; then
        git config remote.origin.url | grep -Fx "$2" >/dev/null ||
          git remote set-url origin "$2"
      else
        git remote add origin "$2"
      fi &&
      # Retrieve latest commits from origin
      git fetch --tags --force origin &&
      git remote set-head origin --auto >/dev/null &&
      git remote prune origin &&
      # If target branch is 'main', reset origin/main to the most recent
      # annotated tag's commit
      if [[ $1 == main ]] &&
        TAG=$(git describe origin/main 2>/dev/null) &&
        REF=$(git rev-parse --verify --short "$TAG^{commit}"); then
        git update-ref refs/remotes/origin/main "$REF" &&
          echo "Updating lk-platform to $TAG ($REF)" >&2
      fi &&
      # Stash local changes
      if ! git stash --include-untracked; then
        git config user.name "$USER" &&
          git config user.email "$USER@$(hostname -f)" &&
          git stash --include-untracked
      fi &&
      BRANCHES=$(git for-each-ref --format="%(refname:short)" refs/heads |
        awk 'NR > 1 { printf(",%s", $0); next } { printf("%s", $0) }') &&
      if [[ ,$BRANCHES, == *,master,* ]] && [[ ,$BRANCHES, != *,main,* ]]; then
        # Rename 'master' to 'main'
        git branch --move master main &&
          git branch --set-upstream-to origin/main main
      fi &&
      BRANCH=$(git rev-parse --verify --abbrev-ref HEAD) &&
      if [[ $BRANCH == "$1" ]]; then
        # If the target branch is already checked out, merge upstream changes
        git merge --ff-only "origin/$1" ||
          git reset --hard "origin/$1"
      elif [[ ,$BRANCHES, == *,"$1",* ]]; then
        # If the target branch exists but isn't checked out, merge upstream
        # changes, then switch
        { git merge-base --is-ancestor "$1" "origin/$1" &&
          git fetch . "origin/$1:$1" ||
          git branch --force "$1" "origin/$1"; } &&
          git checkout "$1"
      else
        # Otherwise, create a new branch from origin/<branch>
        git checkout -b "$1" "origin/$1"
      fi &&
      # Set remote-tracking branch to origin/<branch> if needed
      { git rev-parse --verify --abbrev-ref "@{upstream}" 2>/dev/null |
        grep -Fx "origin/$1" >/dev/null ||
        git branch --set-upstream-to "origin/$1"; } &&
      if [[ ,$BRANCHES, == *,master,* ]] && [[ ,$BRANCHES, == *,main,* ]]; then
        # Delete 'master'
        git merge-base --is-ancestor master origin/main &&
          git branch --delete --force master
      fi) || return

    . ./lib/bash/rc.sh || return

    # Install icdiff if it's not already installed
    INSTALL=$(lk_dpkg_not_installed_list icdiff) || return
    [ -z "$INSTALL" ] ||
      lk_apt_install $INSTALL || return

    shopt -s nullglob

    [ -z "${3:+1}" ] ||
      ! KEYS_FILE=$(lk_first_existing \
        /etc/skel.*/.ssh/{authorized_keys_*,authorized_keys}) ||
      lk_file_replace -m "$KEYS_FILE" "$3" || return

    HEAD_FILE=.git/update-server-head
    LAST_HEAD=
    { [ ! -e "$HEAD_FILE" ] || LAST_HEAD=$(<"$HEAD_FILE"); } &&
      HEAD=$(lk_git_ref) || return
    if ((FORCE_PROVISION)) || [[ $HEAD != "$LAST_HEAD" ]]; then
      ./bin/lk-provision-hosting.sh \
        --set LK_PLATFORM_BRANCH="$1" \
        "${@:4}" &&
        echo "$HEAD" >"$HEAD_FILE"
    else
      lk_tty_log "System already provisioned by lk-platform revision $HEAD"
      lk_tty_print "Checking settings"
      SH=$(lk_settings_getopt "${@:4}") &&
        lk_settings_persist "$SH"
    fi || return

    ((!TLS)) || {
      lk_tty_print "Checking TLS certificates"
      local IFS=$'\n'
      lk_mktemp_with CERT_LIST lk_certbot_list &&
        NO_CERT=($(comm -13 \
          <(awk -F$'\t' -v "now=$(lk_date "%Y-%m-%d %H:%M:%S%z")" \
            '$3 > now {print $2}' "$CERT_LIST" | sort -u) \
          <(lk_hosting_list_sites -e |
            awk -F$'\t' '$11 == "N" {print $10}' | sort -u))) ||
        lk_tty_error -r "Error retrieving local certificates and/or domains" ||
        return
      IFS=,
      [ -z "${NO_CERT+1}" ] ||
        for DOMAINS in "${NO_CERT[@]}"; do
          [[ $DOMAINS =~ \.$TLD_REGEX(,|$) ]] || continue
          lk_tty_detail "Requesting TLS certificate:" "${DOMAINS//,/ }"
          lk_certbot_install $DOMAINS || lk_tty_error -r \
            "TLS certificate not obtained" || STATUS=$?
        done
      unset IFS
    }

    ((!WORDPRESS)) ||
      for WP in /srv/www/{*,*/*}/public_html/wp-config.php; do
        WP=${WP%/wp-config.php}
        OWNER=$(stat -c '%U' "$WP") &&
          runuser -u "$OWNER" -- bash -c "$(
            declare -f update-wp
            printf '%q %q\n' update-wp "$WP"
          )" || STATUS=$?
      done

    return "$STATUS"
  }

  function do-update-server() {
    local STATUS=0
    keep-alive || return
    update-server "$@" &
    wait $! || STATUS=$?
    echo "update-server exit status: $STATUS" >&2
    return "$STATUS"
  }

  function do-query-server() {
    local IFS PUBLIC_IP HOSTED_DOMAIN
    unset IFS
    . /opt/lk-platform/lib/bash/rc.sh &&
      lk_require provision hosting &&
      PUBLIC_IP=$(lk_system_get_public_ips | lk_filter_ipv4 | head -n1) &&
      HOSTED_DOMAIN=($(lk_hosting_list_sites -e |
        awk '{print $10}' | tr ',' '\n')) &&
      declare -p PUBLIC_IP HOSTED_DOMAIN
  }

  ARGS=()
  FORCE_PROVISION=0
  UPGRADE=0
  TLS=1
  WORDPRESS=1
  TEST=1
  while [[ ${1-} =~ ^(-[saru]|--(set|add|remove|unset|(no-)?(force-provision|upgrade|tls|wordpress|test)))$ ]]; do
    [[ $1 != --no-force-provision ]] || FORCE_PROVISION=0
    [[ $1 != --force-provision ]] || FORCE_PROVISION=1
    [[ $1 != --no-upgrade ]] || UPGRADE=0
    [[ $1 != --upgrade ]] || UPGRADE=1
    [[ $1 != --no-tls ]] || TLS=0
    [[ $1 != --tls ]] || TLS=1
    [[ $1 != --no-wordpress ]] || WORDPRESS=0
    [[ $1 != --wordpress ]] || WORDPRESS=1
    [[ $1 != --no-test ]] || TEST=0
    [[ $1 != --test ]] || TEST=1
    [[ ! $1 =~ ^--(no-)?(force-provision|upgrade|tls|wordpress|test)$ ]] || { shift && continue; }
    SHIFT=2
    [[ ${2-} == *=* ]] || [[ $1 =~ ^--?u ]] ||
      ((SHIFT++))
    ARGS+=("${@:1:SHIFT}")
    shift "$SHIFT"
  done
  ((UPGRADE)) ||
    ARGS+=(--no-upgrade)

  TLD_REGEX=$(lk_cache curl -fsSL \
    "https://data.iana.org/TLD/tlds-alpha-by-domain.txt" |
    sed -E '/^(#|$)/d' | tr '[:upper:]' '[:lower:]' |
    lk_ere_implode_input -e)
  TMP=$(lk_mktemp -d)
  ! lk_verbose 2 ||
    lk_tty_print "Generating scripts in" "$TMP"
  SCRIPT=$TMP/do-update-server.sh
  {
    declare -f keep-alive update-server do-update-server
    declare -p FORCE_PROVISION TLS WORDPRESS TLD_REGEX
    lk_quote_args do-update-server \
      "${UPDATE_SERVER_BRANCH:-main}" \
      "${UPDATE_SERVER_REPO:-https://github.com/lkrms/lk-platform.git}" \
      "${UPDATE_SERVER_HOSTING_KEYS-}" \
      ${ARGS[@]+"${ARGS[@]}"}
  } >"$SCRIPT"
  COMMAND=$(lk_quote_args \
    bash -c 't=$(mktemp) && cat >"$t" && sudo -HE bash "$t"')

  ((!TEST)) || {
    SCRIPT2=$TMP/do-query-server.sh
    {
      declare -f do-query-server
      lk_quote_args do-query-server
    } >"$SCRIPT2"
    COMMAND2=$(lk_quote_args \
      bash -c 't=$(mktemp) && cat >"$t" && bash "$t"')
  }

  UPDATED=$TMP/updated-servers.txt
  FAILED=$TMP/failed-servers.txt
  UNREACHABLE=$TMP/unreachable-domains.txt
  touch "$UPDATED" "$FAILED" "$UNREACHABLE"
  i=0
  while [ $# -gt 0 ]; do

    trap "" SIGHUP SIGINT SIGTERM

    ((++i))
    lk_tty_print "Updating server $i of $((i + $# - 1)):" "$1"

    (
      _LK_LOG_CMDLINE=("$0-$1")
      lk_log_start

      [ "${LK_NO_INPUT-}" != 1 ] ||
        lk_log_tty_off -a

      STATUS=0
      ssh -o ControlPath=none -o LogLevel=QUIET "$1" \
        LK_VERBOSE=${LK_VERBOSE-1} "$COMMAND" <"$SCRIPT" || STATUS=$?
      ((!TEST)) || {
        SH=$(ssh -o ControlPath=none -o LogLevel=QUIET "$1" \
          "$COMMAND2" <"$SCRIPT2") &&
          eval "$SH" && {
          lk_tty_print "Testing enabled sites"
          PIDS=()
          for DOMAIN in ${HOSTED_DOMAIN+"${HOSTED_DOMAIN[@]}"}; do
            (
              ARGS=()
              INVALID_TLS=
              TEST_STATUS=0
              while :; do
                HTTP=$(curl -sSI \
                  -o "$TMP/curl-$DOMAIN.http" \
                  -H "Cache-Control: no-cache" \
                  -H "Pragma: no-cache" \
                  --connect-to "$DOMAIN::$PUBLIC_IP:" \
                  --connect-timeout 5 \
                  ${ARGS+"${ARGS[@]}"} \
                  "https://$DOMAIN/php-fpm-ping" 2>&1 >/dev/null | head -n1) &&
                  HTTP=$(awk \
                    'NR == 1 || tolower($1) == "location:" {print}' \
                    "$TMP/curl-$DOMAIN.http") &&
                  [[ $HTTP =~ ^HTTP/$NS+$S+([0-9]+) ]] &&
                  ((rc = BASH_REMATCH[1], rc < 400 || rc == 403)) &&
                  lk_tty_success "OK:" "$DOMAIN$INVALID_TLS" &&
                  break || {
                  TEST_STATUS=$?
                  case "$TEST_STATUS" in
                  60)
                    # "Peer certificate cannot be authenticated with known CA
                    # certificates"
                    lk_in_array --insecure ARGS || {
                      ARGS+=(--insecure)
                      INVALID_TLS=" $LK_RED(insecure)$LK_RESET"
                      TEST_STATUS=0
                      continue
                    }
                    ;;
                  esac
                  lk_tty_error "Failed:" \
                    "$LK_BOLD$DOMAIN$INVALID_TLS$LK_RESET $LK_DIM${HTTP:-($TEST_STATUS)}$LK_UNDIM"
                  echo "$1:$DOMAIN" >>"$UNREACHABLE"
                }
                break
              done
            ) &
            PIDS[${#PIDS[@]}]=$!
          done
          [[ ${#PIDS[@]} -eq 0 ]] || wait "${PIDS[@]}"
        }
      }

      [ "${LK_NO_INPUT-}" != 1 ] ||
        lk_log_tty_on

      (exit "$STATUS") &&
        { FILE=$UPDATED &&
          [ "${LK_NO_INPUT-}" != 1 ] ||
          lk_tty_print "Update completed:" "$1" \
            "$LK_BOLD$_LK_SUCCESS_COLOUR" || :; } ||
        { FILE=$FAILED &&
          lk_tty_print "Update failed:" "$1" \
            "$LK_BOLD$_LK_ERROR_COLOUR"; }
      echo "$1" >>"$FILE"
    ) &

    lk_no_input || {
      wait "$!"
      trap - SIGHUP SIGINT SIGTERM
      [ $# -gt 1 ] && lk_confirm "Continue?" Y || break
    }

    shift

  done

  if lk_no_input; then
    lk_tty_print "Waiting for updates to complete"
    wait
  else
    lk_tty_print "Batch complete"
  fi

  _FAILED=($(<"$FAILED"))
  _UPDATED=($(<"$UPDATED"))
  _UNREACHABLE=($(<"$UNREACHABLE"))

  [ ${#_FAILED[@]} -eq 0 ] || {
    lk_tty_error "${#_FAILED[@]} of $i $(lk_plural \
      "$i" server servers) failed to update:" \
      "$(lk_arr _FAILED)"
  }

  [ ${#_UNREACHABLE[@]} -eq 0 ] ||
    lk_tty_error "${#_UNREACHABLE[@]} $(lk_plural \
      "${#_UNREACHABLE[@]}" domain domains) were unreachable:" \
      "$(lk_arr _UNREACHABLE)"

  [ ${#_UPDATED[@]} -eq 0 ] ||
    lk_tty_success "${#_UPDATED[@]} $(lk_plural \
      "${#_UPDATED[@]}" server servers) updated successfully:" \
      "$(lk_arr _UPDATED)"

  [[ ${#_FAILED[@]}${#_UNREACHABLE[@]} == 00 ]] || lk_die ""

  exit
}
