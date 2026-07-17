#!/usr/bin/env bash
set -uo pipefail

# collect-money.sh - recurring spend (plan §5). Two halves, deliberately:
#   - API-backed, read-only (founder go-ahead 2026-07-13): BinaryLane balance
#     + per-server ongoing charges, Vultr credit/pending, Porkbun domain
#     renewals. Tokens come from the gitignored repo .env via lib.sh envval();
#     they never reach the emitted JSON. Backblaze B2 has NO billing API -
#     that line stays honest instead of guessed.
#   - founder-maintained subscriptions.yml (SaaS the box can't see):
#     inventory/secrets/subscriptions.yml (gitignored). Schema per entry:
#       name, amount, currency, cycle (monthly|yearly), next_charge
#       (YYYY-MM-DD), card (free-text note)
# Anything due inside 7 days (or overdue) is promoted into Needs Steven by
# the renderer. Amounts + domain names stay in the untracked JSON/HTML only
# (the Porkbun list includes guarded-name domains - untracked BY DESIGN).

. "$(dirname "$0")/lib.sh"

SUBS="$SEC_DIR/subscriptions.yml"

binarylane_json() {
  local tok out
  tok=$(envval BINARYLANE_API_TOKEN)
  [ -n "$tok" ] || { jq -n '{error: "no token in .env"}'; return; }
  out=$(curl -s -m 15 -H @<(printf 'Authorization: Bearer %s\n' "$tok") \
        https://api.binarylane.com.au/v2/customers/my/balance 2>/dev/null)
  jq '{currency: "AUD", unbilled_total: .balance.unbilled_total,
       servers: [.balance.charges[]? | {name: (.description | split(" ")[0]),
                                        total, ongoing}]}
      // {error: "unexpected response"}' <<<"$out" 2>/dev/null \
    || jq -n '{error: "binarylane unreachable"}'
}

# B2 has no BILLING API, but STORAGE is queryable - and storage is the whole
# bill on the free tier. Sums live bytes per bucket via the native API.
# WHY (2026-07-17 incident): the 10 GB free cap filled silently until
# Backblaze's own 100% email beat the fleet to the news; at cap, B2 rejects
# b2_get_upload_url, every nightly backup fails, and an over-cap restic repo
# cannot even prune itself (its LOCK is an upload) - so the first alert being
# an external email is exactly one alert too late. The renderer promotes
# >85% into Needs Steven. API budget: ~7 class-C calls per run x 96 runs/day
# ~= 700/day against B2's 2,500/day free class-C allowance.
B2_FREE_CAP=10000000000  # 10 GB decimal - matches B2's own % math (10.32 GB read as 103%)
b2_json() {
  local kid key
  kid=$(envval B2_APPLICATION_KEY_ID); key=$(envval B2_APPLICATION_KEY)
  { [ -n "$kid" ] && [ -n "$key" ]; } || { jq -n '{error: "no B2 key in .env"}'; return; }
  B2_KID="$kid" B2_KEY="$key" B2_FREE_CAP="$B2_FREE_CAP" python3 - <<'PYB2' 2>/dev/null || jq -n '{error: "b2 unreachable"}'
import base64, json, os, urllib.request
kid, key = os.environ['B2_KID'], os.environ['B2_KEY']
auth = base64.b64encode(f'{kid}:{key}'.encode()).decode()
req = urllib.request.Request('https://api.backblazeb2.com/b2api/v3/b2_authorize_account',
                             headers={'Authorization': f'Basic {auth}'})
acct = json.load(urllib.request.urlopen(req, timeout=15))
api = acct['apiInfo']['storageApi']

def call(fn, payload):
    r = urllib.request.Request(f"{api['apiUrl']}/b2api/v3/{fn}", data=json.dumps(payload).encode(),
        headers={'Authorization': acct['authorizationToken'], 'Content-Type': 'application/json'})
    return json.load(urllib.request.urlopen(r, timeout=25))

out, total = [], 0
for b in call('b2_list_buckets', {'accountId': acct['accountId']})['buckets']:
    size, start = 0, None
    while True:
        p = {'bucketId': b['bucketId'], 'maxFileCount': 10000}
        if start: p['startFileName'] = start
        resp = call('b2_list_file_names', p)
        size += sum(f.get('contentLength', 0) for f in resp['files'])
        start = resp.get('nextFileName')
        if not start: break
    total += size
    out.append({'bucket': b['bucketName'], 'bytes': size})
cap = int(os.environ.get('B2_FREE_CAP', 10_000_000_000))
print(json.dumps({'total_bytes': total, 'cap_bytes': cap,
                  'pct_of_cap': round(total / cap * 100, 1), 'buckets': out}))
PYB2
}

vultr_json() {
  local tok out
  tok=$(envval VULTR_API_KEY)
  [ -n "$tok" ] || { jq -n '{error: "no token in .env"}'; return; }
  out=$(curl -s -m 15 -H @<(printf 'Authorization: Bearer %s\n' "$tok") \
        https://api.vultr.com/v2/account 2>/dev/null)
  jq '{currency: "USD", balance: .account.balance,
       pending_charges: .account.pending_charges}
      // {error: "unexpected response"}' <<<"$out" 2>/dev/null \
    || jq -n '{error: "vultr unreachable"}'
}

porkbun_json() {
  local pk sk out now
  pk=$(envval PORKBUN_API_KEY); sk=$(envval PORKBUN_SECRET_API_KEY)
  { [ -n "$pk" ] && [ -n "$sk" ]; } || { jq -n '{error: "no keys in .env"}'; return; }
  out=$(printf '{"apikey":"%s","secretapikey":"%s"}' "$pk" "$sk" \
        | curl -s -m 15 -H 'Content-Type: application/json' -d @- \
          https://api.porkbun.com/api/json/v3/domain/listAll 2>/dev/null)
  now=$(date +%s)
  jq --argjson now "$now" '
    if .status == "SUCCESS" then
      {domains: [.domains[] | {domain,
        expires: .expireDate,
        days_left: (((.expireDate | sub(" .*$"; "") | strptime("%Y-%m-%d") | mktime) - $now) / 86400 | floor),
        auto_renew: (.autoRenew == "1")}] | sort_by(.days_left)}
    else {error: (.message // "porkbun error")} end' <<<"$out" 2>/dev/null \
    || jq -n '{error: "porkbun unreachable"}'
}

subs_json() {
  if [ ! -f "$SUBS" ]; then
    jq -n '{missing: true}'
    return
  fi
  python3 - "$SUBS" <<'PY'
import sys, json, datetime, yaml

subs = (yaml.safe_load(open(sys.argv[1])) or {}).get("subscriptions", [])
today = datetime.date.today()
out, monthly = [], 0.0
for s in subs:
    try:
        amt = float(s.get("amount") or 0)
        cycle = s.get("cycle", "monthly")
        monthly += amt / 12 if cycle == "yearly" else amt
        nxt = s.get("next_charge")
        days = (datetime.date.fromisoformat(str(nxt)) - today).days if nxt else None
        out.append({"name": s.get("name", "?"), "amount": amt,
                    "currency": s.get("currency", "AUD"), "cycle": cycle,
                    "next_charge": str(nxt) if nxt else None,
                    "days_until": days, "card": s.get("card")})
    except Exception as e:
        out.append({"name": s.get("name", "?"), "error": str(e)})

print(json.dumps({
    "list": sorted(out, key=lambda x: x.get("days_until") if x.get("days_until") is not None else 9999),
    "monthly_run_rate": round(monthly, 2)}))
PY
}

main() {
  local bl vu pb subs b2
  bl=$(binarylane_json)
  vu=$(vultr_json)
  pb=$(porkbun_json)
  subs=$(subs_json)
  b2=$(b2_json)
  jq -n --argjson t "$(date +%s)" --argjson bl "$bl" --argjson vu "$vu" \
        --argjson pb "$pb" --argjson subs "$subs" --argjson b2 "$b2" \
    '{generated_at: $t,
      api: {binarylane: $bl, vultr: $vu, porkbun: $pb, b2: $b2},
      subscriptions: ($subs.list // null),
      subscriptions_missing: ($subs.missing // false),
      monthly_run_rate: ($subs.monthly_run_rate // null)}' \
    | emit money
}

main || fail money "money collector crashed"
