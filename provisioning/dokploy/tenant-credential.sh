#!/usr/bin/env bash
# tenant-credential.sh - cut (or re-verify) a PROJECT-SCOPED Dokploy API
# credential for a tenant project's own CI (founder directive 2026-07-13:
# the auto-deploy channel is part of EVERY tenant's handoff pack, not a
# thalon one-off - project agents deploy their own apps for testing; the
# scoped key is how that never widens into host-level authority).
#
#   usage: tenant-credential.sh <tenant-slug> <dokploy-project-name>
#     env: DOKPLOY_URL      (default https://deploy.swordfish.cfd; cutover 2026-07-13)
#          DOKPLOY_KEY_NAME (.env var holding the ADMIN key; default
#                            DOKPLOY_SYD2_API_KEY)
#
# What it converges (idempotent - re-run prints the existing state):
#   1. member user dokploy-<slug>-ci@swordfish.cfd (role member; password
#      generated once into inventory/secrets/dokploy-tenant-<slug>.env)
#   2. permissions pinned to exactly the named project's id + its
#      environment ids + its application ids; canAccessToAPI true;
#      docker/traefik/ssh/git + project + environment create/delete all FALSE.
#      canCreateServices=False by DEFAULT (deploy-only, Option B of security
#      review finding 2, resolved 2026-07-15): the key can application.deploy
#      + read, but cannot application.update (Dokploy gates that behind
#      service:create - there is no service:update statement) and cannot
#      create anything. Tenants bump images by re-tagging a fixed GHCR tag in
#      their own CI, then deploy. CREATE_SCOPE=1 mints the LEGACY
#      create-capable shape for a tenant still on the update-path - and
#      because permissions are RE-ASSERTED every run, re-running WITHOUT
#      CREATE_SCOPE=1 against such a tenant drops create and breaks their
#      update-path CI: coordinate the cutover first.
#   3. an API key minted AS that member (better-auth session sign-in ->
#      user.createApiKey) into the same secrets file
#   4. verification: the key reads its own app; sees ONLY its project;
#      docker.getContainers is rejected; the member's canCreateServices flag
#      is read back and flagged (WARN, or FAIL under STRICT_SCOPE=1)
#
# Blast radius of a DEPLOY-ONLY key (the default): redeploy the tenant's own
# already-configured services + read its own project. A leak cannot point the
# app at a new image, create services/composes (=> no host bind-mount escape
# path), delete anything, read other projects, or reach docker/Traefik files.
# A CREATE_SCOPE=1 legacy key additionally updates AND creates services inside
# the project - compose.create accepts host bind-mounts, so on the SHARED box
# a leaked legacy key is box-level exposure (security review 2026-07-14
# finding 2). Knobs: STRICT_SCOPE=1 hard-fails the create-capability check;
# PROBE_CREATE=1 actively tests create against prod.
# Secrets ride env vars and files, never argv (house rule).

set -euo pipefail
cd "$(dirname "$0")/../.."

SLUG=${1:?usage: tenant-credential.sh <tenant-slug> <dokploy-project-name>}
PROJECT=${2:?usage: tenant-credential.sh <tenant-slug> <dokploy-project-name>}
# slug lands in an email, a secrets-file path, and a JSON name - gate it like
# the sibling tenant-db scripts do (security review 2026-07-14; was missing here)
[[ "$SLUG" =~ ^[a-z][a-z0-9_-]{1,30}$ ]] \
  || { echo "FAIL: bad slug '$SLUG' (want ^[a-z][a-z0-9_-]{1,30}$)"; exit 1; }
DOKPLOY_URL=${DOKPLOY_URL:-https://deploy.swordfish.cfd}
DOKPLOY_KEY_NAME=${DOKPLOY_KEY_NAME:-DOKPLOY_SYD2_API_KEY}
SECFILE="inventory/secrets/dokploy-tenant-$SLUG.env"
EMAIL="dokploy-$SLUG-ci@swordfish.cfd"

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

# --- 1. resolve the project's ids ------------------------------------------------
# data rides the pipe; the program must NOT also claim stdin (heredoc+pipe
# clobber each other), hence -c
ids=$(admin GET project.all | python3 -c '
import json, sys
name = sys.argv[1]
hits = [p for p in json.load(sys.stdin) if p["name"] == name]
if len(hits) != 1:
    sys.exit(f"FAIL: {len(hits)} projects named {name!r}")
p = hits[0]
envs = p.get("environments", [])
apps = [a["applicationId"] for e in envs for a in e.get("applications", [])]
print(p["projectId"])
print(",".join(e["environmentId"] for e in envs))
print(",".join(apps))
' "$PROJECT")
PID=$(sed -n 1p <<<"$ids"); ENVS=$(sed -n 2p <<<"$ids"); APPS=$(sed -n 3p <<<"$ids")
echo "OK: project $PROJECT = $PID (envs: $ENVS; apps: $APPS)"

# --- 2. member user (find-or-create; password persisted once) ---------------------
# assignPermissions keys on the USER id, not the member-row id - and it
# answers 200 silently for an unknown id (observed live 2026-07-13), so the
# read-back verify below is load-bearing, not paranoia
member_lookup='
import json, sys
for m in json.load(sys.stdin):
    if (m.get("user") or {}).get("email") == sys.argv[1]:
        print((m.get("user") or {})["id"]); break
'
MEMBER=$(admin GET user.all | python3 -c "$member_lookup" "$EMAIL")
if [ -n "$MEMBER" ]; then
    echo "OK: member exists ($MEMBER)"
    PASSWORD=$(grep '^DOKPLOY_TENANT_PASSWORD=' "$SECFILE" | cut -d= -f2-) \
        || { echo "FAIL: member exists but $SECFILE has no password - founder call needed"; exit 1; }
else
    PASSWORD=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
    printf '{"email":"%s","password":"%s","role":"member"}' "$EMAIL" "$PASSWORD" \
        | admin POST user.createUserWithCredentials >/dev/null
    umask 077
    { echo "# scoped Dokploy credential for tenant '$SLUG' ($DOKPLOY_URL)"
      echo "DOKPLOY_TENANT_EMAIL=$EMAIL"
      echo "DOKPLOY_TENANT_PASSWORD=$PASSWORD"; } > "$SECFILE"
    MEMBER=$(admin GET user.all | python3 -c "$member_lookup" "$EMAIL")
    [ -n "$MEMBER" ] || { echo "FAIL: created user but cannot find member row"; exit 1; }
    echo "CHANGED: member created ($MEMBER), password -> $SECFILE"
fi

# --- 3. permissions pinned to the project (re-asserted every run) ------------------
python3 - "$MEMBER" "$PID" "$ENVS" "$APPS" "${CREATE_SCOPE:-0}" <<'EOF' | admin POST user.assignPermissions >/dev/null
import json, sys
member, pid, envs, apps, create_scope = sys.argv[1:6]
print(json.dumps({
    "id": member,
    "accessedProjects": [pid],
    "accessedEnvironments": [e for e in envs.split(",") if e],
    "accessedServices": [a for a in apps.split(",") if a],
    "accessedGitProviders": [], "accessedServers": [],
    "canCreateProjects": False, "canDeleteProjects": False,
    # deploy-only by default (Option B, 2026-07-15): application.update gates
    # on service:create (no service:update statement exists), so the default
    # member deploys pre-configured services but cannot repoint images or
    # create anything. CREATE_SCOPE=1 = legacy update-path shape (see header).
    "canCreateServices": create_scope == "1", "canDeleteServices": False,
    "canCreateEnvironments": False, "canDeleteEnvironments": False,
    "canAccessToDocker": False, "canAccessToTraefikFiles": False,
    "canAccessToSSHKeys": False, "canAccessToGitProviders": False,
    "canAccessToAPI": True,
}))
EOF
persisted=$(admin GET user.all | python3 -c '
import json, sys
for m in json.load(sys.stdin):
    if (m.get("user") or {}).get("email") == sys.argv[1]:
        print(m["canAccessToAPI"], ",".join(m["accessedProjects"])); break
' "$EMAIL")
[ "$persisted" = "True $PID" ] \
    || { echo "FAIL: permissions did not persist (read back: '$persisted') - assignPermissions no-ops silently on a wrong id"; exit 1; }
if [ "${CREATE_SCOPE:-0}" = 1 ]; then scope_note="canCreateServices=True LEGACY over-grant (CREATE_SCOPE=1), checked in step 5"; else scope_note="deploy-only (canCreateServices=False)"; fi
echo "OK: permissions pinned to project $PID (api member; project/env create+delete + docker/traefik/ssh OFF; $scope_note)"

# --- 4. API key minted AS the member (skip if the stored one still works) ----------
TENANT_KEY=$(grep '^DOKPLOY_TENANT_API_KEY=' "$SECFILE" 2>/dev/null | cut -d= -f2- || true)
if [ -n "$TENANT_KEY" ] && admin_ok=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' \
        -K <(printf 'header = "x-api-key: %s"\n' "$TENANT_KEY") "$DOKPLOY_URL/api/project.all") \
        && [ "$admin_ok" = 200 ]; then
    echo "OK: stored tenant API key still valid"
else
    ORG=$(admin GET organization.all | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["id"])')
    jar=$(mktemp); trap 'rm -f "$jar"' EXIT
    code=$(printf '{"email":"%s","password":"%s"}' "$EMAIL" "$PASSWORD" \
        | curl -sS -m 30 -o /dev/null -w '%{http_code}' -c "$jar" \
              -H 'Content-Type: application/json' --data-binary @- "$DOKPLOY_URL/api/auth/sign-in/email")
    [ "$code" = 200 ] || { echo "FAIL: member sign-in returned $code"; exit 1; }
    # rateLimitEnabled MUST be false: better-auth api-keys default to TEN
    # requests per DAY (observed live 2026-07-13 - the key dies mid-verify and
    # every later call is a bare session-null "Unauthorized", which reads like
    # a permission bug and is not)
    TENANT_KEY=$(printf '{"name":"%s-ci","metadata":{"organizationId":"%s"},"rateLimitEnabled":false}' "$SLUG" "$ORG" \
        | curl -sS -m 30 -b "$jar" -H 'Content-Type: application/json' \
              --data-binary @- "$DOKPLOY_URL/api/user.createApiKey" \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("key") or d.get("apiKey") or "")')
    [ -n "$TENANT_KEY" ] || { echo "FAIL: createApiKey returned no key"; exit 1; }
    grep -v '^DOKPLOY_TENANT_API_KEY=' "$SECFILE" > "$SECFILE.tmp" || true
    echo "DOKPLOY_TENANT_API_KEY=$TENANT_KEY" >> "$SECFILE.tmp"
    chmod 600 "$SECFILE.tmp"; mv "$SECFILE.tmp" "$SECFILE"
    echo "CHANGED: API key minted as member -> $SECFILE"
fi

# --- 5. verify the scope from the key's own point of view --------------------------
tenant() { curl -sS -m 20 -K <(printf 'header = "x-api-key: %s"\n' "$TENANT_KEY") "$DOKPLOY_URL/api/$1"; }
seen=$(tenant project.all | python3 -c 'import json,sys; print(",".join(sorted(p["name"] for p in json.load(sys.stdin))))')
[ "$seen" = "$PROJECT" ] || { echo "FAIL: key sees projects [$seen], expected only [$PROJECT]"; exit 1; }
echo "OK: key sees only project '$seen'"
docker_code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' \
    -K <(printf 'header = "x-api-key: %s"\n' "$TENANT_KEY") "$DOKPLOY_URL/api/docker.getContainers")
case "$docker_code" in 401|403) echo "OK: docker surface rejected ($docker_code)";;
    *) echo "FAIL: docker.getContainers returned $docker_code for the scoped key"; exit 1;; esac

# negative scope check (security review 2026-07-14): a scoped member must ideally
# NOT create services - service:create widens to compose.create/application.create
# => arbitrary image/compose (host bind-mount => container escape) on the shared
# box. Non-destructive: read the member's canCreateServices flag back. WARN by
# default (the grant is deliberate today so application.update works); FAIL under
# STRICT_SCOPE=1 once a deploy-without-create path exists.
can_create=$(admin GET user.all | python3 -c '
import json, sys
for m in json.load(sys.stdin):
    if (m.get("user") or {}).get("email") == sys.argv[1]:
        print(m.get("canCreateServices")); break
' "$EMAIL")
if [ "$can_create" = True ]; then
    over="scoped key CAN create services (canCreateServices=True) - a leak deploys an arbitrary image/compose (host bind-mount => escape) on the SHARED box, not just the tenant's own image"
    if [ "${STRICT_SCOPE:-0}" = 1 ]; then echo "FAIL: $over"; exit 1; fi
    echo "WARN: $over [known over-grant; set STRICT_SCOPE=1 once deploy-without-create is resolved]"
else
    echo "OK: scoped key cannot create services (canCreateServices=$can_create)"
fi

# opt-in live proof (the deferred prod probe): actually attempt compose.create
# with the scoped key and clean up. Gated off by default - PROBE_CREATE=1 to run.
if [ "${PROBE_CREATE:-0}" = 1 ]; then
    probe_env=${ENVS%%,*}
    presp=$(curl -sS -m 20 \
        -K <(printf 'header = "x-api-key: %s"\nheader = "Content-Type: application/json"\n' "$TENANT_KEY") \
        -X POST --data-binary "$(printf '{"name":"scope-probe-DELETEME","composeType":"docker-compose","environmentId":"%s"}' "$probe_env")" \
        "$DOKPLOY_URL/api/compose.create")
    pid=$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("composeId") or "")
except Exception: print("")' <<<"$presp")
    if [ -n "$pid" ]; then
        printf '{"composeId":"%s"}' "$pid" | admin POST compose.delete >/dev/null 2>&1 \
            && echo "CONFIRMED VULN: scoped key created compose $pid (auto-deleted) - blast radius exceeds doc" \
            || echo "CONFIRMED VULN: scoped key created compose $pid - AUTO-DELETE FAILED, remove 'scope-probe-DELETEME' in Dokploy NOW"
        [ "${STRICT_SCOPE:-0}" = 1 ] && exit 1
    else
        echo "OK: live probe - scoped key could not create a compose (rejected)"
    fi
fi

first_app=${APPS%%,*}
if [ -n "$first_app" ]; then
    app_code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' \
        -K <(printf 'header = "x-api-key: %s"\n' "$TENANT_KEY") \
        "$DOKPLOY_URL/api/application.one?applicationId=$first_app")
    [ "$app_code" = 200 ] || { echo "FAIL: key cannot read its own app ($app_code)"; exit 1; }
    echo "OK: key reads its own app ($first_app)"
fi
echo "== converged: scoped credential for '$SLUG' verified (file: $SECFILE)"
