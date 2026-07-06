# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 (research/planning session, post-Bucket-1)_

## State

**Bucket-1 checkpoint reviewed + charter amended.** This was a research/planning session
(no box changes). syd1 remains live + hardened + CI-verified (45.63.24.122,
`syd1.swordfish.cfd`), carrying NOTHING until Bucket-3 backups exist (invariant).

- **Research pass banked:** `research/2026-07-07-vps-ops-research.md` — 2026 best-practices
  sweep (host/Docker, edge, backups, monitoring, CI supply chain, secrets, IaC, providers,
  cloud layer). Headlines: stack choices all validated; one real gap = Docker bypasses ufw;
  2026 theme = CI supply-chain attacks (trivy-action compromise); Hetzner = no for syd1,
  yes for the Bucket-7 egress matrix; R2 = the artifact store, B2 stays backups.
  Addendum §11 (expanded on founder request — benefits pass): Hermes Agent's real value =
  steady-state ops (cron briefings, alert triage, runbook one-liners via Telegram/443), not
  provisioning (that stays scripts — the moat). Pilot documented as Checkpoint-1 amendment 6:
  graduated autonomy E0 eyes → E1 propose → E2 constrained hands, dogfood-only, never
  spend-capable keys/socket/provisioning; lands post-Bucket-5 resize; go/no-go at the
  Bucket-4/5 checkpoint; LLM budget gates separately.
- **Charter amended at the checkpoint** (founder-approved, see CHARTER.md
  "Checkpoint-1 amendments"): (1) Vultr firewall group = Bucket-2 pre-step; (2) no Ubuntu
  Pro — reboot window instead; (3) **new Bucket 1.5** (CI supply-chain: SHA-pin actions,
  zizmor, Renovate — repo-only); (4) Kuma kept, Gatus = swap path; (5) Tailscale break-glass
  = documented upgrade only. Standing approval: shortlist tools install as their buckets
  arrive; spend/irreversible gates unchanged.
- `inventory/decisions.md` gained the host/edge parameter block + backup dead-man/check
  parameters.

## Next

1. **Bucket 1.5 — CI supply-chain hardening (repo-only, no spend):** SHA-pin all actions in
   `.github/workflows/`, add zizmor lint job, default `permissions: read-all`, onboard
   Renovate (hosted app). Verify: zizmor green, zero non-SHA refs, Renovate PR open.
   Light checkpoint — may merge into the Bucket-2 review.
2. **Bucket 2 — edge + control plane:** pre-steps first (Vultr firewall group script,
   daemon.json, reboot window, swap), then Traefik v3 + socket-proxy (own network,
   CONTAINERS=1 only), Dokploy version-pinned at `deploy.swordfish.cfd`. Ends at the
   ⛔ real-DNS + TLS-issuance gate. Extended assertions: no 0.0.0.0 publishes beyond
   Traefik 80/443; ssh-audit in the smoke workflow.
3. Vault side: founder pastes the research-sync block (given at wrap) into the wiki-agent
   session, alongside the still-pending Bucket-1 sync block if not yet done.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 + 53 blocked, probed) ·
zero guarded tokens in tracked files — extends to public names (CT logs, bucket names) ·
backups before workloads (syd1 carries NOTHING until Bucket 3) · Projects are 1/2/3 only ·
every spend is an Approval Gate · founder is the sole author (no AI attribution).
