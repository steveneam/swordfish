# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-08 03:25 +10:00 (syd2 backups DONE + restore-tested, 55/63; next leg = dogfood replay → 63/63 → cutover)_

## State

**syd2 posture: 55/63.** Backups-before-workloads is satisfied on syd2 —
remaining FAILs are only the dogfood layer (7) + kuma-url (1).

- **Backups live + drilled:** restic→B2 `swordfish-syd2-backups` (own bucket +
  scoped key, per-box pattern), first backup end-to-end green
  (run 28885238961), **restore drill green — RTO 3 s / RPO 0 h,
  content-verified** (run 28885492767). Timers: nightly 15:00 / prune Sat /
  check Sun — all UTC.
- **Portability-drill catches this leg** (each fixed at every layer + ratcheted):
  1. **BinaryLane image ships Australia/Sydney TZ** (Vultr shipped UTC) — every
     schedule resolved local (backup = mid-afternoon). Fixed: `timezone: Etc/UTC`
     in both cloud-init yamls, phase2 converge sets UTC + re-elapses timers,
     new `clock: UTC` assertion (posture total now 63).
  2. **Dogfood dump hook** failed hard on a pre-workload box — now self-arming
     (loud SKIP until a workload's first dump exists, hard FAIL after).
  3. Fresh Dokploy 307s to /register — 307 accepted in route-liveness checks.
- **Per-box backup parameterization:** profiles.yaml has per-box profiles
  (syd2 inherits syd1 policy, own repo); phase7 picks profile by `hostname -s`;
  backups-apply gained `install_ping_urls` (false for parallel-run successor —
  the repo-secret URLs belong to the incumbent) + box-derived `--name`.
- **CI secrets convention:** RESTIC_B2_KEY_ID/KEY now hold syd2's scoped key
  (repo secrets track the CURRENT target box; RESTIC_PASSWORD shared across
  boxes on purpose). Gotcha hit live: setting gh secrets from PS 5.1 hashtable
  index expressions mangles them — assign to plain vars first.
- **Hermes gate satisfied** (founder delegated): Anthropic API direct,
  claude-haiku-4-5 for E0/E1, US$10/mo hard cap provider-side — recorded in
  CHARTER "Bucket-5 in-flight record". Install stays post-cutover.
- Earlier this session: Thalon unmask · syd2 purchased + hardened (Phase 0–2
  green at first boot) · BinaryLane adapter + provider firewall · edge +
  Dokploy v0.29.10 live at `deploy2.swordfish.cfd` (real LE cert) · founder
  registered admin; `DOKPLOY_SYD2_API_KEY` in laptop `.env` (validated).

## Next — dogfood replay leg (→ 63/63)

1. **[founder, 2 min]** healthchecks.io: add a NEW check named `syd2-backups`
   (same cadence as syd1's: expect a ping daily, grace ~2h) → copy its ping
   URL. It must NOT reuse syd1's check (ambiguous acks).
2. Agent: replay dogfood via syd2's Dokploy REST API (key in `.env`; MCP still
   points at syd1 — use raw REST or add a second MCP entry): kuma (status.),
   beszel (metrics.), hello (hello.) — domains created BEFORE first deploy,
   `swordfish-ratelimit` on public routers, compose files in `compose/`.
   Kuma bootstrap via `provisioning/kuma/bootstrap.py` → get syd2's OWN push
   URL. Local route asserts pass pre-cutover (probes are --resolve based).
3. Agent: `gh secret set HEALTHCHECKS_PING_URL` (founder's new check) +
   `KUMA_PUSH_URL` (syd2's own) → re-run backups-apply vs syd2 WITH
   `install_ping_urls=true` → verify-deadman vs syd2 → **63/63**.
4. Cutover (founder gate): re-point `deploy./status./metrics./hello.`
   A-records → 103.249.236.41; re-run edge-apply with
   `deploy_fqdn=deploy.swordfish.cfd`; founder updates Server Domain in
   Dokploy; UptimeRobot targets unchanged (names move with DNS); soak;
   **only then destroy the Vultr instance**; drop temp `deploy2` record.
5. Post-verification: **Thalon handoff pack** (CHARTER addendum 2 item 4) +
   PGlite export hook; **Hermes E0 + Pi** per the in-flight record.

## Standing

- Traefik 3.7.6 Renovate PR: edge-apply protocol (syd2 pre-cutover runs use
  `deploy_fqdn=deploy2.swordfish.cfd`).
- verify-deadman + syd1's receivers still point at syd1 until cutover.
- AGENTS.md edits break the CLAUDE.md hardlink — recreate + verify after.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel · zero guarded
tokens (A/B only — Thalon unmasked) in tracked files · backups-before-workloads
**now satisfied on syd2** (tenants may land after full verification + cutover
per the parallel-run protocol) · every spend is an Approval Gate · founder is
the sole author.

_All work is committed and pushed — it is safe to clear this session._
