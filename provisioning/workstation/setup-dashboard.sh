#!/usr/bin/env bash
set -euo pipefail

# setup-dashboard.sh - live founder dashboard on the cockpit box (founder ask
# 2026-07-13: cards with real state, never stale). Installs:
#   - a systemd timer that re-runs generate-dashboard.sh every 15 minutes
#   - a localhost-ONLY python http.server on 8090 serving ~/dashboard
# code-server's built-in /proxy/<port>/ then exposes it through the EXISTING
# Mac tunnel at  http://localhost:8080/proxy/8090/  - zero Mac-side changes.
# 8090 must never be opened in ufw; the tunnel is the auth (same rule as 8080).
#
# Idempotent - safe to re-run. Second run prints "== converged: no changes".

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

install_if_changed 0644 /etc/systemd/system/swordfish-dashboard-web.service <<'UNIT'
[Unit]
Description=swordfish: founder dashboard static server (localhost only - tunnel is the auth)
After=network.target

[Service]
User=deploy
ExecStart=/usr/bin/python3 -m http.server 8090 --bind 127.0.0.1 --directory /home/deploy/dashboard
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

install_if_changed 0644 /etc/systemd/system/swordfish-dashboard-regen.service <<'UNIT'
[Unit]
Description=swordfish: regenerate the founder dashboard

[Service]
Type=oneshot
User=deploy
ExecStart=/usr/bin/bash /home/deploy/work/swordfish/provisioning/workstation/generate-dashboard.sh
UNIT

install_if_changed 0644 /etc/systemd/system/swordfish-dashboard-regen.timer <<'UNIT'
[Unit]
Description=swordfish: dashboard refresh every 15 minutes

[Timer]
OnCalendar=*:00/15
OnBootSec=2min

[Install]
WantedBy=timers.target
UNIT

# Event-driven git accuracy (walter-cockpit pattern, founder ask 2026-07-13):
# the 15-min snapshot can catch a repo mid-wrap and show stale uncommitted
# counts for up to 15 minutes. A path unit watching each repo's .git state
# (index = stage/commit, refs = commit/push) triggers a local-only projects
# refresh within seconds of any commit or push. StartLimitIntervalSec=0 +
# the 2s ExecStartPre sleep coalesce an add+commit+push burst without ever
# rate-limiting the unit into a dead state.
install_if_changed 0644 /etc/systemd/system/swordfish-dashboard-projects.service <<'UNIT'
[Unit]
Description=swordfish: refresh the projects card after a commit/push
StartLimitIntervalSec=0

[Service]
Type=oneshot
User=deploy
ExecStartPre=/usr/bin/sleep 2
ExecStart=/usr/bin/bash /home/deploy/work/swordfish/provisioning/workstation/generate-dashboard.sh projects
UNIT

# The path unit is GENERATED from the on-box directory glob, never written
# out literally: repo directory names on this box can include guarded
# portfolio names, and this file is git-tracked. The generated unit lands
# untracked in /etc/systemd/system.
{
  printf '[Unit]\nDescription=swordfish: watch repo git state for the projects card\n\n[Path]\n'
  for gd in /home/deploy/work/*/.git /home/deploy/vault/.git; do
    [ -d "$gd" ] || continue
    printf 'PathModified=%s/index\n' "$gd"
    printf 'PathModified=%s/packed-refs\n' "$gd"
    printf 'PathModified=%s/refs/heads\n' "$gd"
    printf 'PathModified=%s/refs/remotes/origin\n' "$gd"
  done
  printf 'Unit=swordfish-dashboard-projects.service\n\n[Install]\nWantedBy=paths.target\n'
} | install_if_changed 0644 /etc/systemd/system/swordfish-dashboard-projects.path

if [ "$changed" -eq 1 ]; then
  sudo systemctl daemon-reload
fi
for u in swordfish-dashboard-web.service swordfish-dashboard-regen.timer swordfish-dashboard-projects.path; do
  if ! systemctl is-enabled --quiet "$u" 2>/dev/null; then
    sudo systemctl enable --now "$u"
    changed=1
  fi
done

# --- verify ------------------------------------------------------------------
sudo systemctl start swordfish-dashboard-regen.service
sleep 1
page=$(curl -fsS http://127.0.0.1:8090/)
grep -q 'class="btn"' <<<"$page" \
  || { echo "FAIL: dashboard not served on 8090"; exit 1; }
# v3 cockpit sections (dashboard-cockpit-plan-2026-07-13.md) all present
for sid in needs-steven fleet security money calendar hermes; do
  grep -q "section id=\"$sid\"" <<<"$page" \
    || { echo "FAIL: cockpit section '$sid' missing from the page"; exit 1; }
done
# leak check asserts on the secret VALUES, not key-name shapes (a key-name
# grep certifies nothing - security review 2026-07-13): the page must not
# contain any live credential this pipeline touches
SEC=/home/deploy/work/swordfish/inventory/secrets
for f in beszel-admin.password kuma-admin.password google-calendar-founder.ics.url; do
  [ -f "$SEC/$f" ] || continue
  v=$(tr -d '\r\n' < "$SEC/$f")
  [ -n "$v" ] && grep -qF -- "$v" <<<"$page" \
    && { echo "FAIL: content of secret $f is present in the page"; exit 1; }
done
for var in BINARYLANE_API_TOKEN VULTR_API_KEY PORKBUN_API_KEY PORKBUN_SECRET_API_KEY; do
  v=$(grep "^${var}[[:space:]]*=" /home/deploy/work/swordfish/.env 2>/dev/null \
      | head -1 | cut -d= -f2- | tr -d '\r"' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -n "$v" ] && grep -qF -- "$v" <<<"$page" \
    && { echo "FAIL: value of $var is present in the page"; exit 1; }
done
ss -ltn | grep -q '127.0.0.1:8090' \
  || { echo "FAIL: 8090 not bound to localhost only"; exit 1; }
# event-driven projects refresh: the fast service must rewrite projects.json
# (the inotify trigger itself was proven end-to-end at install, 2026-07-13:
# git add -> dirty count up within seconds -> unstage -> back to clean)
before=$(stat -c %Y /home/deploy/dashboard/data/projects.json 2>/dev/null || echo 0)
sudo systemctl start swordfish-dashboard-projects.service
after=$(stat -c %Y /home/deploy/dashboard/data/projects.json 2>/dev/null || echo 0)
[ "$after" -gt "$before" ] \
  || { echo "FAIL: projects fast-refresh did not rewrite projects.json"; exit 1; }
systemctl is-active --quiet swordfish-dashboard-projects.path \
  || { echo "FAIL: projects .git path unit not active"; exit 1; }

if [ "$changed" -eq 0 ]; then
  echo "== converged: no changes"
else
  echo "== converged: changes applied (regen timer + 8090 localhost server)"
fi
