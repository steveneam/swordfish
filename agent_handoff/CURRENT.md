# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 19:15 +10:00 (Bucket 3 built + executed — backups live, restore drill green)_

## State

**Bucket 3 BUILT AND VERIFIED on the box — checkpoint open, one founder action
pending (dead-man URL).** Backups now precede workloads (invariant satisfied):

- B2: `swordfish-syd1-backups` (US West, private, 30-day version retention) +
  bucket-scoped key — created + idempotency-verified by
  `provisioning/b2/create-backup-bucket.ps1`; scoped key + repo password live in
  `inventory/secrets/` (gitignored) and as CI secrets (`RESTIC_PASSWORD`,
  `RESTIC_B2_KEY_ID/KEY`).
- Box: restic 0.19.1 + resticprofile 0.33.1 (`no_self_update`), sha256-pinned in
  `provisioning/host/phase7-backups.sh`; config = `provisioning/backup/profiles.yaml`;
  nightly backup 15:00 UTC / prune Sat / check(10%) Sun as systemd timers;
  pre-backup `pg_dump` hook covers the control-plane DB (raw pgdata volume
  excluded by design). Applied via `backups-apply` run 28854506539: converge +
  idempotent re-run + **first real backup (snapshot `f810278c`)** green.
- **Restore drill green** (run 28854625726, runner-side = total-box-loss path):
  RTO 3 s, RPO ≤24 h, pg_dump + repo cross-check verified — first row recorded in
  `runbooks/backup-restore.md`. Monthly-pass cadence STARTED (next ~2026-08-07).
- Posture now **50/50 assertions** (10 new Bucket-3 checks incl. a live
  ≥1-snapshot probe). Dokploy upgrade freeze LIFTED (`runbooks/edge.md`).
- Opportunistic seam landed: `provisioning/dns/` → `provisioning/porkbun/`, new
  `provisioning/b2/` (Checkpoint-2 amendment 6).

## Bucket-3 gate: two founder actions, then closed

1. **healthchecks.io** (free tier): create account + a check named
   `swordfish-syd1-backup` (period 1 day, grace 6 h) → then
   `gh secret set HEALTHCHECKS_PING_URL --body <ping-url>` → re-dispatch
   `backups-apply` with `test_deadman: true` → confirm the notification arrived.
   (Until then hc-ping warns per run; backups themselves are unaffected.)
2. **Password manager:** copy `inventory/secrets/restic-syd1.password` and
   `inventory/secrets/b2-syd1-restic.env` founder-side — the repo password is
   unrecoverable and is the whole DR story.

Timer's first natural fire = tonight 15:00 UTC (01:00 AEST); the dead-man
witnesses it once the URL is set.

## Next — Bucket-3 CHECKPOINT, then Bucket 4

Founder review of this bucket + the two actions above. Then Bucket 4 (dogfood
deploy + monitoring — the AI-operability test): hello container CI→GHCR,
Uptime Kuma (its push monitor joins the dead-man) + Beszel via Dokploy MCP,
ntfy + UptimeRobot, rate-limit middleware on public routers only.
Standing: Renovate PR open (socket-proxy 0.4.2 — edge pin bump = edge-apply
protocol) · FortiGuard recategorization pending (office stays eyes-limited).

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 + 53 blocked
from corp network) · zero guarded tokens in tracked files, extends to public
names (CT logs) · backups before workloads — **now satisfied on syd1** · every
spend is an Approval Gate · founder is the sole author.

_All work is committed and pushed — it is safe to clear this session._
