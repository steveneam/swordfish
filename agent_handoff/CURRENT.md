# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-08 02:16 +10:00 (Thalon unmasked; Bucket-5 opener built — founder purchase is the next touch)_

## State

**Two commits this session, both pushed, guard green on each:**

1. **Project 3 unmasked = Thalon** (founder call 2026-07-08, relayed tenant note
   from `E:\thalon\.context\notes\swordfish-tenant-note-2026-07-08.md`).
   Guard token C removed from `scripts/ci-grep-guard.ps1` — **tokens A/B
   (Projects 1/2) stay guarded**. AGENTS.md + CI-GUARD.md now say two guarded
   names; `thalon.org` DNS co-location on syd2 founder-accepted (CT-log linkage
   acknowledged). Full record: **CHARTER.md "Bucket-4 checkpoint addendum 2"**
   — tenant sequencing (Thalon web app = first syd2 tenant, render offload
   second), the handoff pack owed to Thalon at syd2 verification, the **PGlite
   app-level export hook** joint design item (pre-backup.d calls it before the
   15:00 UTC snapshot — Thalon owes the proposal), and syd2 sizing datapoints.
2. **Bucket-5 opener:** `provisioning/cloud-init/syd2.yaml` (functional payload
   byte-identical to syd1 — verified by diff; Ubuntu 24.04-ONLY + swap
   assumption documented) + `provisioning/binarylane/syd2-purchase-step-card.md`
   (five form invariants: SYD · Ubuntu 24.04 LTS · Standard 4 vCPU/8 GB
   AUD 39.20 · `syd2.swordfish.cfd` · user-data pasted; then API token →
   `.env` as `BINARYLANE_API_TOKEN`). CHARTER gate-evidence corrected:
   form-create first (token only exists post-purchase), adapter owns
   everything after.

Note: editing AGENTS.md breaks the CLAUDE.md hardlink (Edit replaces the file)
— it was re-created this session; re-check `fsutil hardlink list` after any
AGENTS.md edit.

## Next — founder touch, then scripted

1. **[founder]** Execute `provisioning/binarylane/syd2-purchase-step-card.md`
   (purchase + paste user-data + API token into `.env`), then say:
   "syd2 purchased, IP = x.x.x.x, token in .env".
2. Agent: `provisioning/binarylane/` adapter (amendment-6 seam) → A-record
   `syd2` → hardening-smoke vs syd2 (verify the swap assumption, record in
   `inventory/boxes.md`) → edge → backups + tested restore → dogfood replay
   (the portability drill) → verify-deadman on syd2 → DNS cutover + soak →
   only then destroy the Vultr instance (account + credit stay as fallback).
3. Bucket-5 also carries: Thalon handoff pack at verification (Dokploy project
   + scoped cred, GHCR pull slot for `ghcr.io/steveneam/thalon-web`,
   `thalon.org` + `www` domains with `swordfish-ratelimit`, `THALON_DATA_DIR`
   volume into the restic set) · PGlite export-hook wiring · Bifrost dogfood ·
   Hermes E0 + Pi scoping.

## Standing

- Traefik 3.7.6 Renovate PR when it opens: edge pin bump = edge-apply protocol.
- verify-deadman replaces the morning eyeball (dispatch, 26-hour window).

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel · zero guarded
tokens (now A/B only — Thalon is unmasked) in tracked files · backups before
workloads · every spend is an Approval Gate (BinaryLane purchase pre-approved,
re-confirmed by the founder executing the step-card) · founder is the sole
author.

_All work is committed and pushed — it is safe to clear this session._
