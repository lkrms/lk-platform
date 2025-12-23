#!/usr/bin/env bash

function __usage() {
  cat <<EOF
Update lk-platform on one or more hosting servers and perform optional
provisioning tasks.

Usage:
  ${0##*/} [options] <SSH_HOST>...

Options:
  -s, --set <SETTING>=<VALUE>     Set an lk-platform setting
  -a, --add <SETTING>=<VALUE>     Add a value to an lk-platform setting
  -r, --remove <SETTING>=<VALUE>  Remove a value from an lk-platform setting
  -u, --unset <SETTING>           Clear an lk-platform setting
      --branch <BRANCH>     lk-platform branch to provision [default: $BRANCH]
      --repo <URL>          Override '$REPO'
  -k, --keys <KEYS>         Update provider SSH keys for hosting account access
  -p, --provision           Run \`lk-provision-hosting.sh\`
  -g, --upgrade             Upgrade packages (implies --provision)
  -l, --tls                 Try to obtain any missing TLS certificates
  -w, --wordpress           Trigger WP-Cron from hosting account crontabs
  -b, --reboot              Schedule a reboot if required
  -t, --reboot-time <TIME>  Specify reboot time (implies --reboot)
                            [default: LK_AUTO_REBOOT_TIME if set, otherwise +2]
  -h, --reachability        Test site reachability

This script takes the following actions on each <SSH_HOST>, creating an
output log locally and in ~root/ on the remote system:
1. Ignore SIGHUP, SIGINT and SIGTERM to prevent disruption of long-running
   provisioning processes
2. Update lk-platform, discarding any code changes
3. Install icdiff for more readable log output
4. Replace /etc/skel.<PREFIX>/.ssh/authorized_keys_* with <KEYS>
5. If --provision is set, run \`lk-provision-hosting.sh\` with any settings
   changes, otherwise apply settings changes directly
6. If --tls is set, try to obtain Let's Encrypt TLS certificates for any
   public-facing sites that don't have one
7. If --wordpress is set, enable system cron on any WordPress sites that
   aren't using it
8. If --reboot is set, check if a reboot is required and if so, schedule
   it for --reboot-time
EOF
}

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
    trap "kill $! 2>/dev/null || echo ' !! Connection with client lost during update' >&2" EXIT
    trap "" SIGHUP SIGINT SIGTERM
  }

  function update-server() {
    function update-wp() {
      local SITE_ROOT PHP CRONTAB DISABLE_WP_CRON
      cd "$1" &&
        . /opt/lk-platform/lib/bash/rc.sh || return
      [[ ! -e ~/.lk-archived ]] || {
        lk_tty_print "Not checking archived WordPress at" "$1"
        return
      }
      SITE_ROOT=$(lk_wp_get_site_root) &&
        PHP=$(lk_wp_curl -fsS "/php-sysinfo" | jq -r '.php.version') &&
        PHP=$(type -P "php$PHP") || return
      lk_tty_print "Checking WordPress at" "$1"
      if CRONTAB=$(crontab -l 2>/dev/null | grep -F "$(printf \
        ' -- wp_if_running --path=%q cron event run --due-now' "$1")" |
        grep -E '\<LK_LOG_FILE' |
        grep -F "$(printf 'WP_CLI_PHP=%q' "$PHP")") &&
        DISABLE_WP_CRON=$(lk_wp \
          config get DISABLE_WP_CRON --type=constant) &&
        lk_is_true DISABLE_WP_CRON; then
        ! lk_is_v 2 || {
          lk_tty_detail "WP-Cron appears to be configured correctly"
          lk_tty_detail "crontab command:" $'\n'"$CRONTAB"
        }
      else
        ! lk_is_v 2 ||
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
        git config remote.origin.url | grep -Fx "$REPO" >/dev/null ||
          git remote set-url origin "$REPO"
      else
        git remote add origin "$REPO"
      fi &&
      # Retrieve latest commits from origin
      git fetch --tags --force origin &&
      git remote set-head origin --auto >/dev/null &&
      git remote prune origin &&
      # If target branch is 'main', reset origin/main to the most recent
      # annotated tag's commit
      if [[ $BRANCH == main ]] &&
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
      _BRANCH=$(git rev-parse --verify --abbrev-ref HEAD) &&
      if [[ $_BRANCH == "$BRANCH" ]]; then
        # If the target branch is already checked out, merge upstream changes
        git merge --ff-only "origin/$BRANCH" ||
          git reset --hard "origin/$BRANCH"
      elif [[ ,$BRANCHES, == *,"$BRANCH",* ]]; then
        # If the target branch exists but isn't checked out, merge upstream
        # changes, then switch
        { git merge-base --is-ancestor "$BRANCH" "origin/$BRANCH" &&
          git fetch . "origin/$BRANCH:$BRANCH" ||
          git branch --force "$BRANCH" "origin/$BRANCH"; } &&
          git checkout "$BRANCH"
      else
        # Otherwise, create a new branch from origin/<branch>
        git checkout -b "$BRANCH" "origin/$BRANCH"
      fi &&
      # Set remote-tracking branch to origin/<branch> if needed
      { git rev-parse --verify --abbrev-ref "@{upstream}" 2>/dev/null |
        grep -Fx "origin/$BRANCH" >/dev/null ||
        git branch --set-upstream-to "origin/$BRANCH"; } &&
      if [[ ,$BRANCHES, == *,master,* ]] && [[ ,$BRANCHES, == *,main,* ]]; then
        # Delete 'master'
        git merge-base --is-ancestor master origin/main &&
          git branch --delete --force master
      fi) || return

    . ./lib/bash/rc.sh || return

    # Install icdiff if it's not already installed
    INSTALL=$(lk_dpkg_list_not_installed icdiff) || return
    [ -z "$INSTALL" ] ||
      lk_apt_install $INSTALL || return

    shopt -s nullglob

    [ -z "${KEYS:+1}" ] ||
      ! KEYS_FILE=$(lk_readable \
        /etc/skel.*/.ssh/{authorized_keys_*,authorized_keys}) ||
      lk_file_replace -m "$KEYS_FILE" "$KEYS" || return

    HEAD_FILE=.git/update-server-head
    LAST_HEAD=
    { [ ! -e "$HEAD_FILE" ] || LAST_HEAD=$(<"$HEAD_FILE"); } &&
      HEAD=$(lk_git_ref) || return
    if ((PROVISION)); then
      lk_tty_log "Provisioning with lk-platform revision $HEAD"
      ./bin/lk-provision-hosting.sh \
        --set LK_PLATFORM_BRANCH="$BRANCH" \
        "$@" &&
        echo "$HEAD" >"$HEAD_FILE"
    else
      lk_tty_print "Checking settings"
      SH=$(lk_settings_getopt "$@") &&
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
          [[ $DOMAINS =~ \.$TOP_LEVEL_DOMAIN_REGEX(,|$) ]] || continue
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

    ((!REBOOT)) ||
      [[ ! -e /var/run/reboot-required ]] || {
      lk_tty_print "Reboot required"
      lk_tty_run_detail \
        shutdown -r "${REBOOT_TIME:-${LK_AUTO_REBOOT_TIME:-+2}}" || STATUS=$?
    }

    return "$STATUS"
  }

  function do-exit() {
    local STATUS=${1:-$?}
    rm -f "$0" >&2 || true
    exit "$STATUS"
  }

  function do-update-server() {
    local STATUS=0
    keep-alive || do-exit
    update-server "$@" &
    wait $! || STATUS=$?
    echo "update-server exit status: $STATUS" >&2
    do-exit "$STATUS"
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
    do-exit
  }

  ARGS=()
  BRANCH=main
  REPO=https://github.com/lkrms/lk-platform.git
  KEYS=
  PROVISION=0
  UPGRADE=0
  TLS=0
  WORDPRESS=0
  REBOOT=0
  REBOOT_TIME=
  REACHABILITY=0

  lk_getopt "s:a:r:u:k:pglwbt:h" \
    "set:,add:,remove:,unset:,branch:,repo:,keys:,provision,upgrade,tls,wordpress,reboot,reboot-time:,reachability"
  eval "set -- $LK_GETOPT"

  while :; do
    OPT=$1
    shift
    case "$OPT" in
    -s | -a | -r | -u | --set | --add | --remove | --unset)
      ARGS+=("$OPT" "$1")
      shift
      ;;
    --branch)
      BRANCH=$1
      shift
      ;;
    --repo)
      REPO=$1
      shift
      ;;
    -k | --keys)
      KEYS=$1
      shift
      ;;
    -p | --provision)
      PROVISION=1
      ;;
    -g | --upgrade)
      PROVISION=1
      UPGRADE=1
      ;;
    -l | --tls)
      TLS=1
      ;;
    -w | --wordpress)
      WORDPRESS=1
      ;;
    -b | --reboot)
      REBOOT=1
      ;;
    -t | --reboot-time)
      REBOOT=1
      REBOOT_TIME=$1
      shift
      ;;
    -h | --reachability)
      REACHABILITY=1
      ;;
    --)
      break
      ;;
    esac
  done
  ((UPGRADE)) ||
    ARGS+=(--no-upgrade)

  (($#)) || lk_usage

  eval "$(lk_get_regex TOP_LEVEL_DOMAIN_REGEX)"
  lk_mktemp_dir_with TMP
  lk_v 2 lk_tty_print "Generating scripts in" "$TMP"
  SCRIPT=$TMP/do-update-server.sh
  {
    declare -f keep-alive update-server do-exit do-update-server
    declare -p BRANCH REPO KEYS PROVISION TLS WORDPRESS REBOOT REBOOT_TIME TOP_LEVEL_DOMAIN_REGEX
    lk_quote_args do-update-server ${ARGS+"${ARGS[@]}"}
  } >"$SCRIPT"
  COMMAND=$(lk_quote_args \
    bash -c 't=$(mktemp) && cat >"$t" && sudo -HE bash "$t"')

  ((!REACHABILITY)) || {
    SCRIPT2=$TMP/do-query-server.sh
    {
      declare -f do-exit do-query-server
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
      LK_LOG_BASENAME=${0##*/}-$1
      lk_log_open

      [ "${LK_NO_INPUT-}" != Y ] ||
        lk_log_tty_all_off

      STATUS=0
      ssh -o ControlPath=none -o LogLevel=QUIET "$1" \
        LK_VERBOSE=${LK_VERBOSE-1} "$COMMAND" <"$SCRIPT" || STATUS=$?
      ((!REACHABILITY)) || {
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
                  [[ $HTTP =~ ^HTTP/$LK_H+$LK_h+([0-9]+) ]] &&
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
                    "$LK_BOLD$DOMAIN$INVALID_TLS$LK_RESET $LK_DIM${HTTP:-($TEST_STATUS)}$LK_UNBOLD_UNDIM"
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

      [ "${LK_NO_INPUT-}" != Y ] ||
        lk_log_tty_on

      (exit "$STATUS") &&
        { FILE=$UPDATED &&
          [ "${LK_NO_INPUT-}" != Y ] ||
          lk_tty_print "Update completed:" "$1" \
            "$LK_BOLD$_LK_COLOUR_SUCCESS" || :; } ||
        { FILE=$FAILED &&
          lk_tty_print "Update failed:" "$1" \
            "$LK_BOLD$_LK_COLOUR_ERROR"; }
      echo "$1" >>"$FILE"
    ) &

    lk_input_is_off || {
      wait "$!"
      trap - SIGHUP SIGINT SIGTERM
      [ $# -gt 1 ] && lk_tty_yn "Continue?" Y || break
    }

    shift

  done

  if lk_input_is_off; then
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
