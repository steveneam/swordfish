#!/usr/bin/env bash
# templates-preview-provision.sh - converge thalon's template-portfolio preview
# gallery on syd2 (founder-routed ask 2026-07-29, thalon channel (8): the ask
# sat 11 days on his console list and was always console work, i.e. ours).
#
#   usage: templates-preview-provision.sh   (no args; idempotent - re-run prints state)
#     env: DOKPLOY_URL      (default https://deploy.swordfish.cfd)
#          DOKPLOY_KEY_NAME (.env var holding the ADMIN key; default DOKPLOY_SYD2_API_KEY)
#
# What it converges (Dokploy project thalon-previews -> application previews):
#   1. project `thalon-previews` (own project ON PURPOSE: tenant-credential.sh
#      scopes a member to a whole project, so previews in the `thalon` project
#      would hand the templates CI key deploy power over STAGING too)
#   2. application `previews`: docker provider ghcr.io/steveneam/thalon-previews:latest
#      + GHCR pull credential. `:latest` IS the design here (cf. the :staging
#      lesson in staging-assert.sh): their deploy-only key cannot
#      application.update, so the app must sit on the floating tag their CI
#      pushes every build; the safety half that matters is never-another-repo.
#   3. edge basicauth = THE SAME preview pair as staging
#      (inventory/secrets/thalon-preview.basicauth) - one operator credential,
#      and stealth holds: anon sees only a 401 challenge on a neutral host.
#   4. DNS A previews.swordfish.cfd -> syd2 (porkbun upsert, idempotent).
#      NEUTRAL NAME, invariant: public names derive from what a thing does,
#      never who it serves (CI-GUARD.md) - nothing says thalon, no thalon.org.
#   5. domain previews.swordfish.cfd -> :80 https letsencrypt (the image serves
#      nginx on 80 - see their smoke gate: `docker run -p 8080:80`)
#   6. deploy + poll applicationStatus=done
#   7. router middlewares swordfish-ratelimit + thalon-noindex (same posture as
#      staging; Dokploy regenerates this file on domain/security CRUD, so this
#      CONVERGES like staging-assert.sh section 7 - re-run after any such CRUD)
#   8. outside-in verification: anon / -> 401; with the pair /healthz + / -> 200
#      + X-Robots-Tag noindex present
#
# NOT here, deliberately: the scoped CI credential (tenant-credential.sh
# thalon-previews thalon-previews - separate mint, founder-gated hand-off);
# TEMPLATES_PREVIEW_ARMED (a GitHub repo VARIABLE thalon owns, not app env);
# SITES_BASE_URL on their web app (env => a redeploy of THEIR app; fold into
# their next roll). Their workflow's dormant application.update step is stale
# legacy shape and must become deploy-only on their side - told in channel.
# Secrets ride env vars, files, and stdin - never argv (house rule).

set -euo pipefail
cd "$(dirname "$0")/../.."

PROJECT=thalon-previews
APPNAME=previews
HOST_PUB=previews.swordfish.cfd
IMAGE=ghcr.io/steveneam/thalon-previews:latest
APP_PORT=80
PAIR_FILE=inventory/secrets/thalon-preview.basicauth
DOKPLOY_URL=${DOKPLOY_URL:-https://deploy.swordfish.cfd}
DOKPLOY_KEY_NAME=${DOKPLOY_KEY_NAME:-DOKPLOY_SYD2_API_KEY}

[ -s "$PAIR_FILE" ] || { echo "FAIL: $PAIR_FILE missing - the edge pair is the stealth gate"; exit 1; }

envval() { grep "^$1=" .env | cut -d= -f2- | tr -d '\r' | sed 's/^ *//'; }
ADMIN_KEY=$(envval "$DOKPLOY_KEY_NAME")
[ -n "$ADMIN_KEY" ] || { echo "FAIL: $DOKPLOY_KEY_NAME not in .env"; exit 1; }
GHCR_TOKEN=$(envval GHCR_PULL_TOKEN)
[ -n "$GHCR_TOKEN" ] || { echo "FAIL: GHCR_PULL_TOKEN not in .env"; exit 1; }

admin_get() { curl -sS -m 30 -K <(printf 'header = "x-api-key: %s"\n' "$ADMIN_KEY") "$DOKPLOY_URL/api/$1"; }
admin_post() { # path; json on stdin. -w + non-2xx check (protocol note 2026-07-29:
    # curl exits 0 on an HTTP 400 - the status line is the only real verdict)
    local out code
    out=$(curl -sS -m 30 -K <(printf 'header = "x-api-key: %s"\nheader = "Content-Type: application/json"\n' "$ADMIN_KEY") \
        -X POST --data-binary @- -w '\nHTTP_STATUS=%{http_code}' "$DOKPLOY_URL/api/$1")
    code=${out##*HTTP_STATUS=}
    case "$code" in 2*) printf '%s' "${out%$'\n'HTTP_STATUS=*}";;
        *) echo "FAIL: $1 returned HTTP $code" >&2; return 1;; esac
}

# --- 1. project (find-or-create) ---------------------------------------------------
resolve() { # prints "envId\nappIds-csv" or "ABSENT"
    admin_get project.all | python3 -c '
import json, sys
hits = [p for p in json.load(sys.stdin) if p.get("name") == sys.argv[1]]
if not hits: print("ABSENT"); sys.exit()
if len(hits) != 1: sys.exit(f"FAIL: {len(hits)} projects named {sys.argv[1]!r}")
envs = hits[0].get("environments", [])
if len(envs) != 1: sys.exit(f"FAIL: expected exactly 1 environment, found {len(envs)}")
print(envs[0]["environmentId"])
print(",".join(a["applicationId"] for a in envs[0].get("applications", [])))
' "$PROJECT"
}
state=$(resolve)
if [ "$state" = ABSENT ]; then
    printf '{"name":"%s","description":"Thalon template-portfolio preview gallery (own project so the scoped CI credential cannot reach staging). Public at %s behind edge basicauth - neutral name, stealth holds. Provisioned 2026-07-29, founder-routed."}' \
            "$PROJECT" "$HOST_PUB" | admin_post project.create >/dev/null
    echo "CHANGED: project $PROJECT created"
    state=$(resolve)
    [ "$state" != ABSENT ] || { echo "FAIL: project.create did not land"; exit 1; }
fi
ENV_ID=$(sed -n 1p <<<"$state"); CANDIDATES=$(sed -n 2p <<<"$state")
echo "OK: project $PROJECT environment $ENV_ID"

# --- 2. application (find-or-create by name) ---------------------------------------
APP_ID=""
for id in ${CANDIDATES//,/ }; do
    name=$(admin_get "application.one?applicationId=$id" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name",""))')
    if [ "$name" = "$APPNAME" ]; then APP_ID=$id; break; fi
done
if [ -n "$APP_ID" ]; then
    echo "OK: application $APPNAME exists ($APP_ID)"
else
    APP_ID=$(printf '{"name":"%s","environmentId":"%s","description":"Preview gallery image from GHCR; CI redeploys via a deploy-only scoped key (no application.update)."}' \
            "$APPNAME" "$ENV_ID" | admin_post application.create \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("applicationId") or "")')
    [ -n "$APP_ID" ] || { echo "FAIL: application.create returned no applicationId"; exit 1; }
    echo "CHANGED: application created ($APP_ID)"
fi

# --- 3. docker provider + GHCR pull credential -------------------------------------
app_json=$(admin_get "application.one?applicationId=$APP_ID")
read -r img_ok < <(python3 -c '
import json, sys
a = json.loads(sys.argv[1])
ok = (a.get("sourceType") == "docker" and a.get("dockerImage") == sys.argv[2]
      and a.get("username") == "steveneam" and (a.get("registryUrl") or "ghcr.io") == "ghcr.io")
print(int(ok))' "$app_json" "$IMAGE")
if [ "$img_ok" = 1 ]; then
    echo "OK: docker provider pinned to $IMAGE (pull as steveneam)"
else
    GHCR_TOKEN="$GHCR_TOKEN" python3 -c 'import json,sys,os; print(json.dumps({
        "applicationId": sys.argv[1], "dockerImage": sys.argv[2],
        "username": "steveneam", "password": os.environ["GHCR_TOKEN"],
        "registryUrl": "ghcr.io"}))' "$APP_ID" "$IMAGE" \
        | admin_post application.saveDockerProvider >/dev/null
    # re-read: the write is only real if it reads back (protocol note)
    recheck=$(admin_get "application.one?applicationId=$APP_ID" \
        | python3 -c 'import json,sys; a=json.load(sys.stdin); print(a.get("dockerImage"))')
    [ "$recheck" = "$IMAGE" ] || { echo "FAIL: saveDockerProvider did not stick (reads back: $recheck)"; exit 1; }
    echo "CHANGED: docker provider -> $IMAGE"
fi

# --- 4. edge basicauth entry (same pair as staging; value never printed) -----------
PAIR_USER=$(cut -d: -f1 "$PAIR_FILE" | head -1)
have_sec=$(python3 -c '
import json, sys
a = json.loads(sys.argv[1])
print(int(any(s.get("username") == sys.argv[2] for s in a.get("security") or [])))' \
    "$app_json" "$PAIR_USER")
if [ "$have_sec" = 1 ]; then
    echo "OK: edge basicauth entry armed (user $PAIR_USER)"
else
    python3 -c '
import json, sys
u, p = open(sys.argv[2]).readline().rstrip("\n").split(":", 1)
print(json.dumps({"applicationId": sys.argv[1], "username": u, "password": p}))' \
        "$APP_ID" "$PAIR_FILE" | admin_post security.create >/dev/null
    echo "CHANGED: edge basicauth entry created (user $PAIR_USER)"
fi

# --- 5. DNS A record (idempotent porkbun upsert; syd2 ip derived, never memory) ----
SYD2_IP=$(dig +short syd2.swordfish.cfd @1.1.1.1 | tail -1)
[[ "$SYD2_IP" =~ ^[0-9.]+$ ]] || { echo "FAIL: cannot resolve syd2.swordfish.cfd"; exit 1; }
cur=$(dig +short "$HOST_PUB" @1.1.1.1 | tail -1)
if [ "$cur" = "$SYD2_IP" ]; then
    echo "OK: DNS $HOST_PUB -> $SYD2_IP"
else
    pwsh -File provisioning/porkbun/set-a-record.ps1 -Ip "$SYD2_IP" -Subdomain "${HOST_PUB%%.swordfish.cfd}" \
        || { echo "FAIL: porkbun upsert failed"; exit 1; }
    echo "CHANGED: DNS $HOST_PUB -> $SYD2_IP (was: ${cur:-unset}; propagation may lag)"
fi

# --- 6. domain (exactly ours, then deploy) -----------------------------------------
dom_state=$(admin_get "application.one?applicationId=$APP_ID" | python3 -c '
import json, sys
doms = json.load(sys.stdin).get("domains") or []
ours = [d for d in doms if d.get("host") == sys.argv[1]]
others = [d.get("host") for d in doms if d.get("host") != sys.argv[1]]
if others: sys.exit(f"FAIL: unexpected extra domains: {others}")
print("PRESENT" if ours else "ABSENT")' "$HOST_PUB")
if [ "$dom_state" = ABSENT ]; then
    printf '{"host":"%s","https":true,"port":%d,"path":"/","certificateType":"letsencrypt","domainType":"application","applicationId":"%s"}' \
            "$HOST_PUB" "$APP_PORT" "$APP_ID" | admin_post domain.create >/dev/null
    echo "CHANGED: domain $HOST_PUB attached (:$APP_PORT, LE)"
    DEPLOY_NEEDED=1
else
    echo "OK: domain $HOST_PUB attached"
fi

status=$(admin_get "application.one?applicationId=$APP_ID" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("applicationStatus",""))')
if [ "${DEPLOY_NEEDED:-0}" = 1 ] || [ "$status" != done ]; then
    printf '{"applicationId":"%s","title":"provision converge"}' "$APP_ID" | admin_post application.deploy >/dev/null
    echo "OK: deploy dispatched"
    for _ in $(seq 1 36); do
        status=$(admin_get "application.one?applicationId=$APP_ID" \
            | python3 -c 'import json,sys; print(json.load(sys.stdin).get("applicationStatus",""))')
        case "$status" in
            done) break ;;
            error) echo "FAIL: applicationStatus=error - read the Dokploy deploy log"; exit 1 ;;
        esac
        sleep 5
    done
    [ "$status" = done ] || { echo "FAIL: app never reached done (last: $status)"; exit 1; }
fi
echo "OK: applicationStatus=done"

# --- 7. router middlewares (ratelimit + noindex, same as staging) ------------------
cfg=$(admin_get "application.readTraefikConfig?applicationId=$APP_ID")
new=$(python3 - "$cfg" "$HOST_PUB" <<'PY'
import json, sys, yaml
raw = json.loads(sys.argv[1])
if isinstance(raw, dict): raw = raw.get("data") or ""
doc = yaml.safe_load(raw) or {}
host = sys.argv[2]
changed = False
for r in (doc.get("http", {}).get("routers") or {}).values():
    if host not in (r.get("rule") or ""): continue
    mws = r.get("middlewares") or []
    for want in ("swordfish-ratelimit", "thalon-noindex"):
        if want not in mws:
            # before the auth- entry, matching staging order (ratelimit fires
            # ahead of the auth challenge)
            idx = next((i for i, m in enumerate(mws) if m.startswith("auth-")), len(mws))
            mws.insert(idx, want); changed = True
    r["middlewares"] = mws
if not changed:
    print("PRESENT")
else:
    print("REBUILD")
    print(yaml.safe_dump(doc, sort_keys=False, default_flow_style=False))
PY
)
case "$new" in
  PRESENT*) ok_mw=1; echo "OK: ratelimit + noindex middlewares on the routers" ;;
  REBUILD*) printf '%s' "${new#REBUILD}" \
                | python3 -c 'import json,sys; print(json.dumps({"applicationId": sys.argv[1], "traefikConfig": sys.stdin.read().lstrip("\n")}))' "$APP_ID" \
                | admin_post application.updateTraefikConfig >/dev/null
            sleep 4
            grep -q 'swordfish-ratelimit' <<<"$(admin_get "application.readTraefikConfig?applicationId=$APP_ID")" \
                && echo "CHANGED: ratelimit + noindex middlewares attached" \
                || { echo "FAIL: middleware attach did not stick"; exit 1; } ;;
esac

# --- 8. outside-in verification (capture-then-compare, never verdict pipes) --------
PAIR=$(head -1 "$PAIR_FILE")
# || true: under set -e a TLS-not-ready curl (exit 35) must read as 000-retry,
# not kill the script mid-verification
probe() { curl -s -o /dev/null -w '%{http_code}' -m 20 "$@" || true; }
# first issuance: LE cert + DNS propagation can lag ~a minute; 000 = not-yet,
# anything else is a real answer
anon=000
for _ in $(seq 1 12); do
    anon=$(probe "https://$HOST_PUB/")
    [ "$anon" != 000 ] && break
    sleep 10
done
[ "$anon" = 401 ] || { echo "FAIL: anon / returned $anon (want 401 - stealth gate)"; exit 1; }
echo "OK: anon -> 401 (stealth holds on a neutral host)"
hz=$(probe -u "$PAIR" "https://$HOST_PUB/healthz")
[ "$hz" = 200 ] || { echo "FAIL: /healthz returned $hz (want 200)"; exit 1; }
root=$(probe -u "$PAIR" "https://$HOST_PUB/")
[ "$root" = 200 ] || { echo "FAIL: authed / returned $root (want 200 - blank stealth index)"; exit 1; }
echo "OK: /healthz + / -> 200 with the pair"
curl -s -o /dev/null -D - -m 15 -u "$PAIR" "https://$HOST_PUB/" | grep -qi 'x-robots-tag: noindex' \
    && echo "OK: X-Robots-Tag noindex on responses" \
    || { echo "FAIL: noindex header missing"; exit 1; }
echo "== converged: $PROJECT/$APPNAME on syd2 (app $APP_ID) at https://$HOST_PUB"
echo "   next (separate, gated): tenant-credential.sh thalon-previews $PROJECT"
