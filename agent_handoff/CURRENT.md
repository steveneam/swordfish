# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-08 02:48 +10:00 (syd2 LIVE + hardened; next leg = edge/control plane on syd2)_

## State

**syd2 is purchased, hardened, firewalled, DNS'd — the Phase 0–2 layer is green.**

- Founder executed the Bucket-5 purchase gate (form + pasted
  `provisioning/cloud-init/syd2.yaml`). Box: BinaryLane id 638535,
  `syd2.swordfish.cfd` = 103.249.236.41, ubuntu-24.04, std-4vcpu
  (4 vCPU / 8 GB / 100 GB), AUD 39.20/mo. `BINARYLANE_API_TOKEN` in `.env`
  (validated).
- **Hardened at first boot on the new provider unchanged**: smoke run
  28883030398 — every Phase 0–2 assertion green (29/62; the 33 FAILs are the
  not-yet-applied swarm/edge/backup/dogfood layers, converging next).
- **Swap datapoint recorded:** BinaryLane image ships NO swapfile → the
  cloud-init guard created the 2G `/swapfile` (Vultr had shipped 6.2G).
- **Adapter seam live** (`provisioning/binarylane/`): `create-box.ps1`
  (spend-gated, idempotent — no-op converge proven against the live box) ·
  `set-firewall.ps1` (advanced firewall accept tcp 22/80/443 + drop-all —
  applied, no-op re-run proven, SSH-still-green proof = smoke run 28883211204,
  same 29/62) · `syd2-purchase-step-card.md` (executed).
- A-record `syd2` → 103.249.236.41 (Porkbun script, CREATED).
- Earlier this session: **Thalon unmask** (token C removed; A/B guarded;
  CHARTER "Bucket-4 checkpoint addendum 2" holds the tenant note: handoff
  pack, PGlite export hook, sizing).

## Next — edge/control plane on syd2 (parallel-run aware)

1. ⚠ **Decision first: control-plane hostname during parallel-run.**
   `deploy.swordfish.cfd` still points at syd1 (live). Options: temp
   `deploy2.swordfish.cfd` A-record for syd2's Dokploy (extra CT-log name,
   neutral so fine) and rename/re-point at cutover, or install edge+Dokploy
   with TLS probe skipped until cutover. Same question hits `status.` /
   `metrics.` / `hello.` at dogfood replay. Pick at next session start.
2. Dispatch `host-apply` vs syd2 (should be ~no-op — cloud-init mirrored
   phase2-host.sh; proves the converge path works cross-provider).
3. `edge-apply` vs syd2 (Traefik + socket-proxy + Dokploy pinned install),
   then backups (`backups-apply`; NEW B2 bucket `swordfish-syd2-backups` +
   scoped key + restore test), then dogfood replay via Dokploy MCP (the
   portability drill), verify-deadman on syd2, DNS cutover + soak.
4. **Only after the full verification set passes: destroy the Vultr instance**
   (account + credit stay). Then the Thalon handoff pack (CHARTER addendum 2
   item 4) + PGlite export-hook wiring.

## Standing

- Traefik 3.7.6 Renovate PR when it opens: edge pin bump = edge-apply protocol.
- verify-deadman replaces the morning eyeball (dispatch, 26-hour window) —
  still pointed at syd1 until the backup layer moves.
- Editing AGENTS.md breaks the CLAUDE.md hardlink — recreate + verify with
  `fsutil hardlink list` after any AGENTS.md edit.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel · zero guarded
tokens (A/B only — Thalon unmasked) in tracked files · **backups before
workloads: no tenant on syd2 until restic + tested restore exist there** ·
every spend is an Approval Gate · founder is the sole author.

_All work is committed and pushed — it is safe to clear this session._
