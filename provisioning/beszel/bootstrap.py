# provisioning/beszel/bootstrap.py - Bucket 4: Beszel hub config-as-code over
# its PocketBase REST API (proven against 0.18.7). Idempotent: creates only
# what is missing. Run from the laptop: python provisioning/beszel/bootstrap.py
#   deps: pip install --user requests
#
# What it converges (runbook: runbooks/dogfood.md):
#   - first admin account (ops@swordfish.cfd; password generated into
#     inventory/secrets/beszel-admin.password on first run - gitignored)
#   - hub SSH public key -> inventory/secrets/beszel-hub-pubkey.txt; this
#     value must be saved as BESZEL_AGENT_KEY in the Dokploy metrics service
#     env (compose-saveEnvironment) + redeployed for the agent to accept the
#     hub - see compose/metrics/compose.yaml header
#   - the syd1 system record (host "agent" = the compose service DNS name on
#     the internal agent network, port 45876)

import os
import secrets
import sys
from pathlib import Path

import requests

# Box-relative since the Bucket-5 migration: BESZEL_BASE overrides the target
# (pre-cutover the successor's hub lives at a temp neutral name, e.g.
# https://metrics2.swordfish.cfd); BOX names the system record. Defaults track
# the CURRENT box (syd2) - syd1's hub is converged and frozen. Admin creds
# carry over (service identity graduates with the box); the hub KEY does not -
# a fresh hub mints a new keypair, so BESZEL_AGENT_KEY must be re-saved.
BASE = os.environ.get("BESZEL_BASE", "https://metrics.swordfish.cfd")
BOX = os.environ.get("BOX", "syd2")
EMAIL = "ops@swordfish.cfd"
REPO = Path(__file__).resolve().parents[2]
SEC = REPO / "inventory" / "secrets"


def main():
    pw_file = SEC / "beszel-admin.password"
    if pw_file.exists():
        pw = pw_file.read_text().strip()
    else:
        pw = secrets.token_urlsafe(24)
        pw_file.write_text(pw + "\n")
        print("generated beszel-admin.password")

    s = requests.Session()

    # first-boot admin creation; 4xx once an account exists = fine
    r = s.post(BASE + "/api/beszel/create-user", json={"email": EMAIL, "password": pw}, timeout=15)
    print("create-user:", r.status_code, "(non-200 is fine once created)")

    r = s.post(BASE + "/api/collections/users/auth-with-password",
               json={"identity": EMAIL, "password": pw}, timeout=15)
    if r.status_code != 200:
        sys.exit(f"FAIL: auth rejected ({r.status_code}) - password drift between hub and inventory/secrets?")
    auth = r.json()
    s.headers["Authorization"] = auth["token"]
    user_id = auth["record"]["id"]
    print("auth: ok")

    r = s.get(BASE + "/api/beszel/getkey", timeout=15)
    r.raise_for_status()
    hub_key = r.json().get("key") or r.json().get("data")
    (SEC / "beszel-hub-pubkey.txt").write_text(hub_key + "\n")
    print("hub key -> inventory/secrets/beszel-hub-pubkey.txt")

    r = s.get(BASE + "/api/collections/systems/records", timeout=15)
    r.raise_for_status()
    systems = {rec["name"]: rec for rec in r.json()["items"]}
    if BOX in systems:
        rec = systems[BOX]
        print(f"system exists: {BOX} (status {rec['status']})")
    else:
        r = s.post(BASE + "/api/collections/systems/records",
                   json={"name": BOX, "host": "agent", "port": "45876",
                         "users": [user_id], "status": "pending"}, timeout=15)
        r.raise_for_status()
        print(f"system created: {BOX}")
    print("REMINDER: if the hub key changed, save BESZEL_AGENT_KEY in the Dokploy")
    print("metrics service env + redeploy (compose/metrics/compose.yaml header)")


if __name__ == "__main__":
    main()
