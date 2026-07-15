#!/usr/bin/env bash
set -euo pipefail

# setup-thalon-cutover-watch.sh - TEMPORARY watcher for the thalon key-scope
# cutover (security review finding 2, Option B; founder ask 2026-07-15:
# "monitor thalon so you know if they flipped, rather than me telling you").
#
# What it watches (every 10 min, deterministic, LLM-free): the next completed
# thalon web-image run on main AFTER the :staging pin (anchor = install time).
# Under Option B any green run IS the step-5 confirm (re-tag + deploy-only key
# + :staging pin, end-to-end). One edge-triggered alert, then it goes quiet:
#   ✅ green -> Telegram + journal: close-out session needed (revoke legacy
#      key, retire member, STRICT_SCOPE standing)
#   ⚠️ red   -> Telegram + journal: rollback runbook (re-pin recorded value,
#      re-swap old key - both values in thalon's FROM-SWORDFISH.md note)
# State: /var/lib/swordfish/thalon-cutover-watch (anchor + done flag). The
# next swordfish session reads the done flag at boot (CURRENT.md Next-1).
#
# LIFECYCLE: installed for ONE cutover. The close-out session removes it:
#   sudo systemctl disable --now swordfish-thalon-cutover.timer
#   sudo rm -f /etc/systemd/system/swordfish-thalon-cutover.{timer,service} \
#              /usr/local/bin/swordfish-thalon-cutover-watch.sh
#   sudo rm -rf /var/lib/swordfish/thalon-cutover-watch && sudo systemctl daemon-reload
#
# Root unit (alerts.env is root:600); gh rides the deploy user's auth.
# Idempotent - safe to re-run.

changed=0
install_if_changed() { # $1=mode $2=dest, content on stdin
  local tmp; tmp=$(mktemp)
  cat > "$tmp"
  if [ ! -f "$2" ] || ! cmp -s "$tmp" "$2"; then
    sudo install -m "$1" -o root -g root "$tmp" "$2"
    changed=1
  fi
  rm -f "$tmp"
}

install_if_changed 0755 /usr/local/bin/swordfish-thalon-cutover-watch.sh <<'WATCH'
#!/usr/bin/env bash
# Fired by swordfish-thalon-cutover.timer. Must never fail loudly - every
# path exits 0; a missing prerequisite just means "try again next tick".
set -u
STATE=/var/lib/swordfish/thalon-cutover-watch
mkdir -p "$STATE"
[ -f "$STATE/anchor" ] || date +%s > "$STATE/anchor"
[ -f "$STATE/done" ] && exit 0
[ -r /etc/swordfish/alerts.env ] || exit 0
. /etc/swordfish/alerts.env
[ -n "${ALERTS_BOT_TOKEN:-}" ] && [ -n "${ALERTS_CHAT_ID:-}" ] || exit 0

# the run that flipped the var (step 3) - never re-alert on it
BASELINE_RUN=29402961291

row=$(runuser -u deploy -- env HOME=/home/deploy \
  gh api 'repos/steveneam/thalon/actions/workflows/web-image.yml/runs?branch=main&per_page=1' \
  -q '.workflow_runs[0] | "\(.id) \(.status) \(.conclusion) \(.created_at)"' 2>/dev/null) || exit 0
[ -n "$row" ] || exit 0
id=$(awk '{print $1}' <<<"$row"); status=$(awk '{print $2}' <<<"$row")
concl=$(awk '{print $3}' <<<"$row"); created=$(awk '{print $4}' <<<"$row")

[ "$id" != "$BASELINE_RUN" ] || exit 0
[ "$status" = "completed" ] || exit 0
created_epoch=$(date -d "$created" +%s 2>/dev/null || echo 0)
[ "$created_epoch" -gt "$(cat "$STATE/anchor")" ] || exit 0

if [ "$concl" = "success" ]; then
  msg="✅ [syd4] thalon cutover: confirm run $id GREEN - Option B live end-to-end. Swordfish session needed for close-out: revoke legacy key, retire dokploy-thalon-ci member, STRICT_SCOPE standing. (gogogo swordfish when convenient)"
else
  msg="⚠️ [syd4] thalon cutover: run $id ended '$concl' AFTER the :staging pin - swordfish session needed for rollback: re-pin recorded image + re-swap old key (values in thalon FROM-SWORDFISH.md cutover note)"
fi
logger -t swordfish-alerts "$msg"
printf '%s %s\n' "$(date -u +%FT%TZ)" "$msg" > "$STATE/done"
curl -fsS -m 10 "https://api.telegram.org/bot${ALERTS_BOT_TOKEN}/sendMessage" \
  -d chat_id="${ALERTS_CHAT_ID}" --data-urlencode text="$msg" >/dev/null 2>&1
exit 0
WATCH

install_if_changed 0644 /etc/systemd/system/swordfish-thalon-cutover.service <<'UNIT'
[Unit]
Description=swordfish: thalon key-scope cutover watch (temporary; removed at close-out)

[Service]
Type=oneshot
ExecStart=/usr/local/bin/swordfish-thalon-cutover-watch.sh
UNIT

install_if_changed 0644 /etc/systemd/system/swordfish-thalon-cutover.timer <<'TIMER'
[Unit]
Description=swordfish: thalon cutover watch every 10 min (temporary)

[Timer]
OnCalendar=*:0/10
Persistent=true

[Install]
WantedBy=timers.target
TIMER

if [ "$changed" -eq 1 ]; then
  sudo systemctl daemon-reload
fi
if ! systemctl is-enabled --quiet swordfish-thalon-cutover.timer 2>/dev/null; then
  sudo systemctl enable --now swordfish-thalon-cutover.timer
  changed=1
fi

# --- verify ------------------------------------------------------------------
systemctl is-active --quiet swordfish-thalon-cutover.timer || { echo "FAIL: timer inactive"; exit 1; }
sudo /usr/local/bin/swordfish-thalon-cutover-watch.sh || { echo "FAIL: watcher errored on a dry run"; exit 1; }
sudo test -f /var/lib/swordfish/thalon-cutover-watch/anchor || { echo "FAIL: anchor not written"; exit 1; }

if [ "$changed" -eq 0 ]; then
  echo "== converged: no changes"
else
  echo "== converged: cutover watch armed (anchor $(sudo cat /var/lib/swordfish/thalon-cutover-watch/anchor))"
fi
