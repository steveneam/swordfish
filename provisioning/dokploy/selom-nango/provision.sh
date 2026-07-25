#!/usr/bin/env bash
# provision.sh - converge selom's self-hosted Nango OAuth broker on syd2
# (owner-approved 2026-07-23; stood up live the same day, THIS script is the
# rule-9 capture - the compose previously existed only in Dokploy state, so a
# syd2 rebuild could not have recreated it).
#
#   usage: provision.sh          (no args; idempotent - re-run prints state)
#     env: DOKPLOY_URL      (default https://deploy.swordfish.cfd)
#          DOKPLOY_KEY_NAME (.env var holding the ADMIN key; default
#                            DOKPLOY_SYD2_API_KEY)
#
# What it converges (Dokploy project selom -> compose `nango`):
#   1. project `selom` (created if absent) + its single production environment
#   2. compose service `nango`: sourceType raw, composeFile = ./compose.yml
#      (kept verbatim in this directory - edit THERE, re-run HERE)
#   3. tenant env from inventory/secrets/dokploy-tenant-selom-nango.env
#      (0600, gitignored) via compose.saveEnvironment - the DEDICATED safe
#      endpoint (application.saveEnvironment REPLACES env; this one is scoped)
#   4. deploy + poll until composeStatus=done
#   5. domain nango.swordfish.cfd -> nango-server:3003, https, letsencrypt
#      (swordfish.cfd BY FOUNDER CALL - selom.app stays dark pre-launch, CT
#      logs are forever; DNS A record is porkbun's lane, checked not written)
#   6. outside-in verification: /health 200 AND /connection 401 (the 401 is
#      load-bearing - it proves the server API is auth-gated, not open)
#
# ⚠ NANGO_ENCRYPTION_KEY: NEVER ROTATE. It encrypts stored OAuth tokens at
# rest; a new key silently orphans every existing connection. Restore story
# lives in README.md (dump hook: backup/pre-backup.d/40-nango-postgres-dump).
# Secrets ride env vars, files, and stdin - never argv (house rule).

set -euo pipefail
cd "$(dirname "$0")/../../.."

PROJECT=selom
SERVICE=nango
HOSTNAME_PUB=nango.swordfish.cfd
SECFILE=inventory/secrets/dokploy-tenant-selom-nango.env
COMPOSE_SRC=provisioning/dokploy/selom-nango/compose.yml
# exactly the keys compose.yml interpolates (:?required); DASHBOARD_USERNAME
# is baked into the compose on purpose - not injected
ENV_KEYS="NANGO_ENCRYPTION_KEY NANGO_DB_USER NANGO_DB_PASSWORD NANGO_DB_NAME NANGO_DASHBOARD_PASSWORD"
DOKPLOY_URL=${DOKPLOY_URL:-https://deploy.swordfish.cfd}
DOKPLOY_KEY_NAME=${DOKPLOY_KEY_NAME:-DOKPLOY_SYD2_API_KEY}

[ -f "$COMPOSE_SRC" ] || { echo "FAIL: $COMPOSE_SRC missing"; exit 1; }
[ -f "$SECFILE" ] || { echo "FAIL: $SECFILE missing - the tenant secrets are founder-held, restore them first"; exit 1; }

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

# --- 1. project + its single environment (create project once) -------------------
resolve() { # prints "envId\ncomposeIds-csv" or "ABSENT"
    admin GET project.all | python3 -c '
import json, sys
name = sys.argv[1]
hits = [p for p in json.load(sys.stdin) if p["name"] == name]
if not hits:
    print("ABSENT"); sys.exit()
if len(hits) != 1:
    sys.exit(f"FAIL: {len(hits)} projects named {name!r}")
envs = hits[0].get("environments", [])
if len(envs) != 1:
    sys.exit(f"FAIL: expected exactly 1 environment, found {len(envs)} - pick explicitly")
print(envs[0]["environmentId"])
print(",".join(c["composeId"] for c in envs[0].get("compose", [])))
' "$PROJECT"
}
state=$(resolve)
if [ "$state" = ABSENT ]; then
    printf '{"name":"%s","description":"Selom tenant on syd2. First service: self-hosted Nango (OAuth broker for cloud-storage integrations). Owner-approved 2026-07-23; selom owns the app, swordfish owns box+edge."}' "$PROJECT" \
        | admin POST project.create >/dev/null
    echo "CHANGED: project $PROJECT created"
    state=$(resolve)
    [ "$state" != ABSENT ] || { echo "FAIL: project.create did not land"; exit 1; }
fi
ENV_ID=$(sed -n 1p <<<"$state"); CANDIDATES=$(sed -n 2p <<<"$state")
echo "OK: project $PROJECT environment $ENV_ID"

# --- 2. find-or-create the compose (existence by compose.one per id - same
# bare-id listing quirk as tenant-pg.sh found live 2026-07-14) -------------------
COMPOSE_ID=""
for id in ${CANDIDATES//,/ }; do
    name=$(admin GET "compose.one?composeId=$id" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name",""))')
    if [ "$name" = "$SERVICE" ]; then COMPOSE_ID=$id; break; fi
done
if [ -n "$COMPOSE_ID" ]; then
    echo "OK: compose $SERVICE exists ($COMPOSE_ID)"
else
    COMPOSE_ID=$(printf '{"name":"%s","environmentId":"%s","composeType":"docker-compose","description":"Self-hosted Nango (OAuth broker) for Selom cloud-storage integrations. Public at %s (infra domain; selom.app stays dark pre-launch). Owner-approved 2026-07-23."}' \
            "$SERVICE" "$ENV_ID" "$HOSTNAME_PUB" \
        | admin POST compose.create \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("composeId") or "")')
    [ -n "$COMPOSE_ID" ] || { echo "FAIL: compose.create returned no composeId"; exit 1; }
    echo "CHANGED: compose created ($COMPOSE_ID)"
fi

# --- 3. converge composeFile (raw source of truth = this directory) ---------------
want=$(cat "$COMPOSE_SRC")
have=$(admin GET "compose.one?composeId=$COMPOSE_ID" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("composeFile") or "")')
if [ "$have" = "$want" ]; then
    echo "OK: composeFile matches $COMPOSE_SRC"
    DEPLOY_NEEDED=0
else
    python3 -c '
import json, sys
print(json.dumps({"composeId": sys.argv[1], "sourceType": "raw",
                  "composeFile": open(sys.argv[2]).read(),
                  "composePath": "docker-compose.yml", "autoDeploy": False}))
' "$COMPOSE_ID" "$COMPOSE_SRC" | admin POST compose.update >/dev/null
    echo "CHANGED: composeFile -> Dokploy (from $COMPOSE_SRC)"
    DEPLOY_NEEDED=1
fi

# --- 4. converge tenant env from the off-git secrets file -------------------------
# compose.saveEnvironment is the dedicated endpoint (protocol note: safe,
# unlike application.saveEnvironment which replaces). Values pass file->pipe->
# API, never argv, never stdout.
have_env=$(admin GET "compose.one?composeId=$COMPOSE_ID" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("env") or "")')
want_env=$(python3 -c '
import sys
keys = sys.argv[2].split()
vals = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        vals[k.strip()] = v.strip().strip("\"")
missing = [k for k in keys if k not in vals or not vals[k]]
if missing:
    sys.exit(f"FAIL: {sys.argv[1]} missing keys: {missing}")
print("\n".join(f"{k}=\"{vals[k]}\"" for k in keys))
' "$SECFILE" "$ENV_KEYS")
if [ "$have_env" = "$want_env" ]; then
    echo "OK: tenant env matches $SECFILE ($(wc -w <<<"$ENV_KEYS") keys)"
else
    python3 -c 'import json,sys; print(json.dumps({"composeId": sys.argv[1], "env": sys.stdin.read()}))' \
        "$COMPOSE_ID" <<<"$want_env" | admin POST compose.saveEnvironment >/dev/null
    echo "CHANGED: tenant env -> Dokploy ($(wc -w <<<"$ENV_KEYS") keys, names: $ENV_KEYS)"
    DEPLOY_NEEDED=1
fi

# --- 5. deploy if anything changed (or first run), poll to done -------------------
status=$(admin GET "compose.one?composeId=$COMPOSE_ID" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("composeStatus",""))')
if [ "${DEPLOY_NEEDED:-1}" = 1 ] || [ "$status" != done ]; then
    printf '{"composeId":"%s"}' "$COMPOSE_ID" | admin POST compose.deploy >/dev/null
    echo "OK: deploy dispatched"
    for _ in $(seq 1 36); do
        status=$(admin GET "compose.one?composeId=$COMPOSE_ID" \
            | python3 -c 'import json,sys; print(json.load(sys.stdin).get("composeStatus",""))')
        case "$status" in
            done) break ;;
            error) echo "FAIL: composeStatus=error - read Dokploy deploy logs"; exit 1 ;;
        esac
        sleep 5
    done
    [ "$status" = done ] || { echo "FAIL: compose never reached done (last: $status)"; exit 1; }
fi
echo "OK: composeStatus=done"

# --- 6. domain: exactly one, ours ------------------------------------------------
dom_state=$(admin GET "domain.byComposeId?composeId=$COMPOSE_ID" | python3 -c '
import json, sys
doms = json.load(sys.stdin)
host = sys.argv[1]
ours = [d for d in doms if d.get("host") == host]
others = [d.get("host") for d in doms if d.get("host") != host]
if others:
    sys.exit(f"FAIL: unexpected extra domains on this compose: {others}")
print("PRESENT" if ours else "ABSENT")
' "$HOSTNAME_PUB")
if [ "$dom_state" = ABSENT ]; then
    printf '{"host":"%s","https":true,"port":3003,"path":"/","serviceName":"nango-server","domainType":"compose","certificateType":"letsencrypt","composeId":"%s"}' \
            "$HOSTNAME_PUB" "$COMPOSE_ID" | admin POST domain.create >/dev/null
    printf '{"composeId":"%s"}' "$COMPOSE_ID" | admin POST compose.deploy >/dev/null
    echo "CHANGED: domain $HOSTNAME_PUB attached, redeploy dispatched (LE needs DNS: an A record via porkbun's lane + up to ~1 min issuance)"
    sleep 30
else
    echo "OK: domain $HOSTNAME_PUB attached"
fi

# --- 7. outside-in verification (capture-then-compare, never verdict pipes) -------
health=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' "https://$HOSTNAME_PUB/health" || echo curl-fail)
gate=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' "https://$HOSTNAME_PUB/connection" || echo curl-fail)
[ "$health" = 200 ] || { echo "FAIL: /health returned $health (want 200)"; exit 1; }
[ "$gate" = 401 ] || { echo "FAIL: /connection returned $gate (want 401 - the server API must be auth-gated)"; exit 1; }
echo "OK: outside-in - /health 200, /connection 401 (auth-gated)"
echo "== converged: $PROJECT/$SERVICE on syd2 (compose $COMPOSE_ID) at https://$HOSTNAME_PUB"
