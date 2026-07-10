# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-10 20:20 +10:00 (machine migration in motion: env seed staged, syd3 cockpit live + 29/29 verified; ops queue PARKED by design until the cockpit rehearsal passes)_

## State

**Machine migration (the founder is losing the Windows work laptop to IT lockdown;
next cockpit = a VPS driven from the 2011 MacBook's terminal, phone browser for OAuth):**

- **Environment seed staged 2026-07-10** to the portable drive at `migration-staging\`
  (copy-only; the laptop still works unchanged): full `~/.claude` incl. every agent's
  memory + transcripts, global skills, Claude OAuth credentials, `~/.claude.json`
  (MCP configs + keys), SSH keypairs, gh profile, `.gitconfig`. `MANIFEST.md` in that
  folder = restore map + new-host bring-up order + key-rotation checklist (rotation
  runs only AFTER the new cockpit is proven). GitHub tokens were Windows-Credential-
  Manager-bound → re-auth by device flow, not file copy. An `AGENT-BROADCAST.md`
  sits alongside for the other portfolio projects' agents (never commit it here).
  **Final-day rule:** re-run the refresh commands at the top of MANIFEST.md before
  abandoning the laptop. The research vault is founder-copied separately.
- **syd3 = agent cockpit, LIVE + VERIFIED** (CHARTER machine-migration amendment):
  Vultr syd `vhf-1c-2gb` $12/mo credit-funded, 139.180.170.11, `syd3.swordfish.cfd`,
  provider firewall + ufw = tcp/22 only, NO Docker, toolchain baked in
  (git · gh · tmux · Node 22 · Claude Code). cockpit-smoke run 29085148074 =
  **29/29 + ssh-audit clean** (commit 11ac255). ⚠️ Not yet primary: needs founder
  logins + seed restore + a `~/.claude` backup ratchet first.

**syd2 posture unchanged: 60/63 — pre-cutover ceiling** (3 FAILs = sniStrict route
checks for `hello./status./metrics.`; certs can only issue once DNS points here).
syd1 (Vultr) still live as fallback. Thalon brief delivered
(`agent_handoff/thalon-wiring-brief-2026-07-08.md`), six ask-backs outstanding;
stealth mode on record (thalon.org unwired until launch call; staging behind a
neutral swordfish.cfd name + BasicAuth + noindex).

## Next (strict order — sequencing invariant: cockpit rehearsal BEFORE cutover; never both at once)

1. **Founder, at the work laptop (before it is lost):** copy the vault to a portable
   drive; hand `AGENT-BROADCAST.md` to the other project agents; on the final day run
   the MANIFEST.md refresh commands.
2. **Founder, from home (MacBook):** rehearsal — `ssh deploy@syd3.swordfish.cfd`,
   `tmux`, `claude` login (phone browser completes the URL+code flow), `gh auth login`
   (device flow), `scp -r` the staging folder from the drive to syd3, restore per
   MANIFEST.md, then prove the loop by dispatching cockpit-smoke from syd3 itself.
3. ~~Cockpit backup ratchet~~ **DONE 2026-07-10 (hotspot session):** syd3 restic→B2
   nightly (bucket `swordfish-syd3-backups`, source = `/home/deploy` whole-home,
   STANDALONE profile — resticprofile `inherit` merges lists positionally, lesson in
   `provisioning/backup/profiles.yaml`), first backup + runner-side restore drill
   green (runs 29091998789 / 29092092325, RTO 3 s / RPO 0 h). New workflows:
   `cockpit-backups-apply` + `cockpit-restore-drill` (SYD3_-scoped secrets — fleet
   secrets never shared across boxes). Dead-man off-infra leg LIVE
   2026-07-10 (founder-created healthchecks check; receiver-acked on apply run
   29092668496). Remaining follow-ups: **Kuma push leg after cutover** · **founder
   records `inventory/secrets/restic-syd3.password` in the password manager (the
   DR key — losing it = losing the cockpit backups)** · drill content checks grow
   after the seed restore (marked in cockpit-restore-drill.yml).
4. **⛔ PARKED OPS QUEUE — resumes only after the rehearsal passes, from the proven cockpit:**
   1. **⛔ CUTOVER (founder gate — present the step-card first).** Re-point A-records
      `deploy. status. metrics. hello.` → 103.249.236.41 (set-a-record.ps1 ×4) →
      edge-apply vs syd2 with `deploy_fqdn=deploy.swordfish.cfd` → Server Domain
      update in syd2 Dokploy (founder or agent via API) → smoke vs syd2 with default
      deploy_fqdn → **63/63** (certs issue on first SNI hit; syd1 untouched fallback).
   2. **verify-deadman on syd2** — the natural-fire timer passed 15:00 UTC Jul 8;
      dispatch verify-deadman (host=syd2.swordfish.cfd) — window state unknown since,
      check receiver freshness when resuming.
   3. **Soak** (founder-set duration; Kuma + UptimeRobot watch the moved names) →
      destroy the Vultr syd1 *instance* — **re-confirm destroy-vs-keep at that gate:
      the machine-migration amendment notes syd1 may stay as warm fallback** →
      drop temp `deploy2/status2/metrics2` records → flip KUMA_PUSH_URL secret to
      the `status.` host + re-run backups-apply → retire/annotate the syd1 inventory row.
   4. **Thalon wiring** (after the six ask-backs return): Dokploy project `thalon` +
      project-scoped API credential + staging hostname (BasicAuth + noindex) +
      `THALON_DATA_DIR` volume into restic set + PGlite export hook into
      `pre-backup.d` + Kuma monitor on staging.
   5. **Hermes E0 + Pi scoping** per the CHARTER in-flight record (Vercel AI Gateway
      + Groq/Llama, US$10/mo cap; founder provides the gateway key at install).

## Standing

- Traefik 3.7.6 Renovate PR: edge-apply protocol (post-cutover, default deploy_fqdn;
  pre-cutover syd2 runs need `deploy_fqdn=deploy2.swordfish.cfd`).
- Do NOT re-dispatch backups-apply / restore-drill vs syd1 — repo secrets hold syd2's
  bucket key + receivers now.
- AGENTS.md edits break the CLAUDE.md hardlink — recreate + hash-verify after.
- Fleet `hardening-smoke` does NOT apply to cockpit-class boxes — use `cockpit-smoke`.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel · zero guarded tokens
(A/B only — Thalon unmasked) in tracked files · backups-before-workloads satisfied on
syd2, OPEN on syd3 (cockpit state) · cutover + instance-destroy are founder gates ·
thalon.org stays unwired until the launch call · cockpit rehearsal precedes cutover ·
founder is the sole author.

_All work is committed and pushed — safe to clear; this file + agent memory + the
staged seed carry the full state to any machine._
