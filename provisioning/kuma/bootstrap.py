# provisioning/kuma/bootstrap.py - Bucket 4: Uptime Kuma config-as-code over
# its socket.io API (Kuma has no REST admin API; this IS the scripted channel,
# proven against 2.4.0). Idempotent: creates only what is missing, keyed by
# name. Run from the laptop: python provisioning/kuma/bootstrap.py
#   deps: pip install --user python-socketio websocket-client requests
#
# What it converges (runbook: runbooks/dogfood.md):
#   - SQLite choice + admin account (user: swordfish; password generated into
#     inventory/secrets/kuma-admin.password on first run - gitignored)
#   - ntfy notification -> topic from inventory/secrets/ntfy-topic.txt
#   - push monitor swordfish-syd1-backup (dead-man on-infra half; interval
#     108000s = 24h backup period + 6h grace, mirrors healthchecks.io);
#     its push URL lands in inventory/secrets/kuma-push-url.txt -> must match
#     the KUMA_PUSH_URL repo secret (backups-apply installs it on-box)
#   - HTTP monitors for the public TLS surfaces (60s interval, cert-expiry on)
#
# API landmines learned 2026-07-07 (do not relearn):
#   - "add" ignores isDefault notifications: attach notificationIDList
#     explicitly via editMonitor after creation
#   - push monitors get NO pushToken from "add" - mint one and set it via
#     editMonitor, or the push URL 404s
#   - monitorList / notificationList arrive as server-push events right after
#     login, not as call results - register handlers BEFORE logging in

import secrets
import sys
import time
from pathlib import Path

import requests
import socketio

BASE = "https://status.swordfish.cfd"
USER = "swordfish"
REPO = Path(__file__).resolve().parents[2]
SEC = REPO / "inventory" / "secrets"

NOTI_NAME = "ntfy -> founder phone"
HTTP_MONITORS = [
    ("deploy (control plane)", "https://deploy.swordfish.cfd"),
    ("metrics (beszel)", "https://metrics.swordfish.cfd"),
    ("hello (deploy receipt)", "https://hello.swordfish.cfd"),
]


def read_or_create(path: Path, gen):
    if path.exists():
        return path.read_text().strip()
    val = gen()
    path.write_text(val + "\n")
    print(f"generated {path.name}")
    return val


def main():
    pw = read_or_create(SEC / "kuma-admin.password", lambda: secrets.token_urlsafe(24))
    topic = read_or_create(SEC / "ntfy-topic.txt", lambda: "swordfish-" + secrets.token_hex(8))

    # ---- first boot: pick sqlite, wait for the app to come back ----------
    s = requests.Session()
    r = s.get(BASE + "/", allow_redirects=False, timeout=15)
    if "/setup-database" in (r.headers.get("location") or ""):
        r = s.post(BASE + "/setup-database", json={"dbConfig": {"type": "sqlite"}}, timeout=30)
        print("setup-database:", r.status_code)
        for _ in range(30):
            time.sleep(2)
            try:
                if "/setup-database" not in (s.get(BASE + "/", allow_redirects=False, timeout=10).headers.get("location") or ""):
                    break
            except requests.RequestException:
                pass

    # ---- socket.io session ------------------------------------------------
    sio = socketio.Client(logger=False)
    pushed = {}  # server-push snapshots, filled by the handlers below
    sio.on("monitorList", lambda data: pushed.update(monitors=data))
    sio.on("notificationList", lambda data: pushed.update(notis=data))
    sio.connect(BASE, transports=["websocket"], wait_timeout=20)

    def call(event, *args):
        done = {}
        sio.emit(event, args, callback=lambda res: done.update(res=res))
        for _ in range(150):
            if "res" in done:
                return done["res"]
            time.sleep(0.2)
        raise TimeoutError(f"kuma api call timed out: {event}")

    def wait_pushed(key, seconds=8):
        for _ in range(int(seconds / 0.2)):
            if key in pushed:
                return pushed[key]
            time.sleep(0.2)
        sys.exit(f"FAIL: server never pushed {key} after login - aborting rather than creating duplicates")

    if call("needSetup") is True:
        print("setup:", call("setup", USER, pw))
    res = call("login", {"username": USER, "password": pw, "token": ""})
    if not (isinstance(res, dict) and res.get("ok")):
        sys.exit(f"FAIL: kuma login rejected: {res}")
    print("login: ok")

    # ---- notification (keyed by name) --------------------------------------
    notis = wait_pushed("notis")
    hit = [n for n in notis if n.get("name") == NOTI_NAME]
    if hit:
        noti_id = hit[0]["id"]
        print(f"notification exists (id {noti_id})")
    else:
        res = call("addNotification", {
            "name": NOTI_NAME, "type": "ntfy", "isDefault": True, "applyExisting": True,
            "ntfyAuthenticationMethod": "none", "ntfyserverurl": "https://ntfy.sh",
            "ntfytopic": topic, "ntfyPriority": 5,
        }, None)
        noti_id = res.get("id")
        print(f"notification created (id {noti_id})")

    # ---- monitors (keyed by name) -------------------------------------------
    monitors = wait_pushed("monitors")
    by_name = {m["name"]: m for m in (monitors.values() if isinstance(monitors, dict) else monitors)}

    def ensure_monitor(spec):
        if spec["name"] in by_name:
            print(f"monitor exists: {spec['name']} (id {by_name[spec['name']]['id']})")
            return by_name[spec["name"]]["id"]
        res = call("add", spec)
        if not res.get("ok"):
            sys.exit(f"FAIL: add {spec['name']}: {res}")
        print(f"monitor created: {spec['name']} (id {res['monitorID']})")
        return res["monitorID"]

    base_fields = {
        "resendInterval": 0, "upsideDown": False, "active": True,
        "accepted_statuscodes": ["200-299"], "notificationIDList": {}, "conditions": [],
    }
    push_id = ensure_monitor({
        "type": "push", "name": "swordfish-syd1-backup",
        "interval": 108000, "retryInterval": 3600, "maxretries": 0, **base_fields,
    })
    http_ids = [ensure_monitor({
        "type": "http", "name": name, "url": url, "method": "GET",
        "interval": 60, "retryInterval": 60, "maxretries": 2,
        "expiryNotification": True, "ignoreTls": False, "maxredirects": 10, **base_fields,
    }) for name, url in HTTP_MONITORS]

    # ---- attach notification + ensure push token -----------------------------
    for mid in [push_id, *http_ids]:
        mon = call("getMonitor", mid)["monitor"]
        changed = False
        if not mon.get("notificationIDList"):
            mon["notificationIDList"] = {str(noti_id): True}
            changed = True
        if mon["type"] == "push" and not mon.get("pushToken"):
            mon["pushToken"] = "pk_" + secrets.token_hex(16)
            changed = True
        if changed:
            res = call("editMonitor", mon)
            print(f"monitor {mid} patched:", res.get("ok"))

    mon = call("getMonitor", push_id)["monitor"]
    url = f"{BASE}/api/push/{mon['pushToken']}"
    (SEC / "kuma-push-url.txt").write_text(url + "\n")
    print("push URL -> inventory/secrets/kuma-push-url.txt")
    print("REMINDER: keep the KUMA_PUSH_URL repo secret in sync (gh secret set), then backups-apply")

    sio.disconnect()


if __name__ == "__main__":
    main()
