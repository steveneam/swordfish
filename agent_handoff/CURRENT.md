# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-08 04:05 +10:00 (syd2 at 60/63 pre-cutover ceiling; Thalon brief delivered w/ stealth mode; next = CUTOVER gate, deadman natural fire rides the soak)_

## State

**syd2 posture: 60/63 — pre-cutover ceiling** (3 FAILs = sniStrict route checks
for `hello./status./metrics.`; certs can only issue once DNS points here).
Dogfood is fully replayed: kuma (`status2.`, real cert) · beszel hub+agent
(`metrics2.`) · hello (`swordfish-hello-ksv6id`) · ratelimit on public routers ·
both dead-man legs receiver-acked from syd2 (healthchecks `swordfish-syd2-backups`
+ syd2's own Kuma push) · dump hooks armed. IDs in `runbooks/dogfood.md` +
`inventory/boxes.md`.

**Since the 03:47 wrap:**

- **Thalon wiring brief delivered** (founder hands over
  `agent_handoff/thalon-wiring-brief-2026-07-08.md`): box status, handoff-pack
  contents, six ask-backs (port · image digest · THALON_DATA_DIR · PGlite
  export-hook spec · DNS owner · env list).
- **Stealth mode (founder call):** `thalon.org` stays UNWIRED until Thalon's
  launch call — no DNS, no cert, no CT-log entry. At wiring, thalon-web gets a
  **neutral staging hostname on swordfish.cfd** with edge **BasicAuth +
  X-Robots-Tag noindex**; launch = add thalon.org domains + DNS flip + drop
  BasicAuth (no redeploy). Design detail open for the wiring leg: where the
  basicauth users hash lives (NOT in a tracked file — ship like backup secrets
  or via Dokploy surface).
- **Ratchet audit closed:** appName-base lesson + syd2 service IDs + REST-as-
  apply-channel now in `runbooks/dogfood.md`; laptop-side gotchas (PS 5.1
  gh-secret mangling, CLAUDE.md hardlink break) saved to agent memory.
- **Hermes record (final):** Vercel AI Gateway + Groq/Llama 3.3-class for
  E0/E1, US$10/mo cap, Anthropic API key = escalation path (CHARTER
  "Bucket-5 in-flight record").

## Next

1. **⛔ CUTOVER (founder gate — present a step-card first).** Cutover may
   precede the deadman natural fire (cutover ≠ destroy; the fire rides the
   soak): re-point A-records `deploy. status. metrics. hello.` →
   103.249.236.41 (set-a-record.ps1 ×4) → edge-apply vs syd2 with
   `deploy_fqdn=deploy.swordfish.cfd` (bootstrap-route re-point = that
   converge) → founder (or agent via API) sets Server Domain in syd2 Dokploy →
   smoke vs syd2 with default deploy_fqdn → **63/63** (certs issue on first
   SNI hit; syd1 untouched, still live as fallback).
2. **verify-deadman natural fire on syd2** — the timer fires **15:00 UTC
   Jul 8 (= 01:00 AEST Jul 9)**; dispatch verify-deadman
   (host=syd2.swordfish.cfd, default 26h window) any time after that. Note:
   before the timer fires, the unit journal is empty (the earlier backup was
   manual) — do not expect it to pass early.
3. **Soak** (founder-set duration; Kuma + UptimeRobot watch the moved names)
   → destroy the Vultr *instance* (account + credit stay) → drop temp
   `deploy2/status2/metrics2` records → flip KUMA_PUSH_URL secret to the
   `status.` host + re-run backups-apply (installs updated kuma-url) →
   retire the syd1 inventory row.
4. **Thalon wiring** (after Thalon returns the six ask-backs): Dokploy project
   `thalon` + project-scoped API credential + staging hostname (BasicAuth +
   noindex) + `THALON_DATA_DIR` volume into restic set + PGlite export hook
   into `pre-backup.d` + Kuma monitor on staging.
5. **Hermes E0 + Pi scoping** per the in-flight record (founder provides a
   Vercel AI Gateway key at install).

## Standing

- Traefik 3.7.6 Renovate PR: edge-apply protocol (post-cutover, default
  deploy_fqdn; pre-cutover syd2 runs need `deploy_fqdn=deploy2.swordfish.cfd`).
- Do NOT re-dispatch backups-apply / restore-drill vs syd1 — repo secrets hold
  syd2's bucket key + receivers now.
- AGENTS.md edits break the CLAUDE.md hardlink — recreate + hash-verify after.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel · zero guarded
tokens (A/B only — Thalon unmasked) in tracked files · backups-before-workloads
satisfied on syd2 · cutover + instance-destroy are founder gates · thalon.org
stays unwired until the launch call · founder is the sole author.

_All work is committed and pushed — it is safe to clear this session._
