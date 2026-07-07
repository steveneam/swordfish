# provisioning/uptimerobot/bootstrap.py - Bucket 4: UptimeRobot as the second
# off-infra witness (CHARTER pinned decision 8; healthchecks.io is the first).
# Independent company, independent probes, alerts to the founder's email even
# if the whole box + Kuma are down. Idempotent, keyed by URL.
# Run from the laptop: python provisioning/uptimerobot/bootstrap.py
#   deps: requests. Key: UPTIMEROBOT_API_KEY in the gitignored .env (the MAIN
#   api key from the dashboard).
#
# API landmines learned 2026-07-07 (do not relearn):
#   - Accounts created 2025+ are v3-native: v2 newMonitor returns
#     access_denied "not allowed ... with your current plan" even with the
#     main key. Use v3 (Bearer auth, JSON) for writes.
#   - v3 monitor create REQUIRES timeout (<=60) and, if alert contacts are
#     assigned, integer threshold + recurrence per contact.
# Free tier: 5-minute interval - fine for a witness; Kuma (60s) remains the
# primary/fast alerting path (runbooks/dogfood.md).

import sys
from pathlib import Path

import requests

API = "https://api.uptimerobot.com/v3"
REPO = Path(__file__).resolve().parents[2]

MONITORS = [
    ("swordfish status (kuma)", "https://status.swordfish.cfd"),
    ("swordfish deploy (control plane)", "https://deploy.swordfish.cfd"),
]


def read_dotenv(name):
    for line in (REPO / ".env").read_text().splitlines():
        if line.strip().startswith(name + "="):
            return line.split("=", 1)[1].strip()
    sys.exit(f"FAIL: {name} not found in .env")


def main():
    key = read_dotenv("UPTIMEROBOT_API_KEY")
    s = requests.Session()
    s.headers.update({"Authorization": f"Bearer {key}", "Content-Type": "application/json"})

    r = s.get(f"{API}/alert-contacts", timeout=20)
    r.raise_for_status()
    email = [c for c in r.json()["data"] if c.get("type") == "Email" and c.get("status") == "Active"]
    if not email:
        sys.exit("FAIL: no active email alert contact - add one in the UptimeRobot dashboard first")
    contact_id = str(email[0]["id"])
    print(f"alert contact: {email[0]['value']} (id {contact_id})")

    r = s.get(f"{API}/monitors", timeout=20)
    r.raise_for_status()
    existing = {m["url"] for m in r.json()["data"]}

    for name, url in MONITORS:
        if url in existing:
            print(f"monitor exists: {url}")
            continue
        r = s.post(f"{API}/monitors", json={
            "friendlyName": name, "url": url, "type": "HTTP",
            "interval": 300, "timeout": 30,
            "assignedAlertContacts": [{"alertContactId": contact_id, "threshold": 0, "recurrence": 0}],
        }, timeout=20)
        if r.status_code != 201:
            sys.exit(f"FAIL: create {url}: {r.status_code} {r.text[:300]}")
        print(f"monitor created: {url}")


if __name__ == "__main__":
    main()
