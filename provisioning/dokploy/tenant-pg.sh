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
# QUIRK (found live 2026-07-14, the hard way - a re-run duplicated the
# service): project.all lists postgres services as BARE {postgresId} entries,
# no name field. Existence must be resolved by postgres.one per id.
state=$(admin GET project.all | python3 -c '
import json, sys
name = sys.argv[1]
hits = [p for p in json.load(sys.stdin) if p["name"] == name]
if len(hits) != 1:
    sys.exit(f"FAIL: {len(hits)} projects named {name!r}")
envs = hits[0].get("environments", [])
if len(envs) != 1:
    sys.exit(f"FAIL: expected exactly 1 environment, found {len(envs)} - pick explicitly")
print(envs[0]["environmentId"])
print(",".join(g["postgresId"] for g in envs[0].get("postgres", [])))
' "$PROJECT")
ENV_ID=$(sed -n 1p <<<"$state"); CANDIDATES=$(sed -n 2p <<<"$state")
echo "OK: project $PROJECT environment $ENV_ID"
PG_ID=""
for id in ${CANDIDATES//,/ }; do
    name=$(admin GET "postgres.one?postgresId=$id" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name",""))')
    if [ "$name" = "$SERVICE" ]; then PG_ID=$id; break; fi
done

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
STATUS="" EXT="" HOST="" IMG=""
for _ in $(seq 1 24); do
    read -r STATUS EXT HOST IMG < <(admin GET "postgres.one?postgresId=$PG_ID" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("applicationStatus", "?"), json.dumps(d.get("externalPort")),
      d.get("appName", "?"), d.get("dockerImage", "?"))')
    case "$STATUS" in
        done|running) break ;;
        error) echo "FAIL: service status=error - read Dokploy logs"; exit 1 ;;
    esac
    sleep 5
done
case "$STATUS" in done|running) ;; *)
    echo "FAIL: service never reached done/running (last: $STATUS)"; exit 1 ;; esac
echo "OK: service status=$STATUS image=$IMG"
[ "$EXT" = null ] \
    || { echo "FAIL: externalPort=$EXT - tenant-pg must NEVER publish a port"; exit 1; }
echo "OK: no external port (internal docker network only)"

# --- 3b. memory cap (blast containment, security review 2026-07-14) --------------
# Dokploy stores resource limits as bytes-in-a-string and applies them to the
# swarm service spec. 512 MiB = >=9x the observed 6-day peak (~55 MB) with
# headroom for the Project 2 tenant; a runaway query OOMs this container, not
# the box. The setting lands on the NEXT reload/deploy - hardening-smoke's
# "workloads: all memory-capped" assertion is what verifies the running
# container, so reload after changing this.
MEM_LIMIT=536870912
cur=$(admin GET "postgres.one?postgresId=$PG_ID" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("memoryLimit") or "")')
if [ "$cur" = "$MEM_LIMIT" ]; then
    echo "OK: memoryLimit=$MEM_LIMIT"
else
    printf '{"postgresId":"%s","memoryLimit":"%s"}' "$PG_ID" "$MEM_LIMIT" | admin POST postgres.update >/dev/null
    echo "CHANGED: memoryLimit -> $MEM_LIMIT (applies on next reload/deploy)"
fi

# --- 4. record the real in-network host - appName gets a random suffix at ---------
# create and is immutable after (dogfood quirk ledger), so tenants must use
# THIS, not the service name
if ! grep -qx "PG_HOST=$HOST" "$SECFILE" 2>/dev/null; then
    umask 077
    { grep -v '^PG_HOST=' "$SECFILE" 2>/dev/null || true
      echo "PG_HOST=$HOST"; } > "$SECFILE.tmp"
    mv "$SECFILE.tmp" "$SECFILE"
    echo "CHANGED: PG_HOST=$HOST -> $SECFILE"
fi
echo "== converged: $SERVICE on syd2 (id $PG_ID; in-network host '$HOST', port 5432)"
