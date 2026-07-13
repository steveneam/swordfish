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
  local bl vu pb subs
  bl=$(binarylane_json)
  vu=$(vultr_json)
  pb=$(porkbun_json)
  subs=$(subs_json)
  jq -n --argjson t "$(date +%s)" --argjson bl "$bl" --argjson vu "$vu" \
        --argjson pb "$pb" --argjson subs "$subs" \
    '{generated_at: $t,
      api: {binarylane: $bl, vultr: $vu, porkbun: $pb,
            b2: {note: "no billing API - B2 spend shows on the card statement; caps live in the B2 UI"}},
      subscriptions: ($subs.list // null),
      subscriptions_missing: ($subs.missing // false),
      monthly_run_rate: ($subs.monthly_run_rate // null)}' \
    | emit money
}

main || fail money "money collector crashed"
