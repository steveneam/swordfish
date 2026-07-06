# CHARTER — Swordfish build charter

_Approved by the founder: 2026-07-07 01:05 +10:00 (Prompt-1 orient + interview session)._
_Plan of record. One bucket at a time: plan → build → STOP at the checkpoint for founder review._
_Foundations are ratified by Swordfish ADR 0001 (vault: `Swordfish/Wiki/decisions/0001-…`) — **binding, do not re-open**._

## Mission

Swordfish is the portfolio's infrastructure/DevOps ops engine — it provisions, hardens, and
operates self-managed VPS boxes (DNS · TLS · reverse proxy · containers · auto-deploy · firewall ·
backups · monitoring) so an AI agent does the ops and the founder approves. North star:
`swordfish provision <box>` → a hardened, TLS-terminated, container-ready box with off-box
backups + uptime monitoring, live in under an hour from one approved command.

## Binding foundations (ADR 0001 — ratified 2026-07-06, not re-openable here)

1. **Dokploy** is the control plane (Apache-2.0, official MCP + CLI). The Stage-1 MCP-driven
   deploy from Claude Code IS the AI-operability test. Swap paths (Coolify / raw compose)
   stay documented, not pending.
2. The dogfood box is **Vultr Sydney** and **graduates** into the Stage-2 shared box —
   harden to production standard from day one; rebuild-proof = idempotent script re-runs.
3. **Project 2** targets the VPS shared box, pre-empting its planned managed-cloud stack.
4. **Project 1's** ≥50 GB reference-data disk lands via the Stage-3 VPS box; the PaaS disk
   tier is never purchased; its managed data plane stays put.
5. Executable home = this repo. The vault's Swordfish area is research/planning + mirror.

## Constraints in force (invariant ratchets — never loosened)

No local Docker (CI + VPS only) · 443 is the reliable channel · backups before workloads ·
keep-managed boundary (clinical/stateful data planes stay managed) · separation of duties
(Swordfish provisions + hands off; Projects 1/2 connect their own apps, founder-directed) ·
zero guarded tokens in tracked files (grep guard before every commit) · every spend or
irreversible step is a founder Approval Gate · founder is the sole author (no AI attribution).

## Pinned decisions (founder interview, 2026-07-07)

| # | Item | Decision |
|---|---|---|
| 1 | Box tier | Vultr Sydney `vhf-1c-2gb` — $12/mo, 1 vCPU / 2 GB / 64 GB NVMe (live-priced 2026-07-07; account holds $250 credit) |
| 2 | SSH channel | **CI-as-hands, 443-as-eyes.** sshd stays on 22 (outbound 22 confirmed BLOCKED from the founder's network; 443 open). GitHub Actions runners execute box commands; laptop operates via Vultr API / Dokploy UI+MCP / provider HTTPS console; phone hotspot = break-glass raw SSH. sslh-on-443 = documented upgrade only; the playbook's sshd-on-443 clause is explicitly NOT implemented in v1 (Traefik owns 443 from Phase 3) |
| 3 | DNS wiring | Porkbun A-records direct to box IP (TLS-ALPN unchanged). Cloudflare = documented upgrade path when a public workload earns DDoS protection (note: orange-cloud breaks TLS-ALPN → would need DNS-01) |
| 4 | Hostnames | Apex = **swordfish.cfd** (renewal $15.96/yr — anchor on renewal). Boxes = region+ordinal (`syd1.swordfish.cfd`); services = flat functional names (`deploy.` = Dokploy, `status.` = Uptime Kuma, `metrics.` = Beszel). Hostnames are public via CT logs → guarded-token rule applies to DNS too |
| 5 | Backups | Nightly restic → B2, encrypted; retention 7 daily / 4 weekly / 6 monthly; **monthly restore drill = the AGENTS.md rule-8 monthly pass**; weekly scripted CI restore drill = named Stage-2 upgrade (opinion ratchet) |
| 6 | B2 layout | Per-box bucket (`swordfish-syd1-backups`) + bucket-scoped application key (blast-radius isolation); account region **US West** (chosen at signup — B2 has no APAC region; off-region backup geometry accepted); ~30-day file versioning as the oops/ransomware guard |
| 7 | Secrets v1 | Compose secret-files on-box + gitignored `.env` / `inventory/secrets/` laptop-side. **Graduation trigger: Infisical deploys when box #2 goes live (Stage 3/Bucket 6).** sops+age = documented alternative |
| 8 | Alerts | ntfy push to the founder's phone (random topic on ntfy.sh; self-host = later option) + UptimeRobot free email as the independent off-infra witness |
| 9 | Budget | **$30/mo gross ceiling for Stages 1–2** (covers the documented resize path). Per-event Approval Gates unchanged; breaching the ceiling = stop and re-charter |
| 10 | Dogfood workload | Swordfish's own monitoring stack (Uptime Kuma + Beszel + a hello/status container) deployed **through CI + the Dokploy MCP from Claude Code** — this is the AI-operability test |

**Stage-0 facts on record (2026-07-07):** Vultr API token validated (lives in gitignored `.env`) ·
SSH keypair `~/.ssh/id_ed25519` generated (neutral comment `swordfish-ops`) + public key uploaded
to the Vultr account · `swordfish.cfd` registered (Porkbun, auto-renew on, propagating — NXDOMAIN
at approval time, re-probe before Phase 2) · Porkbun API Access still OFF (optional flip in
Bucket 0) · `scripts/doctor.ps1` has a PS-5.1 encoding parse bug (fix = Bucket 0).

## Buckets (dependency-ordered; mapped to vps-build-plan Stages 0→5)

> Discipline: build ONE bucket, verify, STOP at the checkpoint for founder review. Buckets 0–4
> are tightly specified; 5–8 stay coarse by design and are refined at their checkpoints.

### Bucket 0 — Stage-0 close-out: tooling ready, accounts complete *(no spend)*
- Fix `scripts/doctor.ps1` (encoding parse error under Windows PowerShell 5.1); extend probes:
  outbound-22 check, Porkbun API key presence, B2 key presence.
- **[founder]** Open Backblaze B2 account (**US West**) + application key → `.env`.
- **[founder, optional]** Flip Porkbun API Access on + key → `.env` (enables scripted DNS).
- Record pinned decisions + box plan into `inventory/` (fleet doc, no secrets).
- ✅ Verify: doctor all-green under PS 5.1 + pwsh 7; grep guard green; CI green.
- **CHECKPOINT.**

### Bucket 1 — Stage 1a: provision + harden (playbook Phases 0–2) *(⛔ Approval Gate: $12/mo box purchase)*
- Author cloud-init: `deploy` user + key, key-only SSH (no root, no password), ufw 22/80/443,
  unattended-upgrades, fail2ban, Docker + compose plugin.
- Box-create script via Vultr API (`vhf-1c-2gb`, `syd`, cloud-init user-data, `swordfish-ops` key).
- A-record `syd1.swordfish.cfd` → box IP (Porkbun API or UI).
- GHA smoke workflow — CI-as-hands proof: runner SSHes in, asserts hardening
  (password login refused, root refused, ufw active, unattended-upgrades on).
- Everything captured in `provisioning/`; box row in `inventory/boxes.md`.
- ✅ Verify: CI smoke green; hardening assertions pass; idempotent re-run clean.
- **CHECKPOINT.**

### Bucket 2 — Stage 1b: edge + control plane (Phases 3+) *(⛔ Gate: real DNS + TLS issuance)*
- Traefik v3 + tecnativa/docker-socket-proxy (publish no app ports; resolves the vault's
  Dokploy/socket-proxy compat gap on live hardware).
- Dokploy installed, **version-pinned**, behind TLS at `deploy.swordfish.cfd`.
- ✅ Verify: green-lock UI in the founder's browser; Dokploy MCP reachable from Claude Code;
  RAM headroom recorded (2 GB tier watch-item).
- **CHECKPOINT.**

### Bucket 3 — Stage 1c: backups BEFORE workloads (Phase 7) *(invariant)*
- Create `swordfish-syd1-backups` (US West) + bucket-scoped key; ~30-day versioning.
- restic nightly systemd timer; retention 7d/4w/6m; prune policy.
- **Execute a real restore drill** into a scratch dir/container; record RTO/RPO in `runbooks/`;
  monthly-pass cadence starts (this drill IS the monthly documented-command pass).
- ✅ Verify: restored data matches source; timer fires on schedule.
- **CHECKPOINT.**

### Bucket 4 — Stage 1d: dogfood deploy + monitoring (Phases 4/5/8) — the AI-operability test
- Hello/status container built in CI → GHCR, digest-pinned, image bar enforced
  (multi-stage, minimal base, non-root, HEALTHCHECK).
- Deploy hello + Uptime Kuma + Beszel **through the Dokploy MCP from Claude Code**;
  `status.` + `metrics.` live behind TLS.
- Wire ntfy push + UptimeRobot external check; test-fire an alert to the phone.
- ✅ Verify: playbook definition-of-done checklist all-✓ → **Stage 1 complete; box graduates.**
- **CHECKPOINT** (+ Dokploy-MCP verdict recorded: keep or trigger swap path).

### Bucket 5 — Stage 2: graduation + Project 2 handoff *(⛔ Gate: resize only, within the $30 ceiling)*
- Headroom check → resize if needed. Handoff pack: control-plane access + connection details.
- **Project 2 connects itself** (founder-directed) — Swordfish never touches the app side.
- Backups extended over Project 2 volumes; weekly scripted CI restore drill lands (the
  Stage-2 upgrade). **CHECKPOINT.**

### Bucket 6 — Stage 3: Project 1 box + data disk *(⛔ Gate: production box + ≥50 GB block storage spend)*
- Second box (bigger RAM), residency-matched region + block storage volume.
- **Box-#2 triggers fire:** hardening graduates to Ansible + dev-sec roles; **Infisical deploys**
  (secrets graduation per pinned decision 7).
- Harden → control plane → backups → handoff. Project 1 materializes its corpus + connects to
  its retained managed plane itself (founder-directed). **CHECKPOINT.**

### Bucket 7 — Stage 4: Project 3 render offload *(⛔ Gate: bandwidth box spend, provider per vault matrix)*
- High-egress box; render worker pulls job specs from the managed plane, pushes artifacts to
  object storage; no long-lived state. **CHECKPOINT.**

### Bucket 8 — Stage 5: steady state / completion
- OpenTofu graduation (box #3+); fleet monitoring consolidated; old PaaS tiers retired and the
  net saving recorded (closes the cost-ledger gap); North-Star `swordfish provision <box>`
  assembled from the accumulated provisioning scripts. **Done-when** per the vps-build-plan
  Stage-5 checklist.

## Change control

Buckets are re-scoped only at checkpoints (opinion ratchets — freely revised there).
The Constraints-in-force block and ADR 0001 are invariant. A budget-ceiling breach, a
guard failure, or a keep-managed-boundary question stops the build for the founder.
