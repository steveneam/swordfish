#!/usr/bin/env bash
# hc-ping.sh success|fail - dead-man's-switch ping (CHARTER pinned decision 5).
# healthchecks.io alerts when the success ping goes MISSING past the grace
# window - it fires even if this box is dead, which is the whole point. The
# ping URL is capability-bearing (anyone holding it can silence the alarm), so
# it lives in /etc/resticprofile/hc-url (0600 root), installed by backups-apply
# from the HEALTHCHECKS_PING_URL repo secret. Installed as
# /etc/resticprofile/hc-ping.sh by phase7-backups.sh; called by the
# run-after / run-after-fail hooks in profiles.yaml.

set -u

url_file=/etc/resticprofile/hc-url
if [ ! -s "$url_file" ]; then
    echo "WARN: $url_file missing/empty - dead-man ping skipped (set the HEALTHCHECKS_PING_URL repo secret + re-run backups-apply)"
    exit 0
fi
url=$(tr -d '[:space:]' < "$url_file")

case "${1:-}" in
    success) target="$url" ;;
    fail)    target="$url/fail" ;;
    *) echo "usage: hc-ping.sh success|fail"; exit 2 ;;
esac

# never let a ping delivery problem fail the backup job itself - a missing
# success ping is exactly what the dead-man alarm exists to catch
if curl -fsS -m 10 --retry 5 -o /dev/null "$target"; then
    echo "OK: dead-man ping sent ($1)"
else
    echo "WARN: dead-man ping failed to send ($1)"
fi
exit 0
