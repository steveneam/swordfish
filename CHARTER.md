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

### Bucket 1.5 — CI supply-chain hardening *(repo-only, no spend; added at Checkpoint 1)*
- SHA-pin every GitHub Action (full commit SHA, tag in comment); zizmor workflow-lint job in
  CI; default `permissions: read-all`; deploy-key jobs tightly scoped.
- Renovate (hosted app; AGPL — service-use only, on the licensing ledger) maintains action
  SHAs + image digests via PRs.
- Context: trivy-action compromise 2026-03 — the CI runner holds the box SSH key, so a
  compromised action is a box compromise. See `research/2026-07-07-vps-ops-research.md` §6.
- ✅ Verify: zizmor green in CI; zero non-SHA action refs; Renovate onboarding PR open.
- **CHECKPOINT** (light — may merge into the Bucket-2 review).

### Bucket 2 — Stage 1b: edge + control plane (Phases 3+) *(⛔ Gate: real DNS + TLS issuance)*
- Pre-steps (host layer, from the Checkpoint-1 research pass):
  Vultr firewall group (free) attached to syd1 allowing 22/80/443 only — the provider-side
  layer Docker can't bypass (scripted + idempotent in `provisioning/vultr/`);
  Docker `daemon.json` (json-file log caps + `live-restore`); unattended-upgrades
  **reboot window** (no Ubuntu Pro attach — personal-use terms judged grey); 1–2 GB swap.
- Traefik v3 + tecnativa/docker-socket-proxy (publish no app ports; resolves the vault's
  Dokploy/socket-proxy compat gap on live hardware). Proxy on its own internal network,
  `CONTAINERS=1` only, `no-new-privileges`; security-headers/HSTS + modern-TLS middleware
  as tracked config; JSON access logs.
- Dokploy installed, **version-pinned**, behind TLS at `deploy.swordfish.cfd`.
  Known 2026 failure mode: Dokploy *updates* can break/remove its managed Traefik — never
  upgrade before `/etc/dokploy` + Traefik config are in the restic set (Bucket 3).
- `assert-hardening.sh` extends: no `0.0.0.0` published ports besides Traefik 80/443;
  ssh-audit grade added to the smoke workflow.
- ✅ Verify: green-lock UI in the founder's browser; Dokploy MCP reachable from Claude Code;
  RAM headroom recorded (2 GB tier watch-item); extended assertions green.
- **CHECKPOINT.**

### Bucket 3 — Stage 1c: backups BEFORE workloads (Phase 7) *(invariant)*
- Create `swordfish-syd1-backups` (US West) + bucket-scoped key; ~30-day versioning.
- restic nightly via **resticprofile** (config-as-code: retention, hooks, pings, scheduling
  in one tracked YAML); retention 7d/4w/6m; prune policy; weekly
  `restic check --read-data-subset=10%`.
- **Dead-man's switch:** job pings on success only → Uptime Kuma push monitor (Bucket 4)
  + healthchecks.io free tier as the off-infra witness that fires even if the box dies.
- Pre-backup hooks for anything stateful later (dump before snapshot — file-level backup of
  a running DB volume is not consistent). `/etc/dokploy` + Traefik config in the set.
- **Execute a real restore drill** into a scratch dir/container; record RTO/RPO in `runbooks/`;
  monthly-pass cadence starts (this drill IS the monthly documented-command pass).
- ✅ Verify: restored data matches source; timer fires on schedule; dead-man alert test-fired.
- **CHECKPOINT.**

### Bucket 4 — Stage 1d: dogfood deploy + monitoring (Phases 4/5/8) — the AI-operability test
- Hello/status container built in CI → GHCR, digest-pinned, image bar enforced
  (multi-stage, minimal base, non-root, HEALTHCHECK).
- Deploy hello + Uptime Kuma + Beszel **through the Dokploy MCP from Claude Code**;
  `status.` + `metrics.` live behind TLS. (Kuma confirmed at Checkpoint 1 — its push monitor
  is the Bucket-3 dead-man switch; Gatus = documented config-as-code swap path.)
- Wire ntfy push + UptimeRobot external check; test-fire an alert to the phone.
- Image-update flow = Renovate PRs against digest-pinned compose (Watchtower is
  discontinued); Diun optional as notify-only drift alert.
- ✅ Verify: playbook definition-of-done checklist all-✓ → **Stage 1 complete; box graduates.**
- **CHECKPOINT** (+ Dokploy-MCP verdict recorded: keep or trigger swap path).

### Bucket 5 — Stage 2: graduation + Project 2 handoff *(⛔ Gate: box spend, within the $30 ceiling)*
- Headroom check → **box-path fork** (Checkpoint-2 amendment 2): resize-in-place vs
  graduate-by-migrating; either way gated. Handoff pack: control-plane access + connection
  details + parity notes (Next.js standalone/sharp/cache-volume, gateway base-URL seam,
  Postgres+RLS pattern — parity plan §9).
- Bifrost AI gateway lands as a dogfood service (Checkpoint-2 amendment 1).
- **Project 2 connects itself** (founder-directed) — Swordfish never touches the app side.
- Backups extended over Project 2 volumes; weekly scripted CI restore drill lands (the
  Stage-2 upgrade).
- Dogfood-roster option if headroom allows post-resize: **Hermes Agent pilot at tier E0/E1**
  (Checkpoint-1 amendment 6; research §11) — ⛔ its LLM API budget gates separately.
  **CHECKPOINT.**

### Bucket 6 — Stage 3: Project 1 box + data disk *(⛔ Gate: production box + ≥50 GB block storage spend)*
- Second box (bigger RAM), residency-matched region + block storage volume.
- **Box-#2 triggers fire:** hardening graduates to Ansible + dev-sec roles; **Infisical deploys**
  (secrets graduation per pinned decision 7); **CrowdSec replaces fail2ban** (fleet-shared
  bans + Traefik bouncer — added at Checkpoint 1).
- Forward-auth SSO in front of admin UIs adopts here (Checkpoint-2 amendment 4).
- Harden → control plane → backups → handoff. Project 1 materializes its corpus + connects to
  its retained managed plane itself (founder-directed). **CHECKPOINT.**

### Bucket 7 — Stage 4: Project 3 render offload *(⛔ Gate: bandwidth box spend, provider per vault matrix)*
- High-egress box; render worker pulls job specs from the managed plane, pushes artifacts to
  object storage; no long-lived state. **CHECKPOINT.**
- Analytics lane: pg_duckdb + Parquet-on-R2 (Checkpoint-2 amendment 5).
- Provider matrix must weigh (Checkpoint-1 research): **Hetzner EU** (20 TB included,
  ~€1/TB overage, 3–5× cheaper compute; latency-tolerant stateless fit — no AU region) and
  **Cloudflare R2** (zero egress) as the artifact store, decoupling artifacts from the
  render provider. B2 stays the backup target (write-heavy/restore-rarely economics).

### Bucket 8 — Stage 5: steady state / completion
- OpenTofu graduation (box #3+); fleet monitoring consolidated; old PaaS tiers retired and the
  net saving recorded (closes the cost-ledger gap); North-Star `swordfish provision <box>`
  assembled from the accumulated provisioning scripts. **Done-when** per the vps-build-plan
  Stage-5 checklist.

## Checkpoint-1 amendments (founder-approved 2026-07-07, research pass)

Full findings: `research/2026-07-07-vps-ops-research.md`. The five calls:

1. **Vultr firewall group** for syd1 (22/80/443 only) → Bucket-2 pre-step. Closes the
   Docker-bypasses-ufw gap from outside the OS; free; scripted + idempotent.
2. **No Ubuntu Pro attach** (personal-use terms judged grey) → unattended-upgrades reboot
   window instead; revisit if the fleet earns paid Pro.
3. **Bucket 1.5** (CI supply-chain hardening, repo-only) approved as a standalone mini-bucket.
4. **Uptime Kuma kept** (push monitor = backup dead-man switch); Gatus recorded as the
   config-as-code swap path.
5. **Tailscale-over-443 break-glass** = documented upgrade only; the corporate-laptop install
   probe stays founder-optional (IT-policy risk is the founder's call).
6. **Hermes Agent pilot documented** (research §11): steady-state ops value (cron briefings,
   alert triage, runbook one-liners over Telegram/443), NOT provisioning — that stays scripts.
   Graduated autonomy E0 eyes → E1 propose (command approval) → E2 constrained hands on
   dogfood workloads only; never spend-capable keys / socket / provisioning authority.
   Lands post-Bucket-5 resize via Dokploy; LLM budget = Approval Gate; go/no-go at the
   Bucket-4/5 checkpoint.

Standing approval noted: tools/integrations from the research shortlist may be installed as
their buckets arrive without a fresh per-tool gate — spend and irreversible-step gates unchanged.

## Checkpoint-2 amendments (founder-approved 2026-07-07, platform-parity research pass)

Full findings: `research/2026-07-07-platform-parity-plan.md` (PaaS→VPS parity map). The calls:

1. **AI gateway posture:** projects stay on Vercel AI Gateway (host-independent, zero-markup
   BYOK — decoupled from hosting) until self-hosted **Bifrost** (Apache-2.0, single Go binary)
   is deployed + drilled as a dogfood service in the Bucket-5 era; app-side swap = one
   base-URL env var. LiteLLM / Portkey Gateway = documented alternatives.
2. **Bucket-5 box-path fork stays open by design** (founder: decide when things are more
   built out): resize-in-place (Vultr 8 GB, US$40 — needs a ceiling amendment) vs
   graduate-by-migrating (BinaryLane SYD 4vCPU/8GB/100GB ≈US$26, inside the ceiling —
   doubles as the portability drill). Decide at the Bucket-4/5 checkpoint.
3. **Disk demand is portfolio-aggregate** (>100 GB combined across projects, no single
   driver): served per-workload — R2 for artifacts (zero egress), per-box block-storage/HDD
   volumes for reference data; never one giant disk. Confirms the multi-box trajectory.
4. **Forward-auth SSO: not before box #2** (agent ruling, founder-delegated). The Bucket-2
   lockout incident made control-plane reachability the precious invariant — an auth proxy
   in front of Dokploy adds a failure mode in front of the recovery path and must exempt
   API/MCP header-auth routes. Per-app auth + 2FA suffices while UIs are few; adopt at
   Bucket 6 with the fleet set (Ansible/Infisical/CrowdSec). Traefik rate-limit middleware
   on **public app routers** still lands Bucket 4 — never on the control-plane router.
5. **Analytics lane pinned:** pg_duckdb 1.0 (MIT) + Parquet-on-R2 is the Bucket-7 pattern
   for Project 3 offload (verify pg_ducklake license at adoption).
6. **Bucket-3 opportunistic add:** surface the `provisioning/<provider>/` adapter seam
   (file moves only — provider-specific surface is create-box / firewall / DNS).

## Bucket-4 checkpoint record (founder-reviewed 2026-07-08 00:05 +10:00)

Stage-1 definition-of-done accepted (62/62 posture, run 28859416115; operating detail in
`runbooks/dogfood.md`) — **Stage 1 complete, syd1 graduates** per the Bucket-4 line. The calls:

1. **Dokploy-MCP verdict: KEEP.** Every Bucket-4 operation (project/compose/app create, inline
   compose, env, domains + middleware, deploys, logs/containers, Traefik file reads) ran through
   the MCP from Claude Code — zero SSH, zero UI. Quirks documented in `runbooks/dogfood.md`;
   Coolify / raw-compose swap paths stay documented, not pending.
2. **Bucket-5 box-path fork resolved: graduate-by-migrating** (BinaryLane SYD 4 vCPU / 8 GB /
   100 GB ≈ US$26/mo, inside the $30 ceiling) — drivers: RAM ~71% idle on the 2 GB tier, and the
   founder wants Project 3's offload workload to start on the shared box with real headroom
   (more vCPU / RAM / disk). Doubles as the portability drill (Checkpoint-2 amendment 2 intent).
   **Parallel-run protocol (founder-set):** the Vultr box stays live until the BinaryLane box
   passes the full verification set (posture assertions green on the new box · backups + tested
   restore · monitors + both dead-man legs · DNS cutover + soak); only then is the Vultr
   *instance* destroyed. The Vultr *account* stays open (no instance = no charge; remaining
   credit keeps) as the fallback provider. ⛔ The BinaryLane purchase is the Bucket-5 Approval
   Gate; the bounded two-box overlap (≈US$38/mo gross, Vultr side credit-funded so cash stays
   ≈US$26) is pre-acknowledged here and re-confirmed at that gate.
3. **Hermes pilot: GO** (founder, this checkpoint) — per Checkpoint-1 amendment 6 ladder:
   E0 eyes → E1 propose → E2 constrained hands on dogfood workloads only; lands post-migration
   via Dokploy; its LLM API budget remains a separate Approval Gate.
4. **Project 3 pull-forward (re-scope):** Project 3's offload workload becomes an early tenant
   of the Stage-2 shared box once the migration verifies (sequencing pulled forward from
   Bucket 7; the dedicated high-egress box decision defers until the offload's real bandwidth
   profile is measured on the shared box). Keep-managed boundary unchanged — only offload
   compute / data-disk / bandwidth moves; the managed control plane stays put. Per AGENTS.md
   separation of duties, Project 3's offload is dogfood-class: Swordfish MAY do its hands-on
   wiring (unlike Projects 1/2, which connect themselves).
5. **Project-integration surface ruling:** projects wire in via the control plane's existing
   surfaces — Dokploy REST API + official MCP + CLI at `deploy.swordfish.cfd` — with
   per-project scoped credentials and service connection strings issued at handoff. No custom
   Swordfish API layer gets built (it would duplicate the control plane); the
   `swordfish provision <box>` CLI stays the Bucket-8 north star for box ops.
6. **Dead-man freshness is now executable:** `.github/workflows/verify-deadman.yml`
   (CI-as-hands, dispatch-only) asserts the nightly backup succeeded and BOTH witness pings
   were receiver-acknowledged inside a window — the standing "confirm both legs each morning"
   documentary check graduated to a dispatchable CI check.

## Change control

Buckets are re-scoped only at checkpoints (opinion ratchets — freely revised there).
The Constraints-in-force block and ADR 0001 are invariant. A budget-ceiling breach, a
guard failure, or a keep-managed-boundary question stops the build for the founder.
