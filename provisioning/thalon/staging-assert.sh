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
# 2026-07-29: this used to demand a <sha40>@sha256:<digest> pin, and it had been
# FAILING for days - which is worse than useless, because a permanently-red check
# trains everyone to stop reading the exit code of this script. Thalon argued it
# was asserting the wrong invariant and they are right, structurally:
#   their deploy key deliberately carries NO application.update grant (s37), so
#   the only lever CI has is re-tag :staging + application.deploy. Against a
#   DIGEST-pinned app that call is a silent no-op - it reports success and ships
#   nothing. Pinning would trade a false alarm for a real, silent outage.
# The floating tag IS the design here. What is still worth asserting is the safety
# half of the original intent - never :latest, never some other repo, never a
# widened reference - so pin the REFERENCE exactly instead of the digest.
# (opinion, not invariant: revisit if their key ever gains application.update.)
pin_ok = img == "ghcr.io/steveneam/thalon-web:staging"
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
[ "$pin"   = 1 ]    && ok "image ref is exactly :staging (never latest, never another repo)" \
                    || bad "image ref widened - expected ghcr.io/steveneam/thalon-web:staging"
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

# --- 7. OAuth callback edge exemption (founder-approved 2026-07-28, thalon s84) -----
# Platforms redirect a credential-less browser to /api/integrations/callback/<dest>;
# a 401 challenge there strands the operator mid-consent (same reasoning as /assets/).
# ONE higher-priority router serves that ONE prefix without the basicauth middleware -
# rate-limit and noindex are kept. The route is inert without a single-use tenant-walled
# state row, and the begin door stays gated (pinned below).
# Dokploy regenerates this file on domain/security CRUD, so this CONVERGES like sec. 5.
CB_PREFIX='/api/integrations/callback/'
cfg=$(admin_get "application.readTraefikConfig?applicationId=$APP")
new=$(python3 - "$cfg" "$HOSTNAME_STAGING" "$CB_PREFIX" <<'PY'
import json, sys, yaml
# the raw API returns the YAML as a JSON-encoded string; the MCP wrapper wraps it
# in {"data": ...}. Accept either shape.
raw = json.loads(sys.argv[1])
if isinstance(raw, dict):
    raw = raw.get("data") or ""
doc = yaml.safe_load(raw) or {}
host, prefix = sys.argv[2], sys.argv[3]
routers = doc.setdefault("http", {}).setdefault("routers", {})
marker = "PathPrefix(`%s`)" % prefix
if any(marker in (r.get("rule") or "") for r in routers.values()):
    print("PRESENT"); sys.exit(0)
base = next(((n, r) for n, r in routers.items()
             if "websecure" in (r.get("entryPoints") or [])
             and (r.get("rule") or "").strip() == "Host(`%s`)" % host), None)
if base is None:
    print("NOBASE"); sys.exit(0)
name, r = base
ex = {"rule": "Host(`%s`) && %s" % (host, marker), "priority": 100,
      "service": r.get("service"),
      # drop ONLY the basicauth middleware; keep rate-limit + noindex
      "middlewares": [m for m in (r.get("middlewares") or []) if not m.startswith("auth-")],
      "entryPoints": ["websecure"]}
if r.get("tls"):
    # deep-copy: sharing the dict makes PyYAML emit an &anchor/*alias pair
    ex["tls"] = json.loads(json.dumps(r["tls"]))
routers[name.replace("-router-websecure", "-router") + "-oauth-callback"] = ex
print("REBUILD")
print(yaml.safe_dump(doc, sort_keys=False, default_flow_style=False))
PY
)
case "$new" in
  PRESENT*) ok "oauth-callback edge exemption router present" ;;
  NOBASE*)  bad "no base websecure router to derive the callback exemption from" ;;
  REBUILD*) printf '%s' "${new#REBUILD}" \
                | python3 -c 'import json,sys; print(json.dumps({"applicationId": sys.argv[1], "traefikConfig": sys.stdin.read().lstrip("\n")}))' "$APP" \
                | admin_post application.updateTraefikConfig >/dev/null
            sleep 4
            recheck=$(admin_get "application.readTraefikConfig?applicationId=$APP")
            grep -q "PathPrefix(\`$CB_PREFIX\`)" <<<"$recheck" \
                && ok "CONVERGED: re-added oauth-callback exemption router (Dokploy had regenerated it away)" \
                || bad "callback exemption re-add did not stick" ;;
esac

# the exemption must be effective ANONYMOUSLY - that is its whole purpose
cbc=$(probe "https://$HOSTNAME_STAGING${CB_PREFIX}facebook")
[ "$cbc" != 401 ] \
    && ok "callback prefix reachable anon ($cbc = app's own typed refusal, no state row)" \
    || bad "callback prefix still 401 - exemption not effective, connect will strand"
# ...and no wider than that: every neighbouring door stays challenged
for p in / /app /api/health /api/integrations /api/integrations/facebook/oauth \
         /api/integrations/facebook/connect /api/integrations/callback; do
    c=$(probe "https://$HOSTNAME_STAGING$p")
    [ "$c" = 401 ] && ok "$p still gated (401)" || bad "$p -> $c - exemption leaked wider than the prefix"
done
# APP_ORIGIN must be set, or the app builds absolute redirects from its bind address
# (0.0.0.0:3000) and the operator lands on a dead host mid-consent.
python3 -c '
import json, sys
env = dict(l.rstrip("\r").split("=",1) for l in (json.loads(sys.argv[1]).get("env") or "").splitlines() if "=" in l)
sys.exit(0 if env.get("APP_ORIGIN") == "https://"+sys.argv[2] else 1)' "$app_json" "$HOSTNAME_STAGING" \
    && ok "APP_ORIGIN pinned to https://$HOSTNAME_STAGING" \
    || bad "APP_ORIGIN missing/wrong - callback redirects will point at 0.0.0.0:3000"

# --- 8. credential-vault KEK (minted 2026-07-29 for thalon s85) ---------------------
# THALON_VAULT_MASTER_KEY seals every credential staging stores; the engine wants
# exactly 32 bytes, base64. This is a KEY-encryption key, not a password: once staging
# has sealed a row under it, losing or rotating it makes that row permanently
# undecryptable. So the invariant is not just "set" - it is "set AND still equal to the
# durable off-repo copy", which is what a restore would put back. A silent UI rotation
# or a lost inventory file is exactly the failure this catches. Values never printed.
VAULT_FILE=inventory/secrets/thalon-staging-vault-master.env
if [ ! -s "$VAULT_FILE" ]; then
    bad "$VAULT_FILE missing - the durable copy of staging's KEK is GONE (sealed rows unrecoverable if the app env is also lost)"
else
    python3 -c '
import base64, json, sys
env = dict(l.rstrip("\r").split("=",1) for l in (json.loads(sys.argv[1]).get("env") or "").splitlines() if "=" in l)
live = env.get("THALON_VAULT_MASTER_KEY")
if not live: print("UNSET"); sys.exit(1)
try:
    n = len(base64.b64decode(live, validate=True))
except Exception: print("NOTB64"); sys.exit(1)
if n != 32: print("LEN%d" % n); sys.exit(1)
disk = dict(l.rstrip().split("=",1) for l in open(sys.argv[2]) if "=" in l).get("THALON_VAULT_MASTER_KEY")
print("OK" if live == disk else "DIVERGED"); sys.exit(0 if live == disk else 1)' "$app_json" "$VAULT_FILE" >/tmp/.vaultchk 2>&1
    case "$(cat /tmp/.vaultchk)" in
      OK)       ok "THALON_VAULT_MASTER_KEY set, 32 bytes, matches the durable inventory copy" ;;
      UNSET)    bad "THALON_VAULT_MASTER_KEY unset - every connect 503s at the vault" ;;
      NOTB64)   bad "THALON_VAULT_MASTER_KEY is not valid base64" ;;
      LEN*)     bad "THALON_VAULT_MASTER_KEY decodes to $(sed 's/^LEN/ /' /tmp/.vaultchk) bytes - engine requires exactly 32" ;;
      DIVERGED) bad "THALON_VAULT_MASTER_KEY on the app != $VAULT_FILE - one of them was changed out of band; do NOT overwrite either until you know which sealed the live rows" ;;
      *)        bad "vault KEK check errored: $(cat /tmp/.vaultchk)" ;;
    esac
    rm -f /tmp/.vaultchk
fi

# ------------------------------------------------------------------------------------
if [ "$fails" -eq 0 ]; then echo "== staging posture verified ($HOSTNAME_STAGING)"; else
    echo "== $fails FAILURES"; exit 1; fi
