# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-08 03:47 +10:00 (dogfood replayed on syd2 — 60/63 = pre-cutover ceiling; next = deadman natural fire, then the CUTOVER gate)_

## State

**syd2 posture: 60/63 — the pre-cutover ceiling.** The only 3 FAILs are
sniStrict route checks for `hello./status./metrics.` whose LE certs can only
issue once DNS points here. Everything else is green.

- **Dogfood replayed via Dokploy REST** (project `swordfish` on syd2; IDs in
  `inventory/boxes.md`): kuma healthy at `status2.` (real cert) · beszel
  hub+agent at `metrics2.` (real cert; BESZEL_AGENT_KEY flow done) · hello
  running (recreated with explicit `appName: swordfish-hello` — **create
  accepts an appName base**, random-name landmine avoided) · ratelimit on all
  public routers · domains carry real + temp names so cutover needs no domain
  edits, just DNS + cert issuance.
- **Both dead-man legs receiver-acknowledged from syd2** (run 28886561884):
  healthchecks.io check `swordfish-syd2-backups` + syd2's own Kuma push
  monitor (`swordfish-syd2-backup`, ntfy → founder phone). Dump hooks armed
  (kuma+beszel dumps now in the snapshot set). Repo secrets
  HEALTHCHECKS_PING_URL / KUMA_PUSH_URL now hold syd2's receivers.
- **Bootstraps are box-parameterized** (`KUMA_BASE`/`BESZEL_BASE`/`BOX`,
  defaults track syd2 — syd1's instances are frozen); verify-deadman derives
  the unit name from its host input.
- **Hermes record amended** (founder call): Vercel AI Gateway + Groq/Llama
  3.3-class for E0/E1, US$10/mo cap (expect <$1), Anthropic API key =
  escalation path (subscriptions don't transfer to third-party harnesses).
  CHARTER "Bucket-5 in-flight record".
- Earlier this session: Thalon unmask · syd2 purchase + hardening + adapter +
  firewall · edge at deploy2 · backups + tested restore (RTO 3s) · UTC-clock
  catch (posture total 63).

## Next

1. **verify-deadman natural fire on syd2** — after today's 15:00 UTC timer:
   dispatch `verify-deadman` with host=syd2.swordfish.cfd (default 26h window
   is fine). Both legs + exit 0 = the graduation-strength dead-man proof.
2. **⛔ CUTOVER (founder gate — present a step-card first):**
   re-point A-records `deploy. status. metrics. hello.` → 103.249.236.41
   (scripted, set-a-record.ps1) → re-run edge-apply vs syd2 with
   `deploy_fqdn=deploy.swordfish.cfd` (bootstrap-route re-point is that same
   converge) → founder sets Server Domain in syd2 Dokploy UI to
   deploy.swordfish.cfd (or agent via API) → smoke vs syd2 with default
   deploy_fqdn → **63/63** (certs issue on first SNI hit).
3. **Soak** (founder-set duration; UptimeRobot + Kuma watch the moved names)
   → then destroy the Vultr *instance* (account + credit stay) → drop temp
   `deploy2/status2/metrics2` A-records + flip KUMA_PUSH_URL to `status.`
   host + re-run backups-apply (installs the updated kuma-url) → update
   `syd1` row in inventory to retired.
4. **Thalon handoff pack** (CHARTER addendum 2 item 4): Dokploy project +
   per-project scoped API cred · GHCR pull slot `ghcr.io/steveneam/thalon-web`
   · domains `thalon.org` + `www` → syd2 · `THALON_DATA_DIR` volume into the
   restic set · PGlite export hook into `pre-backup.d`.
5. **Hermes E0 + Pi scoping** per the amended in-flight record (founder
   provides a Vercel AI Gateway key at install time).

## Standing

- Traefik 3.7.6 Renovate PR: edge-apply protocol (pre-cutover syd2 runs use
  `deploy_fqdn=deploy2.swordfish.cfd`).
- syd1 keeps running its own nightly + receivers until cutover completes
  (parallel-run); do NOT re-dispatch backups-apply/drill vs syd1 — repo
  secrets now hold syd2's bucket key + receivers.
- AGENTS.md edits break the CLAUDE.md hardlink — recreate + verify after.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel · zero guarded
tokens (A/B only — Thalon unmasked) in tracked files · backups-before-workloads
satisfied on syd2 · cutover + instance-destroy are founder gates · founder is
the sole author.

_All work is committed and pushed — it is safe to clear this session._
