# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-11 02:21 +10:00 (FIRST BOOT ON syd4 — the machine migration LANDED;
this file is now written from the box itself. Ops queue still parked pending the
founder's rehearsal-pass confirmation.)_

## State

**MIGRATION LANDED — the agent lives on syd4 now** (BinaryLane `std-4vcpu` 4 vCPU /
8 GB / 100 GB, 66.226.147.123, `syd4.swordfish.cfd`, tcp/22 only, NO Docker; founder
drives it from the 2011 MacBook over SSH). First-boot verification, all green:

- `hostname -s` = syd4, login banner shown; agent memory + transcripts loaded
  (MANIFEST Part 4 slug rename worked — the agent knows its own history).
- Repo `~/work/swordfish` clean at `0b45b6b` = origin/main; `.env` +
  `inventory/secrets/` + `.context/` present and confirmed gitignored. Vault restored
  as **plain files at `~/vault` (READ-ONLY by rule, no MCP)**; Thalon repo at
  `~/work/thalon`.
- Grep guard PASS via on-box pwsh 7.6.3.
- **Real op end-to-end:** cockpit-smoke dispatched *from this box* vs
  syd4.swordfish.cfd → **34/34** (run 29107082841 — the count grew from 33 with the
  smoothness-layer assertion, commit 0b45b6b). gh device-flow auth live as steveneam.
- **First-boot wiring done:** Dokploy MCP re-added **local scope** from the staged
  `~/migration/claude-global.json` (key lives in untracked `~/.claude.json`; note the
  staged project key is `E:\swordfish` — match by substring). Stale `obsidian-vault`
  entry **removed from tracked `.mcp.json`** (this commit). Break-glass
  `id_ed25519` installed to `~/.ssh` (chmod 600) — CI-as-hands stays the primary
  channel. Plugins carried over automatically. The Chrome browser MCP is the one
  lost capability, as documented — not needed for ops.
- USB seed was refreshed 23:50 on the laptop's final day — the drive is current;
  memories written since live here and are restic-backed nightly (RTO 3 s proven).

**syd3 = ops cockpit, LIVE + VERIFIED + BACKED UP** (unchanged): Vultr syd
`vhf-1c-2gb` $12/mo credit-funded, 139.180.170.11, `syd3.swordfish.cfd`, tcp/22
only, NO Docker. cockpit-smoke 29/29-era green + ssh-audit clean; restic→B2 nightly
+ tested restore (RTO 3 s); dead-man leg receiver-acked. Its **swordfish seed-slice
restore is still open** (optional — end-state A-vs-B, everything-on-syd4 vs
swordfish-isolated-on-syd3, is decided now that the portfolio has moved).

**syd2 posture unchanged: 60/63 — pre-cutover ceiling** (3 FAILs = sniStrict route
checks for `hello./status./metrics.`; certs can only issue once DNS points here).
syd1 (Vultr) still live as fallback. Thalon brief delivered
(`agent_handoff/thalon-wiring-brief-2026-07-08.md`), six ask-backs outstanding;
stealth mode on record (thalon.org unwired until launch call).

## Next (strict order)

1. **Founder: confirm the rehearsal passed.** This first-boot session is the
   evidence (MacBook → syd4, real op green end-to-end). That confirmation — and
   nothing else — un-parks the ops queue.
2. **Box tail (agent, non-gated, next session or on ask):** grow
   cockpit-restore-drill content checks now that `~/.claude` + repos live here
   (marked in `cockpit-restore-drill.yml`). Kuma push dead-man leg comes
   post-cutover.
3. **Optional:** syd3 swordfish-slice restore (MANIFEST minimal-slice checklist) if
   end-state B (infra-key isolation) is chosen.
4. **⛔ PARKED OPS QUEUE — resumes only after item 1, in this order:**
   1. **⛔ CUTOVER (founder gate — present the step-card first).** Re-point A-records
      `deploy. status. metrics. hello.` → 103.249.236.41 (set-a-record.ps1 ×4) →
      edge-apply vs syd2 with `deploy_fqdn=deploy.swordfish.cfd` → Server Domain
      update in syd2 Dokploy → smoke vs syd2 with default deploy_fqdn → **63/63**
      (certs issue on first SNI hit; syd1 untouched fallback).
   2. **verify-deadman on syd2** — natural-fire timer passed 15:00 UTC Jul 8;
      window state unknown since — check receiver freshness when resuming.
   3. **Soak** (founder-set duration) → syd1 **destroy-vs-keep re-confirmed at that
      gate** (amendment notes it may stay as warm fallback) → drop temp
      `deploy2/status2/metrics2` records → flip KUMA_PUSH_URL to the `status.` host
      + re-run backups-apply → retire/annotate the syd1 inventory row.
   4. **Thalon wiring** (after the six ask-backs return): Dokploy project + scoped
      API credential + staging hostname (BasicAuth + noindex) + `THALON_DATA_DIR`
      into restic set + PGlite export hook into `pre-backup.d` + Kuma monitor.
   5. **Hermes E0 + Pi scoping** per CHARTER (Vercel AI Gateway + Groq/Llama,
      US$10/mo cap; founder provides the gateway key at install).
5. **Key rotation** (MANIFEST checklist) only after the whole new environment is
   proven — last step of the migration, not before.

## Standing

- You run on LINUX now: bash, LF, `~/work/swordfish`; repo `.ps1` scripts run via
  `pwsh`. Windows-era paths in old records need translation (E:\ → the drive /
  history).
- Traefik 3.7.6 Renovate PR: edge-apply protocol (post-cutover, default deploy_fqdn;
  pre-cutover syd2 runs need `deploy_fqdn=deploy2.swordfish.cfd`).
- Do NOT re-dispatch backups-apply / restore-drill vs syd1 — repo secrets hold syd2's
  bucket key + receivers now.
- AGENTS.md edits break the CLAUDE.md hardlink — recreate + hash-verify after.
- Fleet `hardening-smoke` does NOT apply to cockpit-class boxes — use `cockpit-smoke`
  (now 34 assertions).

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel · zero guarded tokens
(A/B only — Thalon unmasked) in tracked files · backups-before-workloads satisfied on
syd2/syd3/syd4 · cutover + instance-destroy are founder gates · thalon.org stays
unwired until the launch call · rehearsal-pass confirmation precedes the ops queue ·
founder is the sole author.

_All work is committed and pushed — safe to clear; this file + agent memory (both
living on syd4, restic-backed nightly) carry the full state._
