# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 01:05 +10:00_

## State

**CHARTER.md approved + written** (Prompt-1 session: orient → 10-item founder interview → charter).
All interview items pinned — see the table in `CHARTER.md`. Key facts: box = Vultr Sydney
`vhf-1c-2gb` $12/mo (account validated, $250 credit, SSH pubkey `swordfish-ops` uploaded);
domain = `swordfish.cfd` (bought, DNS still propagating — NXDOMAIN at wrap); outbound port 22
confirmed BLOCKED from founder's network → CI-as-hands/443-as-eyes model pinned; B2 = per-box
bucket US West (account NOT yet opened); secrets = compose files v1, Infisical at box #2;
alerts = ntfy + UptimeRobot; budget ceiling Stages 1–2 = $30/mo; dogfood workload = Swordfish's
own monitoring stack via CI + Dokploy MCP. Known bug: `scripts/doctor.ps1` fails to parse under
Windows PowerShell 5.1 (encoding) — fix is Bucket-0 scope. No box purchased; no spend beyond the
domain; Vultr token + future B2 keys live in gitignored `.env`.

## Next

1. **Bucket 0** (Stage-0 close-out) on founder go: fix doctor.ps1 + extend probes; record pinned
   decisions into `inventory/`; verify all-green.
2. **[founder]** Open Backblaze B2 account — region **US West** — app key into `.env`
   (placeholders already there). Optional: flip Porkbun API Access on + key into `.env`.
3. Bucket 1 after Bucket-0 checkpoint: provisioning package. **Box purchase = Approval Gate —
   do NOT create the instance until the founder clears it.**

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (port 22 confirmed blocked) ·
zero guarded tokens in tracked files (guard before every commit; applies to hostnames/buckets
too — they're public) · backups before workloads · Projects are 1/2/3 only · every spend is an
Approval Gate · founder is the sole author (no AI attribution).
