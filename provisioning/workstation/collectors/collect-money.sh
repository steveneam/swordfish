#!/usr/bin/env bash
set -uo pipefail

# collect-money.sh - recurring spend (plan §5). Two halves, deliberately:
#   - founder-maintained subscriptions.yml (SaaS the box can't see):
#     inventory/secrets/subscriptions.yml (gitignored). Schema per entry:
#       name, amount, currency, cycle (monthly|yearly), next_charge
#       (YYYY-MM-DD), card (optional note)
#   - API-backed invoices (BinaryLane/Vultr/B2/Porkbun): NOT BUILT YET -
#     polling those is an OPEN FOUNDER DECISION (NEEDS-STEVEN.md 2026-07-13).
#     Same gate covers pre-filling subscriptions.yml. Until the call is made
#     this collector reports the gate honestly instead of guessing numbers.
# Anything due inside 7 days (or overdue) is flagged for the Needs-Steven
# queue by the renderer. Amounts stay in the untracked JSON/HTML only.

. "$(dirname "$0")/lib.sh"

SUBS="$SEC_DIR/subscriptions.yml"

main() {
  if [ ! -f "$SUBS" ]; then
    jq -n --argjson t "$(date +%s)" \
      '{generated_at: $t, gated: true,
        note: "awaiting founder decision: billing-API polling + subscriptions.yml pre-fill (see NEEDS STEVEN)"}' \
      | emit money
    return
  fi

  python3 - "$SUBS" <<'PY' | emit money
import sys, json, time, datetime, yaml

subs = (yaml.safe_load(open(sys.argv[1])) or {}).get("subscriptions", [])
today = datetime.date.today()
out, monthly = [], 0.0
for s in subs:
    try:
        amt = float(s.get("amount", 0))
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
    "generated_at": int(time.time()),
    "gated": False,
    "subscriptions": sorted(out, key=lambda x: x.get("days_until") if x.get("days_until") is not None else 9999),
    "monthly_run_rate": round(monthly, 2),
    "api_note": "infra invoice APIs (BinaryLane/Vultr/B2/Porkbun) still gated on the founder decision",
}))
PY
}

main || fail money "money collector crashed"
