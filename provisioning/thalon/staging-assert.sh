#!/usr/bin/env bash
# staging-assert.sh - executable truth for the thalon staging pack on syd2
# (built 2026-07-13 over the Dokploy REST API; this script is the rot guard
# rule 9 wants - the one-time creation calls live in the 0210101 + this
# session's commit messages, the RUNNING invariants live here, re-checkable
# any session and on the monthly pass).
#
# Asserts (read-only) every staging invariant, and CONVERGES exactly one
# thing: the basicauth middleware's removeHeader flag. Dokploy regenerates
# that middleware with removeHeader:true whenever the app's security entries
# change; staging needs FALSE - the edge must forward the Authorization
# header so the ONE preview pair satisfies both the edge gate and the app's
# own workspace gate in sequence (double-Basic deadlock, staging-verify
# finding 2, resolved option 1). Verified live: the flag survives
# application.deploy/redeploy; only security CRUD rewrites it.
#
#   usage: staging-assert.sh          env: DOKPLOY_URL (default deploy; cutover 2026-07-13)
#
# At launch this whole posture changes (thalon.org domains, edge auth drops,
# monitor swaps) - retire or rewrite this script at the launch call.

set -euo pipefail
cd "$(dirname "$0")/../.."

DOKPLOY_URL=${DOKPLOY_URL:-https://deploy.swordfish.cfd}
APP=jh_UI2lErDwykJG6FcFBD
HOSTNAME_STAGING=preview.swordfish.cfd

envval() { grep "^$1=" .env | cut -d= -f2- | tr -d '\r' | sed 's/^ *//'; }
KEY=$(envval DOKPLOY_SYD2_API_KEY)
[ -n "$KEY" ] || { echo "FAIL: DOKPLOY_SYD2_API_KEY not in .env"; exit 1; }
admin_get()  { curl -sS -m 30 -K <(printf 'header = "x-api-key: %s"\n' "$KEY") "$DOKPLOY_URL/api/$1"; }
admin_post() { curl -sS -m 30 -K <(printf 'header = "x-api-key: %s"\nheader = "Content-Type: application/json"\n' "$KEY") -X POST --data-binary @- "$DOKPLOY_URL/api/$1"; }

fails=0
ok()   { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fails=$((fails+1)); }

app_json=$(admin_get "application.one?applicationId=$APP")

# --- 1-4. app shape ---------------------------------------------------------------
read -r pin status pair envkeys mount < <(python3 -c '
import json, sys, re
a = json.loads(sys.argv[1])
img = a.get("dockerImage") or ""
pin_ok = bool(re.fullmatch(r"ghcr\.io/steveneam/thalon-web:[0-9a-f]{40}@sha256:[0-9a-f]{64}", img))
sec = a.get("security") or []
pair = (sec[0]["username"] + ":" + sec[0]["password"]) if sec else "-"
env = dict(l.split("=",1) for l in (a.get("env") or "").splitlines() if "=" in l)
keys = ",".join(sorted(env))
ws_is_pair = env.get("WORKSPACE_BASIC_AUTH") == pair
mounts = [(m.get("volumeName"), m.get("mountPath")) for m in a.get("mounts") or []]
mount_ok = ("thalon-data","/data") in mounts
doms = [(d.get("host"), d.get("port"), d.get("https")) for d in a.get("domains") or []]
dom_ok = (sys.argv[2], 3000, True) in doms
print(int(pin_ok), a.get("applicationStatus"), int(bool(sec)), int(ws_is_pair and "DB_DUMP_TOKEN" in env), int(mount_ok and dom_ok))
' "$app_json" "$HOSTNAME_STAGING")
[ "$pin"   = 1 ]    && ok "image pinned sha-tag@digest (never latest)" || bad "image pin drifted"
[ "$status" = done ] && ok "applicationStatus done"                    || bad "applicationStatus=$status"
[ "$pair"  = 1 ]    && ok "edge BasicAuth entry armed"                 || bad "no security entry - staging is OPEN"
[ "$envkeys" = 1 ]  && ok "env: WORKSPACE_BASIC_AUTH == edge pair, DB_DUMP_TOKEN present" || bad "env drifted from unified-pair posture"
[ "$mount" = 1 ]    && ok "thalon-data at /data + domain $HOSTNAME_STAGING:3000 https"    || bad "mount/domain drifted"

# probes authenticate with the pair Dokploy itself holds - self-referential,
# no second copy of the secret to drift
EDGE_PAIR=$(python3 -c 'import json,sys; s=(json.loads(sys.argv[1]).get("security") or [{}])[0]; print(s.get("username","")+":"+s.get("password",""))' "$app_json")

# --- 5. middleware removeHeader (the one converged piece) --------------------------
mw=$(admin_get settings.readMiddlewareTraefikConfig)
if grep -q 'removeHeader: false' <<<"$mw"; then
    ok "basicauth middleware forwards Authorization (removeHeader: false)"
elif grep -q 'removeHeader: true' <<<"$mw"; then
    python3 -c 'import json,sys; print(json.dumps({"traefikConfig": json.loads(sys.argv[1]).replace("removeHeader: true","removeHeader: false")}))' "$mw" \
        | admin_post settings.updateMiddlewareTraefikConfig >/dev/null
    sleep 3
    grep -q 'removeHeader: false' <<<"$(admin_get settings.readMiddlewareTraefikConfig)" \
        && ok "CONVERGED: removeHeader true->false (Dokploy regenerated it - expected after security CRUD)" \
        || bad "removeHeader flip did not stick"
else
    bad "no basicauth middleware found at all"
fi

# --- 6. live surface through the edge ----------------------------------------------
probe() { curl -s -o /dev/null -w '%{http_code}' -m 20 "$@"; }
[ "$(probe "https://$HOSTNAME_STAGING/")" = 401 ] \
    && ok "anon -> 401 (stealth holds)" || bad "anon request not challenged"
for p in /api/health /blog /blog/rss.xml /sitemap.xml /llms.txt; do
    c=$(probe -u "$EDGE_PAIR" "https://$HOSTNAME_STAGING$p")
    [ "$c" = 200 ] && ok "$p -> 200 through edge" || bad "$p -> $c"
done
c=$(probe -u "$EDGE_PAIR" -L "https://$HOSTNAME_STAGING/app")
[ "$c" = 200 ] && ok "/app -> 200 with the ONE pair (header pass-through intact)" \
             || bad "/app -> $c - double-Basic deadlock is back (removeHeader regenerated?)"
curl -s -o /dev/null -D - -m 15 -u "$EDGE_PAIR" "https://$HOSTNAME_STAGING/" | grep -qi 'x-robots-tag: noindex' \
    && ok "X-Robots-Tag noindex on responses" || bad "noindex header missing"

# ------------------------------------------------------------------------------------
if [ "$fails" -eq 0 ]; then echo "== staging posture verified ($HOSTNAME_STAGING)"; else
    echo "== $fails FAILURES"; exit 1; fi
