#!/usr/bin/env bash
set -uo pipefail

# collect-security.sh - fleet security signal (plan §4).
#   - ssh login alerts (journald tag swordfish-alerts): syd4 local + syd3 ssh.
#     syd1/syd2 have the same pam hook but no cockpit-readable journal - their
#     login alerts reach the founder's Telegram directly; the card says so.
#   - failed-auth + fail2ban ban counts, 24 h (same greps as the daily digest;
#     ban counting needs the journald logtarget fix of 2026-07-13)
#   - posture: ufw active + sshd key-only, per reachable box
#   - TLS cert days-remaining per public host (openssl, no auth needed)
#   - domain expiry via public RDAP (rdap.org) - tokenless, so no founder gate

. "$(dirname "$0")/lib.sh"

TLS_HOSTS=("${SYD1_HOSTS[@]}" "${SYD2_HOSTS[@]}")  # one home: lib.sh
DOMAINS=(swordfish.cfd thalon.org)

lines_to_logins() { # stdin = alert lines -> JSON array with a suspicious flag
  jq -R -s '[split("\n")[] | select(length > 0) |
    {line: ., suspicious: (test("UNRECOGNIZED-KEY|no-key-info|method:"))}]'
}

local_auth() { # syd4 counts + posture
  local fails bans ufw pass
  fails=$(sudo -n journalctl -u ssh --since "24 hours ago" --no-pager 2>/dev/null \
          | grep -cE 'Invalid user|Failed (publickey|password)|banner exchange.*invalid' || true)
  bans=$(sudo -n journalctl -u fail2ban --since "24 hours ago" --no-pager 2>/dev/null \
         | grep -c ' Ban ' || true)
  ufw=$(sudo -n ufw status 2>/dev/null | head -1 | awk '{print $2}')
  pass=$(sudo -n sshd -T 2>/dev/null | awk '/^passwordauthentication/{print $2}')
  jq -n --argjson f "${fails:-0}" --argjson b "${bans:-0}" \
        --arg ufw "${ufw:-unknown}" --arg pw "${pass:-unknown}" \
    '{box: "syd4", fails_24h: $f, bans_24h: $b, ufw: $ufw, sshd_password_auth: $pw}'
}

syd3_auth() {
  # NB --since=-24h, deliberately space-free: the earlier `--since \"24 hours
  # ago\"` variant reached the remote $() as three args, journalctl errored
  # silently and every count rendered a CONFIDENT 0 (code review 2026-07-13
  # caught it - the exact confident-wrong-briefing failure mode again)
  local out
  out=$(ssh_syd3 '
    echo "fails=$(sudo -n journalctl -u ssh --since=-24h --no-pager 2>/dev/null | grep -cE "Invalid user|Failed (publickey|password)|banner exchange.*invalid")"
    echo "bans=$(sudo -n journalctl -u fail2ban --since=-24h --no-pager 2>/dev/null | grep -c " Ban ")"
    echo "ufw=$(sudo -n ufw status 2>/dev/null | head -1 | awk "{print \$2}")"
    echo "pass=$(sudo -n sshd -T 2>/dev/null | awk "/^passwordauthentication/{print \$2}")"' 2>/dev/null) \
    || { jq -n '{box: "syd3", unreachable: true}'; return; }
  jq -n --argjson f "$(grep '^fails=' <<<"$out" | cut -d= -f2 | grep -E '^[0-9]+$' || echo 0)" \
        --argjson b "$(grep '^bans=' <<<"$out" | cut -d= -f2 | grep -E '^[0-9]+$' || echo 0)" \
        --arg ufw "$(grep '^ufw=' <<<"$out" | cut -d= -f2)" \
        --arg pw "$(grep '^pass=' <<<"$out" | cut -d= -f2)" \
    '{box: "syd3", fails_24h: $f, bans_24h: $b,
      ufw: (if $ufw == "" then "unknown" else $ufw end),
      sshd_password_auth: (if $pw == "" then "unknown" else $pw end)}'
}

tls_json() { # cert days-remaining per public host
  local out='[]' h end days now; now=$(date +%s)
  for h in "${TLS_HOSTS[@]}"; do
    end=$(echo | timeout 12 openssl s_client -servername "$h" -connect "$h:443" 2>/dev/null \
          | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -n "$end" ]; then
      days=$(( ($(date -d "$end" +%s) - now) / 86400 ))
      out=$(jq --arg h "$h" --argjson d "$days" '. + [{host: $h, days_left: $d}]' <<<"$out")
    else
      out=$(jq --arg h "$h" '. + [{host: $h, days_left: null}]' <<<"$out")
    fi
  done
  echo "$out"
}

domains_json() {
  local out='[]' d exp days now; now=$(date +%s)
  for d in "${DOMAINS[@]}"; do
    exp=$(curl -sL -m 15 "https://rdap.org/domain/$d" 2>/dev/null \
          | jq -r '[.events[]? | select(.eventAction == "expiration")][0].eventDate // empty')
    if [ -n "$exp" ]; then
      days=$(( ($(date -d "$exp" +%s) - now) / 86400 ))
      out=$(jq --arg d "$d" --arg e "$exp" --argjson dl "$days" \
        '. + [{domain: $d, expires: $e, days_left: $dl}]' <<<"$out")
    else
      out=$(jq --arg d "$d" '. + [{domain: $d, expires: null, days_left: null}]' <<<"$out")
    fi
  done
  echo "$out"
}

main() {
  local logins4 raw3 logins3 auth tls domains
  logins4=$(sudo -n journalctl -t swordfish-alerts --since "7 days ago" -o cat --no-pager 2>/dev/null \
            | tail -15 | lines_to_logins)
  # capture SPLIT from fallback: `ssh | jq || echo []` under pipefail emitted
  # BOTH jq's [] and the fallback [] when ssh died -> invalid JSON -> the
  # whole card (syd4 data included) went UNAVAILABLE (code review 2026-07-13)
  raw3=$(ssh_syd3 'sudo -n journalctl -t swordfish-alerts --since=-7d -o cat --no-pager 2>/dev/null | tail -15' \
         2>/dev/null) || raw3=""
  logins3=$(lines_to_logins <<<"$raw3")
  auth=$(jq -n --argjson a "$(local_auth)" --argjson b "$(syd3_auth)" '[$a, $b]')
  tls=$(tls_json)
  domains=$(domains_json)
  jq -n --argjson t "$(date +%s)" --argjson l4 "$logins4" --argjson l3 "$logins3" \
        --argjson auth "$auth" --argjson tls "$tls" --argjson dom "$domains" \
    '{generated_at: $t, logins: ($l4 + $l3), auth: $auth, tls: $tls, domains: $dom,
      note: "syd1/syd2 login alerts go straight to Telegram; no cockpit-readable journal by design"}' \
    | emit security
}

main || fail security "security collector crashed"
