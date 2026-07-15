# SSH login audit — who has actually logged into the fleet

_First audit stamped 2026-07-13 04:30 UTC (founder request: confirm all access
is cloud/founder-owned, none from the old work laptop's corporate network).
Method: full journald sshd history (`Accepted publickey`) per auditable box,
aggregated by source IP + key fingerprint; owners resolved via whois; CI
sources verified against GitHub's published Actions ranges (api.github.com/meta)._

## Verdict (2026-07-13)

- **Every accepted login on syd3 + syd4 (full history) is publickey** with one
  of the two fleet keys — `swordfish-ops` (founder/cockpit) or `swordfish-ci`
  (GitHub secret). Password auth is disabled fleet-wide, so this table IS the
  complete access record.
- **No corporate/business source appears anywhere.** The old work laptop's
  office network (a business netblock) never shows. Founder-key logins come
  only from two AU **consumer** ISPs — Optus and Leaptel — i.e. home/hotspot.
- Founder-key logins cluster in the **2026-07-10/11 migration window** (the
  laptop and the Mac were both legitimately active then — hotspot session,
  d4a7471). **Jul 12: zero. Jul 13: exactly one** (03:23 UTC, Leaptel) = the
  founder's live code-server session at audit time. No unexplained device.
- Every `swordfish-ci` login source sits inside GitHub's published Actions
  runner ranges (Azure netblocks + GitHub's own `64.236.128.0/17`).

## Sources seen (full journald history: syd4 + syd3, both first-booted 2026-07-10)

| Source IP | Owner | Key | Boxes | Window | Class |
|---|---|---|---|---|---|
| 49.186.75.98 | Optus (AU consumer) | swordfish-ops | syd3, syd4 | Jul 10–11 | founder — migration window |
| 202.128.115.13 | Leaptel (AU consumer NBN) | swordfish-ops | syd4 | Jul 10 + Jul 13 | founder — incl. current session |
| 66.226.147.123 | syd4 itself (BinaryLane) | swordfish-ops | syd3 | Jul 13 | cockpit agent, box-to-box ops |
| 12 distinct: 52.159.x, 135.232.x, 20.x, 40.84.x, 172.x, 64.236.192.151 | Microsoft Azure + GitHub (`64.236.128.0/17`) | swordfish-ci | syd3, syd4 | ongoing | GitHub Actions runners (CI-as-hands) |

Fleet reference IPs: syd1 45.63.24.122 (Vultr) · syd2 103.249.236.41
(BinaryLane) · syd3 139.180.170.11 (Vultr) · syd4 66.226.147.123 (BinaryLane).

## Coverage limits

- **syd4, syd3**: complete (journald reaches back to first boot).
- **syd2, syd1**: inbound 22 answers the CI runners only (cockpit SSH times
  out), and no workflow prints journal excerpts — deliberately: the fleet has
  no generic remote-exec channel, only fixed-script applies (posture feature,
  not a gap). syd2's logins since 2026-07-11 are mirrored live to the
  founder's Telegram by the alerts layer; expected sources there are the same
  CI pool + founder keys.

## Re-run (any box, and what "bad" looks like)

    sudo journalctl -u ssh --no-pager | grep 'Accepted publickey' \
      | awk '{for(i=1;i<=NF;i++){if($i=="from")ip=$(i+1); if($i=="ssh2:")fp=$(i+2)}; print ip, fp}' \
      | sort | uniq -c | sort -rn

Every source must be explainable as: a fleet box, a GitHub Actions range
(`swordfish-ci` key; check api.github.com/meta), or a founder consumer-ISP
address (`swordfish-ops` key). Anything else — especially a business
netblock — is an incident: treat per the alerts runbook, rotate the key it used.

Since 2026-07-15 the live Telegram login alerts carry this classification
inline (🔁 fleet / 🏠 founder / 🤖 CI / ⚠️ unknown) — the classifier in
`provisioning/host/setup-login-alerts.sh` mirrors the fleet + founder IPs
above, so **update both files together** when the fleet or his ISP changes.
