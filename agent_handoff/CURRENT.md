# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-08 03:03 +10:00 (syd2 edge + control plane LIVE at deploy2; founder registers Dokploy, then backups + replay)_

## State

**syd2 posture: 42/62.** Everything except backups (13) + dogfood (7) is green.

- Edge + control plane converged on syd2 via `edge-apply` run 28883853825:
  swordfish-traefik + socket-proxy own 80/443, **Dokploy v0.29.10 pinned,
  reachable at `https://deploy2.swordfish.cfd` with a real LE cert**
  (laptop CA-validated probe: HTTP 307 → fresh instance awaiting /register).
  Idempotency proven in CI (second phase3 run = no changes).
- **Parallel-run parameterization landed:** `phase3-edge.sh` takes
  `DEPLOY_FQDN` (default `deploy.swordfish.cfd`) and its bootstrap-route
  converge rewrites when the routed FQDN differs — **the DNS-cutover re-point
  is just re-running edge-apply with the real FQDN**. `assert-hardening.sh`
  probes `$DEPLOY_FQDN` and derives the backup profile from `hostname -s`
  (syd1 unchanged; syd2 will assert `profile-syd2`). All three workflows
  (edge-apply / host-apply / hardening-smoke) gained a `deploy_fqdn` input.
- Assertion fix from live observation: fresh Dokploy 307s to /register →
  307 joined the accepted 30x class in the route-liveness checks.
- Earlier this session: syd2 purchased + hardened at first boot (29/62 →
  Phase 0–2 all green), BinaryLane adapter proven (create-box no-op converge,
  provider firewall 22/80/443+drop-all + SSH-still-green), A-record `syd2`,
  swap datapoint (BinaryLane ships no swapfile → guard created 2G), and the
  **Thalon unmask** (token C removed; CHARTER addendum 2 = tenant note).

## Next

1. **[founder, 2 min]** Open `https://deploy2.swordfish.cfd` → register the
   admin account. **Immediately after** (API-channel-before-UI-changes rule):
   Settings → API/CLI → generate an API key → `.env` as
   `DOKPLOY_SYD2_API_KEY=`. No other UI changes (Server Domain stays unset —
   the bootstrap route owns deploy2 until cutover).
2. Agent — backups leg (no founder dependency): `b2/create-backup-bucket.ps1`
   for `swordfish-syd2-backups` (US West, scoped key) → `backups-apply` vs
   syd2 → **tested restore** → expect posture 55/62.
3. Agent — dogfood replay via Dokploy REST/API-key on syd2 (the portability
   drill; MCP config still points at syd1): kuma + beszel + hello, domains
   created before first deploy, ratelimit on public routers. Dead-man legs:
   note syd2's resticprofile will ping healthchecks.io + the kuma-url — decide
   whether the parallel-run window pings a NEW healthchecks check + syd2's own
   Kuma (recommended) or shares syd1's (ambiguous acks). Then verify-deadman
   vs syd2 → 62/62.
4. Cutover (founder gate): re-point `deploy./status./metrics./hello.` A-records
   to 103.249.236.41 + re-run edge-apply with `deploy_fqdn=deploy.swordfish.cfd`
   + founder sets Server Domain; soak; **only then destroy the Vultr instance**
   (account + credit stay). Drop temp `deploy2` record after soak.
5. Post-verification: **Thalon handoff pack** (CHARTER addendum 2 item 4) +
   PGlite export hook; **Hermes E0 pilot + Pi scoping** (Bucket-4 ruling 3 —
   LLM budget is its own Approval Gate, ask the founder for provider + cap).

## Standing

- Traefik 3.7.6 Renovate PR when it opens: edge pin bump = edge-apply protocol
  (now also re-run on syd2 with `deploy_fqdn=deploy2.swordfish.cfd` pre-cutover).
- verify-deadman still points at syd1 until the backup layer moves.
- Editing AGENTS.md breaks the CLAUDE.md hardlink — recreate + verify after.
- Dokploy UI quirk ledger: `runbooks/dogfood.md`.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel · zero guarded
tokens (A/B only — Thalon unmasked) in tracked files · **backups before
workloads: no tenant on syd2 until restic + tested restore exist there** ·
every spend is an Approval Gate · founder is the sole author.

_All work is committed and pushed — it is safe to clear this session._
