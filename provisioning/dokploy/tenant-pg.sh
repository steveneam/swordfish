#!/usr/bin/env bash
# tenant-pg.sh - converge the shared tenant Postgres service on syd2
# (founder call 2026-07-13: self-hosted Postgres 17 for Thalon + Project 2 on
# the EXISTING box, zero new spend; Project 1's clinical DB stays on managed
# Supabase - keep-managed invariant).
#
#   usage: tenant-pg.sh          (no args; idempotent - re-run prints state)
#     env: DOKPLOY_URL      (default https://deploy.swordfish.cfd)
#          DOKPLOY_KEY_NAME (.env var holding the ADMIN key; default
#                            DOKPLOY_SYD2_API_KEY)
#
# What it converges:
#   1. one Dokploy postgres service `tenant-pg` (postgres:17.10, version-pinned)
#      in the swordfish project - superuser `swordfish`, password generated
#      once into inventory/secrets/pg-syd2.env (0600, gitignored)
#   2. deploy + poll until the service reports done/running
#   3. verification: externalPort must be null - the DB lives on the internal
#      docker network ONLY; tenant apps on the same box reach it by appName
#      DNS; there is deliberately NO public 5432 (hardening-smoke asserts the
#      box side)
#
# Per-tenant databases/roles are NOT this script's job - that is
# tenant-db.sh (CI-as-hands; syd2's inbound 22 answers CI only).
# Backup chain: pre-backup.d/15-tenant-pg-dump + the restore drill - which
# must be green BEFORE any tenant database is provisioned (invariant).
# Secrets ride env vars, files, and stdin - never argv (house rule).

set -euo pipefail
cd "$(dirname "$0")/../.."

SERVICE=tenant-pg
IMAGE=postgres:17.10        # founder call pinned major 17; bump minor deliberately
PROJECT=swordfish
SUPERUSER=swordfish
SECFILE=inventory/secrets/pg-syd2.env
DOKPLOY_URL=${DOKPLOY_URL:-https://deploy.swordfish.cfd}
DOKPLOY_KEY_NAME=${DOKPLOY_KEY_NAME:-DOKPLOY_SYD2_API_KEY}

envval() { grep "^$1=" .env | cut -d= -f2- | tr -d '\r' | sed 's/^ *//'; }
ADMIN_KEY=$(envval "$DOKPLOY_KEY_NAME")
[ -n "$ADMIN_KEY" ] || { echo "FAIL: $DOKPLOY_KEY_NAME not in .env"; exit 1; }

admin() { # method path [json-stdin]
    local m=$1 p=$2
    if [ "$m" = GET ]; then
        curl -sS -m 30 -K <(printf 'header = "x-api-key: %s"\n' "$ADMIN_KEY") "$DOKPLOY_URL/api/$p"
    else
        curl -sS -m 30 -K <(printf 'header = "x-api-key: %s"\nheader = "Content-Type: application/json"\n' "$ADMIN_KEY") \
             -X POST --data-binary @- "$DOKPLOY_URL/api/$p"
    fi
}

# --- 1. resolve the project's single environment + any existing service ----------
# (project.all nests postgres services under each environment)
state=$(admin GET project.all | python3 -c '
import json, sys
name, svc = sys.argv[1], sys.argv[2]
hits = [p for p in json.load(sys.stdin) if p["name"] == name]
if len(hits) != 1:
    sys.exit(f"FAIL: {len(hits)} projects named {name!r}")
envs = hits[0].get("environments", [])
if len(envs) != 1:
    sys.exit(f"FAIL: expected exactly 1 environment, found {len(envs)} - pick explicitly")
env = envs[0]
pgs = [g for g in env.get("postgres", []) if g.get("name") == svc]
print(env["environmentId"])
print(pgs[0]["postgresId"] if pgs else "")
' "$PROJECT" "$SERVICE")
ENV_ID=$(sed -n 1p <<<"$state"); PG_ID=$(sed -n 2p <<<"$state")
echo "OK: project $PROJECT environment $ENV_ID"

# --- 2. create once (password persisted first, so a crash never strands it) ------
if [ -n "$PG_ID" ]; then
    echo "OK: service $SERVICE exists ($PG_ID)"
    grep -q '^PG_SUPERPASS=' "$SECFILE" 2>/dev/null \
        || echo "WARN: $SERVICE exists but $SECFILE has no PG_SUPERPASS - recover it from Dokploy UI"
else
    PASSWORD=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
    umask 077
    { echo "# syd2 tenant Postgres superuser (service $SERVICE, $DOKPLOY_URL)"
      echo "PG_SUPERUSER=$SUPERUSER"
      echo "PG_SUPERPASS=$PASSWORD"; } > "$SECFILE"
    PG_ID=$(python3 -c '
import json, sys
print(json.dumps({"name": sys.argv[1], "appName": sys.argv[1],
                  "databaseName": sys.argv[2], "databaseUser": sys.argv[2],
                  "databasePassword": sys.stdin.read().strip(),
                  "dockerImage": sys.argv[3], "environmentId": sys.argv[4],
                  "description": "shared tenant Postgres (per-tenant DBs via tenant-db.sh)"}))
' "$SERVICE" "$SUPERUSER" "$IMAGE" "$ENV_ID" <<<"$PASSWORD" \
        | admin POST postgres.create \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("postgresId") or "")')
    [ -n "$PG_ID" ] || { echo "FAIL: postgres.create returned no postgresId"; exit 1; }
    echo "CHANGED: service created ($PG_ID), superuser password -> $SECFILE"
    printf '{"postgresId":"%s"}' "$PG_ID" | admin POST postgres.deploy >/dev/null
    echo "OK: deploy dispatched"
fi

# --- 3. poll until running, then verify the no-public-port invariant --------------
for _ in $(seq 1 24); do
    read -r STATUS EXT IMG < <(admin GET "postgres.one?postgresId=$PG_ID" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("applicationStatus", "?"), json.dumps(d.get("externalPort")), d.get("dockerImage", "?"))')
    [ "$STATUS" = done ] || [ "$STATUS" = running ] && break
    [ "$STATUS" = error ] && { echo "FAIL: service status=error - read Dokploy logs"; exit 1; }
    sleep 5
done
[ "$STATUS" = done ] || [ "$STATUS" = running ] \
    || { echo "FAIL: service never reached done/running (last: $STATUS)"; exit 1; }
echo "OK: service status=$STATUS image=$IMG"
[ "$EXT" = null ] \
    || { echo "FAIL: externalPort=$EXT - tenant-pg must NEVER publish a port"; exit 1; }
echo "OK: no external port (internal docker network only)"
echo "== converged: $SERVICE on syd2 (id $PG_ID; in-network host '$SERVICE', port 5432)"
