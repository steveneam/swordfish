# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-08 01:20 +10:00 (Bucket-4 CHECKPOINT CLOSED — Stage 1 graduated; Bucket 5 opens next session)_

## State

**Bucket-4 checkpoint held with the founder and recorded in `CHARTER.md`
(“Bucket-4 checkpoint record”). Stage 1 COMPLETE, syd1 graduated. All
verification is green and live:**

- **Dokploy-MCP verdict: KEEP** (founder-ratified; quirks in `runbooks/dogfood.md`).
- **Dead-man NATURAL fire verified tonight** — 15:00 UTC timer ran (exit 0),
  BOTH legs receiver-acknowledged (healthchecks.io + Kuma push), proven by the
  NEW ratchet `.github/workflows/verify-deadman.yml` (run 28877105328).
  The manual “confirm legs each morning” check is now a dispatchable CI job
  (default window: 26 hours).
- Fresh graduation-stamp posture run: hardening-smoke green (run 28872534047);
  zizmor + ci-guard green on the checkpoint commits (b989f49, 49e1ac2).

## Founder decisions on record (all in CHARTER.md checkpoint record)

1. **Bucket-5 fork → graduate-by-migrating to BinaryLane** Standard
   4 vCPU / 8 GB / 100 GB NVMe / 4 TB, AUD $39.20/mo ≈ US$26 (confirmed
   available on the founder's new BinaryLane account 2026-07-08; CPU-Optimised
   ≥4-thread + 16 GB HDD plans out of stock — Bucket-7 datapoint).
   **Parallel-run:** Vultr box stays until syd2 passes full verification;
   then instance destroyed, account + credit retained as fallback.
2. **Spend gate satisfied in principle** (founder walked the purchase flow);
   BinaryLane's wizard requires the purchase to finish account activation →
   API token only exists post-purchase. Therefore syd2 is created **via the UI
   form WITH our cloud-init user-data pasted in** (hardened at first boot),
   then everything after is scripted.
3. **Hermes pilot: GO** (E0→E1→E2 ladder; LLM budget gates separately).
   **Pi coding agent approved** (pi.dev, MIT) — candidate ops agent harness,
   scoped at Bucket 5.
4. **Project 3 pull-forward:** its offload workload becomes an early tenant of
   syd2 (dogfood-class — Swordfish may wire it). Keep-managed boundary
   unchanged. Real name = guarded token; never in tracked files.
5. **Integration surface ruling:** projects wire in via Dokploy REST API +
   MCP + CLI at `deploy.swordfish.cfd` with per-project scoped creds at
   handoff; no custom Swordfish API layer.

## Next — Bucket-5 opener (single founder-touch, then scripted)

1. Agent: adapt `provisioning/cloud-init/syd1.yaml` → `syd2` user-data
   (hostname; **Ubuntu 24.04 LTS ONLY** — cloud-init pins Docker apt to
   `noble`; check swap: Vultr image shipped /swapfile, BinaryLane may not) +
   step-card for the founder.
2. Founder: complete BinaryLane purchase per step-card (Sydney · Ubuntu
   24.04 LTS · Standard 8 GB · hostname `syd2.swordfish.cfd` · user-data
   pasted) → create API token → `.env` as `BINARYLANE_API_TOKEN`.
3. Agent: `provisioning/binarylane/` adapter (amendment-6 seam), A-record
   `syd2`, hardening-smoke vs syd2, then edge → backups → dogfood replay
   (the portability drill), verify-deadman on syd2, DNS cutover + soak →
   only then destroy the Vultr instance.

## Standing

- Traefik 3.7.6 Renovate PR when it opens: edge pin bump = edge-apply protocol.
- verify-deadman can replace the morning eyeball: dispatch with default
  26-hour window any time; assertions cover backup exit + both ping legs.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel · zero guarded
tokens in tracked files (extends to DNS/CT logs) · backups before workloads ·
every spend is an Approval Gate (BinaryLane purchase pre-approved at the
Bucket-4 checkpoint, re-confirmed by the founder executing it) · founder is
the sole author.

_All work is committed and pushed — it is safe to clear this session._
