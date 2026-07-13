#!/usr/bin/env bash
set -euo pipefail

# setup-relay.sh - installs the E1 relay on syd4 (idempotent; design doc:
# agent_handoff/hermes-e1-relay-design-2026-07-13.md). Second run prints
# "converged". Installs:
#   - the untracked relay-map seed (only if absent - it holds project dirs
#     whose names can be guarded, NEVER tracked)
#   - the watermark, initialised to the CURRENT max message id (no replay
#     of history on first start)
#   - swordfish-relay.service (system unit, User=deploy, Restart=always)
#   - the Stop hook merged into ~/.claude/settings.json (json-aware merge)

DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/../collectors/lib.sh"

MAP_FILE="$HOME/work/swordfish/inventory/secrets/relay-map"
STATE_DIR="$HOME/.local/state/swordfish-relay"
changed=0

if [ ! -f "$MAP_FILE" ]; then
  echo "FAIL: $MAP_FILE missing. Seed it (untracked!) like:"
  echo '  GROUP_ID=-100...   FOUNDER_ID=64...   map[2]=/home/deploy/work/<project>'
  exit 1
fi

mkdir -p "$STATE_DIR" "$HOME/.claude/relay-pending"
if [ ! -f "$STATE_DIR/watermark" ]; then
  # shellcheck disable=SC2034
  declare -A map; GROUP_ID="" FOUNDER_ID=""; . "$MAP_FILE"
  ssh_syd3_stdin 'sudo -n python3 -' <<PY > "$STATE_DIR/watermark"
import sqlite3
db = sqlite3.connect("file:/home/hermes/.hermes/state.db?mode=ro", uri=True)
r = db.execute("select coalesce(max(m.id),0) from messages m "
               "join sessions s on s.id=m.session_id "
               "where s.source='telegram' and s.chat_id='${GROUP_ID}'").fetchone()
print(r[0])
PY
  grep -qE '^[0-9]+$' "$STATE_DIR/watermark" || { echo "FAIL: watermark init"; rm -f "$STATE_DIR/watermark"; exit 1; }
  echo "watermark initialised at $(cat "$STATE_DIR/watermark")"
  changed=1
fi

unit=/etc/systemd/system/swordfish-relay.service
tmp=$(mktemp)
cat > "$tmp" <<UNIT
[Unit]
Description=swordfish: hermes E1 relay poller (founder topic messages -> project agent sessions)
After=network-online.target

[Service]
User=deploy
ExecStart=/usr/bin/bash /home/deploy/work/swordfish/provisioning/workstation/relay/swordfish-relay.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
if [ ! -f "$unit" ] || ! cmp -s "$tmp" "$unit"; then
  sudo install -m 0644 -o root -g root "$tmp" "$unit"
  sudo systemctl daemon-reload
  changed=1
fi
rm -f "$tmp"
sudo systemctl enable --now swordfish-relay.service >/dev/null 2>&1 || true

# Stop hook: json-aware idempotent merge into user settings
python3 - "$HOME/.claude/settings.json" <<'PY' && changed=1 || true
import json, os, sys
p = sys.argv[1]
cmd = "/home/deploy/work/swordfish/provisioning/workstation/relay/relay-stop-hook.sh"
s = {}
if os.path.exists(p):
    s = json.load(open(p))
hooks = s.setdefault("hooks", {}).setdefault("Stop", [])
for entry in hooks:
    if any(h.get("command") == cmd for h in entry.get("hooks", [])):
        sys.exit(1)          # already present -> signal "no change"
hooks.append({"hooks": [{"type": "command", "command": cmd, "timeout": 30}]})
tmp = p + ".tmp"
json.dump(s, open(tmp, "w"), indent=2)
os.replace(tmp, p)
PY

# outbound voice: warn (not fail - relay-send falls back to hermes send)
grep -q '^ALERTS_BOT_TOKEN=..*' "$HOME/work/swordfish/inventory/secrets/telegram.env" 2>/dev/null \
  || echo "WARN: no ALERTS_BOT_TOKEN in inventory/secrets/telegram.env - relay speaks with the hermes bot (reply-bait; see relay-send.sh)"

# --- verify ------------------------------------------------------------------
sleep 2
systemctl is-active --quiet swordfish-relay.service \
  || { echo "FAIL: relay service not active"; sudo journalctl -u swordfish-relay -n 10 --no-pager; exit 1; }
grep -q relay-stop-hook "$HOME/.claude/settings.json" \
  || { echo "FAIL: stop hook not in user settings"; exit 1; }
[ -f "$STATE_DIR/watermark" ] || { echo "FAIL: no watermark"; exit 1; }

if [ "$changed" -eq 0 ]; then echo "== converged: no changes"; else echo "== converged: relay installed + running"; fi
