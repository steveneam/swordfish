#!/usr/bin/env bash
set -euo pipefail

# setup-b2-watch.sh - daily B2 storage early-warning (ratchet from free-cap
# incident #3, 2026-08-01; prior brushes 07-17 and 07-25).
#
# WHY: the 10 GB B2 free cap fails CLOSED - at cap, b2_get_upload_url 403s
# account-wide, restic cannot even upload its own lock file, so backups AND
# the prune that would free space both wedge (catch-22 proven live twice).
# Every incident so far was discovered only after nightlies had already been
# failing for days. The healthchecks dead-man fires at that same too-late
# moment. This watcher alerts at 8 GiB - days of lead time while every fix
# (forget/prune/exclude) still works.
#
# WHAT: daily timer on the cockpit box (syd4 - the only box holding the
# master B2 key) sums ALL bucket bytes via the B2 API and pushes ONE ntfy
# note to the founder's phone iff total >= threshold. Below threshold it
# logs the total to the journal and stays silent. Numbers only, never
# credentials, are ever printed.
#
# SYD4-ONLY, deliberately: reads the master key from the swordfish repo's
# gitignored .env and the ntfy topic from inventory/secrets/ - neither
# exists (nor should exist) on any other box.
#
# Idempotent converge + verify, same family as setup-peer-mail-watch.sh.

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

install_if_changed 0755 /usr/local/bin/swordfish-b2-watch.sh <<'WATCH'
#!/usr/bin/env bash
# Fired by swordfish-b2-watch.timer (daily). Exit 1 on any failure so the
# unit lands in `systemctl --failed`, which the fleet status sweep reads -
# a broken watcher must be visible, but must not page the phone.
set -euo pipefail

ENV_FILE=/home/deploy/work/swordfish/.env
TOPIC_FILE=/home/deploy/work/swordfish/inventory/secrets/ntfy-topic.txt
THRESHOLD_GIB=${B2_WATCH_THRESHOLD_GIB:-8.0}

[ -r "$ENV_FILE" ] || { echo "FAIL: $ENV_FILE not readable"; exit 1; }
[ -r "$TOPIC_FILE" ] || { echo "FAIL: $TOPIC_FILE not readable"; exit 1; }

total=$(python3 - "$ENV_FILE" <<'PY'
import base64, json, sys, urllib.request
kid = key = None
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip().replace("\r", "")
        if line.startswith("B2_APPLICATION_KEY_ID="):
            kid = line.split("=", 1)[1].strip()
        elif line.startswith("B2_APPLICATION_KEY="):
            key = line.split("=", 1)[1].strip()
if not kid or not key:
    sys.exit("no B2 master key in env file")

def post(url, token, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
        headers={"Authorization": token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)

basic = "Basic " + base64.b64encode(f"{kid}:{key}".encode()).decode()
req = urllib.request.Request(
    "https://api.backblazeb2.com/b2api/v2/b2_authorize_account",
    headers={"Authorization": basic})
with urllib.request.urlopen(req, timeout=60) as r:
    auth = json.load(r)
api, tok, acct = auth["apiUrl"], auth["authorizationToken"], auth["accountId"]

total = 0
for b in post(f"{api}/b2api/v2/b2_list_buckets", tok, {"accountId": acct})["buckets"]:
    start_name = start_id = None
    while True:
        body = {"bucketId": b["bucketId"], "maxFileCount": 10000}
        if start_name is not None:
            body["startFileName"] = start_name
            if start_id: body["startFileId"] = start_id
        resp = post(f"{api}/b2api/v2/b2_list_file_versions", tok, body)
        total += sum(f.get("contentLength") or 0 for f in resp["files"])
        if resp.get("nextFileName") is None:
            break
        start_name, start_id = resp["nextFileName"], resp.get("nextFileId")
print(f"{total/2**30:.2f}")
PY
)

echo "b2-watch: total stored ${total} GiB (cap 9.31 GiB, alert >= ${THRESHOLD_GIB})"

over=$(python3 -c "import sys; print(1 if float('${total}') >= float('${THRESHOLD_GIB}') else 0)")
if [ "$over" = "1" ]; then
  topic=$(tr -d ' \r\n' < "$TOPIC_FILE")
  msg="⚠️ unexpected - B2 backup storage at ${total} GiB of the 9.31 GiB free cap (early-warning threshold ${THRESHOLD_GIB}). At cap, ALL nightly backups hard-block and cannot self-prune. No action needed from you: any swordfish session sees this and runs the cap playbook - but do not clear the alert as noise if it repeats."
  logger -t swordfish-alerts "$msg"
  curl -fsS -m 15 -d "$msg" "https://ntfy.sh/${topic}" >/dev/null
fi
exit 0
WATCH

install_if_changed 0644 /etc/systemd/system/swordfish-b2-watch.service <<'UNIT'
[Unit]
Description=swordfish: B2 storage early-warning (free-cap watchdog)

[Service]
Type=oneshot
User=deploy
ExecStart=/usr/local/bin/swordfish-b2-watch.sh
UNIT

install_if_changed 0644 /etc/systemd/system/swordfish-b2-watch.timer <<'TIMER'
[Unit]
Description=swordfish: daily B2 storage check 11:00 UTC

[Timer]
# 11:00 UTC: clear of the 06:2x apt window, the 15:00 nightly backups, the
# Sat 17:00 prune, and the 18:30 reboot window.
OnCalendar=*-*-* 11:00:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER

if [ "$changed" -eq 1 ]; then
  sudo systemctl daemon-reload
fi
if ! systemctl is-enabled --quiet swordfish-b2-watch.timer 2>/dev/null; then
  sudo systemctl enable --now swordfish-b2-watch.timer
  changed=1
fi

# --- verify ------------------------------------------------------------------
systemctl is-active --quiet swordfish-b2-watch.timer || { echo "FAIL: timer inactive"; exit 1; }
out=$(sudo -u deploy /usr/local/bin/swordfish-b2-watch.sh) || { echo "FAIL: watcher errored"; echo "$out"; exit 1; }
grep -q 'b2-watch: total stored' <<<"$out" || { echo "FAIL: watcher produced no total"; exit 1; }
echo "$out"

if [ "$changed" -eq 0 ]; then
  echo "== converged: no changes (b2-watch armed daily 11:00 UTC)"
else
  echo "== converged: b2-watch armed daily 11:00 UTC"
fi
