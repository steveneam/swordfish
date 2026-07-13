# DNS cutover step-card — syd1 → syd2 (founder gate)

_Bucket-5 closer. ⛔ The cutover MOMENT is a founder gate (CHARTER parallel-run
protocol; AGENTS.md rule 4). Your entire touch is one line in chat or the
Swordfish Telegram topic: **`cutover go`**. Everything below is agent-executed
from syd4 + CI-as-hands. Built + pre-flight-verified 2026-07-13._

## What this is

The real hostnames (`deploy.` `status.` `metrics.` `hello.` `.swordfish.cfd`)
re-point from syd1 (Vultr, 45.63.24.122) to syd2 (BinaryLane, 103.249.236.41).
syd2 has been serving the same stacks at the temp `*2` names since 2026-07-08;
syd1 is converged and frozen. After the flip, syd2 is THE box, the posture
ceiling lifts 60/63 → 63/63, and syd1 enters soak as the warm rollback target.

## Pre-flight evidence (all verified green 2026-07-13, before presenting this card)

| check | evidence |
|---|---|
| syd2 posture at pre-cutover ceiling 60/63 | run 28886809947 — the 3 FAILs are real-name TLS route checks that can only pass post-cutover |
| syd2 backups + tested restore | nightly restic→B2 15:00 UTC; drill RTO 3 s / RPO 0 h (run 28885492767) |
| verify-deadman natural fire vs syd2 | run 29251119226 (2026-07-13, SUCCESS): nightly ran + BOTH dead-man legs receiver-acked inside 26 h |
| monitors cutover-ready | syd2's Kuma HTTP monitors already probe the REAL names (bootstrap constants); beszel/kuma bootstrap defaults are real-name; `preview.` (thalon staging) already points at syd2 |
| API channel before UI changes | syd2 Dokploy agent key verified live (200 vs deploy2) from syd4's `.env` (`DOKPLOY_SYD2_API_KEY`) |
| rollback path | 4 A-records back to 45.63.24.122 (idempotent porkbun upsert); TTL 600 s → ≤10 min; syd1 stays live + untouched through soak |

## The moment (agent executes on `cutover go`; ~20–30 min)

1. **DNS**: `provisioning/porkbun/set-a-record.ps1` ×4 — `deploy` `status`
   `metrics` `hello` → 103.249.236.41 (pwsh + Porkbun keys live on syd4).
2. **Propagation wait**: dig loop until all 4 resolve to syd2 (TTL 600).
3. **`edge-apply` vs `host=syd2.swordfish.cfd`** (`deploy_fqdn` default =
   `deploy.swordfish.cfd`): converges the Dokploy router off the temp name,
   real LE cert issues via TLS-ALPN, idempotency proof re-run included.
   _Expected side effect: `deploy2.` stops routing (404) — by design._
4. **`hardening-smoke` vs syd2** (defaults): expect **63/63**.
5. **Repo flips, one commit** (cross-refs pinned in `collectors/lib.sh`):
   - `provisioning/workstation/collectors/lib.sh` — `SYD2_HOSTS` = the four
     real names; delete `SYD1_HOSTS`.
   - `provisioning/workstation/collectors/collect-fleet.sh` — drop the syd1
     `api_box` call; syd2's beszel/kuma bases flip `metrics2.`/`status2.` →
     `metrics.`/`status.`.
   - `provisioning/thalon/staging-assert.sh` — default `DOKPLOY_URL` →
     `https://deploy.swordfish.cfd`.
6. **thalon CI**: repo variable `DOKPLOY_API_BASE` →
   `https://deploy.swordfish.cfd/api` (they were told it stays a repo
   variable); re-run `staging-assert.sh` to prove the tenant chain.
7. **syd4 `~/.claude.json`** dokploy MCP: swap `DOKPLOY_API_KEY` to the syd2
   key (URL already reads `deploy.swordfish.cfd`).
8. **Verify**: all 4 real names serve from syd2 with valid LE certs; Kuma
   monitors green; dashboard fleet card healthy; tonight's 21:00 UTC morning
   briefing probes the flipped names as a free extra witness.

## Soak, then syd1's fate (separate gate — nothing is destroyed today)

- **Soak = 72 h**: monitors green + ≥1 natural verify-deadman pass vs syd2
  + morning briefings clean.
- The `*2` A-records STAY during soak (rollback aid); retire them at soak end.
- After soak, the **syd1 destroy-vs-warm-fallback decision** presents as its
  own founder gate (CHARTER machine-migration amendment: fate re-confirms at
  the cutover gate; Vultr account + credit are retained as fallback either
  way). At destroy also: retire syd1's healthchecks check, its UptimeRobot
  monitors, and its restic B2 bucket per the backup runbook.

## Rollback (any point, no founder action needed)

`set-a-record.ps1` ×4 back to 45.63.24.122 — syd1 was never touched and
serves again within TTL (≤10 min). Repo flips revert via git; thalon's repo
variable flips back the same way it flipped.

## Founder-visible changes after cutover

- Dokploy UI login moves to **https://deploy.swordfish.cfd** (same admin
  account you registered at deploy2 — bookmark update only).
- `deploy2.` 404s; `status2.`/`metrics2.` keep serving until soak-end retirement.
