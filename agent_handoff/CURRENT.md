# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 01:38 +10:00_

## State

**Bucket 0 COMPLETE — at its checkpoint awaiting founder review.** Charter approved earlier this
session (`CHARTER.md`, commit 9428caf). Bucket-0 delivery (commit a33a197, CI green):
`scripts/doctor.ps1` fixed (PS-5.1 ASCII/encoding parse bug) + hardened (key-presence now
requires non-empty values; fast 3s TCP probes; new checks: outbound-22 state, `swordfish.cfd`
resolution) — **11/11 PASS** on the founder's laptop; `inventory/decisions.md` operational
digest created (links to CHARTER.md, no duplication, no secrets); planned `syd1.swordfish.cfd`
row added to `inventory/boxes.md`.

**Stage-0 accounts: ALL validated live.** Vultr (token OK, $250 credit, pubkey `swordfish-ops`
uploaded) · Porkbun API (ping + per-domain DNS read OK) · B2 (auth OK, us-west-004, admin key
has writeBuckets/writeKeys) · `swordfish.cfd` fully propagated (resolves even on the corporate
resolver). Outbound 22 confirmed blocked → CI-as-hands model. pwsh 7 not installed on the
laptop (PS 5.1 authoritative locally; CI runners have pwsh). No box, no spend beyond the domain.

## Next

1. **Founder reviews the Bucket-0 checkpoint** → on go, **Bucket 1** (Stage 1a): cloud-init
   (deploy user, key-only SSH, ufw, unattended-upgrades, fail2ban, Docker) + Vultr box-create
   script + A-record + GHA hardening-smoke workflow. **Ends at the ⛔ $12/mo box-purchase
   Approval Gate — do NOT create the instance without the founder's explicit approve.**
2. Vault side: founder pastes the vault-sync block (chat, 01:33 stamp) into the wiki-agent
   session — CHARTER.md landed → sync-operational-mirror + 5 filed deltas.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 blocked, probed) · zero
guarded tokens in tracked files — extends to public names (CT logs, bucket names) · backups
before workloads · Projects are 1/2/3 only · every spend is an Approval Gate · founder is the
sole author (no AI attribution).
