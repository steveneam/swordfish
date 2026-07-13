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

if [ "$changed" -eq 1 ]; then
  sudo systemctl daemon-reload
fi
for u in swordfish-dashboard-web.service swordfish-dashboard-regen.timer; do
  if ! systemctl is-enabled --quiet "$u" 2>/dev/null; then
    sudo systemctl enable --now "$u"
    changed=1
  fi
done

# --- verify ------------------------------------------------------------------
sudo systemctl start swordfish-dashboard-regen.service
sleep 1
curl -fsS http://127.0.0.1:8090/ | grep -q 'class="btn"' \
  || { echo "FAIL: dashboard not served on 8090"; exit 1; }
ss -ltn | grep -q '127.0.0.1:8090' \
  || { echo "FAIL: 8090 not bound to localhost only"; exit 1; }

if [ "$changed" -eq 0 ]; then
  echo "== converged: no changes"
else
  echo "== converged: changes applied (regen timer + 8090 localhost server)"
fi
