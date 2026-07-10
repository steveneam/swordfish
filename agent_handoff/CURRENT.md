# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-11 03:05 +10:00 (FIRST BOOT ON syd4 — the machine migration LANDED
and the rehearsal's pain points are already ratcheted. Ops queue still parked pending
the founder's rehearsal-pass confirmation.)_

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

**Rehearsal debrief (founder feedback 2026-07-11, fixes applied same session):**

- **The claude login was an ordeal:** restored `.credentials.json` did NOT carry the
  login; the long OAuth URL couldn't be copied because tmux mouse mode was capturing
  the terminal's mouse (native Mac selection dead). Founder had to disable mouse mode
  by hand, select/paste into Chromium, relay the code back. **Ratcheted:** tmux
  `mouse off` is now the default on syd4 (live) + BOTH cloud-inits, with `prefix+m`
  as an on-demand toggle and a `copy text` crib line in the login banner. The
  checklist's login section is rewritten: ranked paths (code-server terminal in
  Chromium — founder-verified "worked well" — then native terminal selection, then
  phone QR as fallback; QR is fine for gh's short code, impractical for claude's
  long URL). Logins are per-user-per-box: **the other project agents on syd4 reuse
  this login — the ordeal does not repeat per project.** syd3 will need one login
  round when its slice restores.
- **Checklist Part 3 had a stale vault folder name** — the drive folder was renamed
  to `walter` before the checklist was written. Fixed in the on-box copy
  (`~/migration/MACBOOK-CHECKLIST.md`, now the canonical edition — drive re-copy
  queued for next time the drive is plugged in). The old folder name carried a
  guarded token; `walter` is safe to name.
- **Thalon's gitignored secrets were NOT copied** (location unknown to the founder).
  Recorded in the checklist: thalon's agent inventories its own secret paths on
  first boot, then scp from the drive (check `thalon/` and `thalon-migration/`).
- **syd3 still runs the old mouse-on tmux config** — its firewall blocks box-to-box
  ssh, so the fix couldn't be pushed from here. The Mac-relay one-liners are in the
  checklist's LATER section; cloud-init already pinned for rebuilds.

**Same session — zizmor fixed + drill checks grown:** both cockpit backup workflows
used dynamic `secrets[format(...)]` indexing, which makes Actions provision the
ENTIRE secrets context to the runner (the exact cross-box sharing the per-box
prefixes exist to prevent) and failed zizmor. Reworked to static per-prefix
references + bash indirect expansion (adding a box = add its env lines + case
guard). cockpit-restore-drill content verification is now per-box: SYD4 asserts the
seed state (`~/.claude`, vault, repos + secrets); SYD3 stays at fresh-box baseline
until its slice restore.

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
2. ~~Box tail: grow cockpit-restore-drill content checks~~ **DONE + PROVEN**
   (run 29109061050: snapshot `bb5b6018`, 3.1 GB / 19,336 files restored to the
   runner in 23 s, RPO 0 h, per-box content checks PASS incl. the seed state —
   the whole workstation is recoverable from B2 alone). Remaining tails: Kuma
   push dead-man leg post-cutover · founder relays the mouse-off tmux config to
   syd3 from the Mac (checklist LATER section has the exact commands) · founder
   re-copies the updated MACBOOK-CHECKLIST.md to the USB drive next time it's
   plugged in.
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

**Late-session findings (2026-07-11 ~03:15):**

- **syd4 cannot originate ANY port-22 connection** — github.com, gitlab.com, syd2
  and syd3 all time out on 22 while 443 egress works everywhere; ufw is clean
  (allow outgoing) and the BinaryLane advanced-firewall rules are inbound-only →
  upstream egress-22 policy (BinaryLane network side). CI-as-hands is unaffected
  (runners connect inbound to every box) and remains the primary channel; git/gh
  over HTTPS unaffected. **Founder approved the chartered SSH-on-443 fallback
  (AGENTS.md rule 2) and it is APPLIED on syd3** via the new `ssh443-apply`
  workflow (run 29109656340, converge + idempotency-proof green): sshd listens
  22+443, ufw admits 443 from syd4/32 only, syd3 cloud-init pinned, `ssh syd3`
  alias staged in syd4's ~/.ssh/config. **One link missing: the Vultr
  provider-firewall twin rule** — the Vultr API key rejects syd4's IP
  (laptop-era IP access-control list). Founder one-time fix, either: add
  66.226.147.123 to the API key's Access Control (my.vultr.com → Account → API)
  — preferred, the agent then manages Vultr from the cockpit — or add the rule
  by hand (Firewall group `swordfish-syd3`: TCP 443, source 66.226.147.123/32).
  When it lands: agent verifies `ssh syd3`, pushes the tmux/motd fixes there,
  and clears the checklist follow-up.
- **B2 daily download cap hit 2026-07-11** (founder email): caused by two full
  restore drills in one day (3.1 GB snapshot each) — **nothing is lost or
  overwritten**; the cap only throttles further *downloads* until midnight UTC or
  a cap raise; nightly *uploads* (backups) are unaffected. Founder option: raise
  the daily download cap in B2 'Caps & Alerts' so a monthly drill never trips it.
  Agent option (proposed): exclude `~/migration/browsers/` (~large, static,
  still on the USB drive) from the syd4 backup source to shrink drill downloads.
- **tmux cosmetics per founder request:** black background + dark status bar,
  live on syd4 + pinned in both cloud-inits (with the mouse-off layer).
- **Portfolio workstation wiring COMPLETE (founder-directed, ~03:50):** Project 1's
  and Project 2's repos cloned to `~/work/<their-dir-names>` (fresh clones are
  content-identical — their own records show zero unpushed commits) and the vault
  agent attached at `~/vault`. All five project agents' memories are re-attached to
  their new paths (`~/.claude/projects` slug renames; verified each memory index
  present). No additional logins needed — claude + gh auth are per-box. Each
  project agent inventories its own gitignored secrets on first boot; their staging
  folders remain on the portable drives (founder scp's while a drive is in the
  Mac). Swordfish did NOT touch their code — workstation provisioning only.
- **Rotation list grew:** sourcing the PS-era `.env` (`KEY= value` spacing)
  echoed several secret values into this session's box-local transcript
  (encrypted-backup exposure only). Include in the already-chartered
  post-proving rotation: VULTR, PORKBUN ×2, B2 ×2, DOKPLOY ×2, UPTIMEROBOT,
  GHCR_PULL_TOKEN, healthchecks URLs. Also normalize `.env` to `KEY=value`.

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
