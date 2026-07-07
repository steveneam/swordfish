#!/usr/bin/env bash
# hc-ping.sh success|fail - dead-man's-switch pings (CHARTER pinned decision 5).
# Two independent receivers, pinged in sequence, each optional, never failing
# the backup job (a missing success ping is exactly what the alarms catch):
#   /etc/resticprofile/hc-url    healthchecks.io - the OFF-infra witness that
#                                fires even if this whole box is dead
#   /etc/resticprofile/kuma-url  Uptime Kuma push monitor (Bucket 4) - the
#                                on-infra half, feeds the ntfy phone push
# Both URLs are capability-bearing (anyone holding one can silence that alarm),
# so they live as 0600 root files installed by backups-apply from the repo
# secrets HEALTHCHECKS_PING_URL / KUMA_PUSH_URL. Installed as
# /etc/resticprofile/hc-ping.sh by phase7-backups.sh; called by the
# run-after / run-after-fail hooks in profiles.yaml.

set -u

mode="${1:-}"
case "$mode" in
    success|fail) ;;
    *) echo "usage: hc-ping.sh success|fail"; exit 2 ;;
esac

send() { # url label
    if curl -fsS -m 10 --retry 5 -o /dev/null "$1"; then
        echo "OK: dead-man ping sent ($2)"
    else
        echo "WARN: dead-man ping failed to send ($2)"
    fi
}

sent=0

hc_file=/etc/resticprofile/hc-url
if [ -s "$hc_file" ]; then
    url=$(tr -d '[:space:]' < "$hc_file")
    if [ "$mode" = fail ]; then url="$url/fail"; fi
    send "$url" "healthchecks $mode"
    sent=1
fi

kuma_file=/etc/resticprofile/kuma-url
if [ -s "$kuma_file" ]; then
    url=$(tr -d '[:space:]' < "$kuma_file")
    if [ "$mode" = success ]; then
        send "$url?status=up&msg=backup-ok" "kuma $mode"
    else
        send "$url?status=down&msg=backup-failed" "kuma $mode"
    fi
    sent=1
fi

if [ "$sent" -eq 0 ]; then
    echo "WARN: no dead-man URLs installed (hc-url / kuma-url missing) - pings skipped (set the repo secrets + re-run backups-apply)"
fi
exit 0
