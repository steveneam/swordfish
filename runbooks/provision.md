# Provision a VPS from zero — the end-to-end playbook

_The `provision` runbook (the one named in `runbooks/README.md`). Deterministic,
dependency-ordered path from **nothing** to a hardened, TLS-terminated,
container-ready, backed-up, monitored box operated by an AI agent with human
approval gates. Distilled from building syd1→syd4 (2026-07-07 → 2026-07-16,
201 commits). Every step is either executable by an agent/CI or explicitly
marked as a human touch._

**Legend:** 🧑 = human-required (account, payment, approval, physical device) ·
🤖 = agent/CI-executable · ⛔ = hard gate, never auto-run.

**Reuse outside this repo:** clone `provisioning/` + `compose/` +
`.github/workflows/` + this file. Provider-specific surface is one directory
per provider (`vultr/`, `binarylane/`, `porkbun/`, `b2/`) — swapping a
provider = writing its directory, nothing else moves. Skip the
swordfish-specific parts (anonymity grep guard, Telegram relay) unless wanted.

---

## Phase 0 — Decisions and accounts (the only phase that is mostly 🧑)

1. 🧑 **Create accounts** (agent can pre-write every form value; human types
   payment details): VPS provider with an API + cloud-init support (Vultr and
   BinaryLane are implemented here), DNS registrar with an API (Porkbun),
   GitHub (repo + Actions + GHCR), off-site backup storage (Backblaze B2),
   alerting endpoints (ntfy.sh topic, healthchecks.io, UptimeRobot).
2. 🧑 **Mint API tokens** for provider/registrar/B2 and hand them to the agent
   via an untracked secret store (`.env*`, `inventory/secrets/` — gitignored).
   Never in tracked files. Watch for CR/LF contamination in copy-pasted
   secrets — strip with `tr -d '\r\n'` or APIs 400 like password drift.
3. 🤖 **Probe the operator's network reality** before designing access
   (`scripts/doctor.ps1` pattern): is outbound 22 blocked? Is 443 clean? This
   decides the access architecture. Ours: **CI-as-hands, 443-as-eyes** —
   GitHub Actions runners execute box commands; the human operates only
   provider UIs over HTTPS; raw SSH is phone-hotspot break-glass.
4. 🧑+🤖 **Write the charter before any code** (`CHARTER.md` pattern): pick
   region/tier from *live* pricing (never memory), pin the decisions in a
   table, define the approval gates. Adopt the invariants up front:
   **backups-before-workloads · every spend/destroy is a 🧑 gate · no local
   Docker if the workstation is locked down · 443 is the reliable channel ·
   stateful/compliance data planes stay managed**.

## Phase 1 — DNS (🤖, idempotent)

5. 🤖 A-records for the box fqdn + service subdomains (`deploy.`, `status.`,
   `metrics.`, …): `provisioning/porkbun/set-a-record.ps1` (idempotent
   upsert). DNS first — TLS issuance in Phase 4 needs it resolving.

## Phase 2 — Box creation, hardened at first boot

6. 🤖 **Author the cloud-init user-data** from `provisioning/cloud-init/`
   (adapt `syd2.yaml`). Non-negotiables baked in so the box is hardened
   *before it is first reachable*:
   - Ubuntu **24.04 LTS** pinned (Docker apt suite + fail2ban systemd backend
     assume it; providers default to newer images — select explicitly).
   - SSH keys land **before** sshd hardening; `ufw allow 22` lands **before**
     `ufw enable` — the two classic self-lockout gates resolved in code.
   - Two authorized keys: human break-glass + CI runner (the CI-as-hands key).
   - `ssh_pwauth: false`, sshd drop-in `00-`prefixed (first-value-wins beats
     provider defaults), timezone pinned `Etc/UTC` (providers disagree).
   - Host layer (daemon.json, swap, unattended-upgrades) mirrored from
     `provisioning/host/phase2-host.sh` so a rebuild lands converged at boot.
7. 🧑⛔ **SPEND GATE — create the box.** Scripted path:
   `provisioning/vultr/create-box.ps1` / `binarylane/create-box.ps1` (dry-run
   by default; the `-Approve` flag IS the gate, typed by the human). First
   box on a brand-new provider (no API token yet): the purchase form, with
   the cloud-init pasted in — pre-stage a **step-card** so the human only
   selects/pastes/pays (`provisioning/binarylane/syd2-purchase-step-card.md`
   is the template; never make the human hand-create anything an agent can
   pre-write).
8. 🤖 **Provider firewall** (defense outside the box): allow 22 + 80/443
   only (`vultr/firewall-group.ps1`, `binarylane/set-firewall.ps1`).
9. 🤖 **Verify, don't trust:** run `provisioning/checks/assert-hardening.sh`
   via the `hardening-smoke.yml` workflow. Never pipe a verdict through
   grep/head in a checked chain — capture output, then grep (pipes hide
   failures under `&&` and false-fail expected-failure checks).

## Phase 3 — Host layer converge (🤖)

10. 🤖 `host-apply.yml` → `provisioning/host/phase2-host.sh`: Docker + pinned
    daemon.json, swap guard, unattended-upgrades reboot window, fail2ban.
    Idempotent — re-running on a healthy box is a no-op, and **that re-run is
    the rebuild proof** (boxes are never destroyed to prove rebuildability).
11. 🤖 Login alerting: `alerts-apply.yml` → `setup-login-alerts.sh`. Every
    alert carries expected/unexpected inline (🔁🏠🤖⚠️) so the human can
    triage on a phone at a glance.

## Phase 4 — Edge + control plane

12. 🤖 `edge-apply.yml` → `provisioning/host/phase3-edge.sh` + `compose/edge/`:
    Traefik v3 owns 80/443 (TLS via Let's Encrypt), docker-socket-proxy (no
    raw socket exposure), **version-pinned Dokploy** control plane behind TLS
    at `deploy.<domain>`. Its port 3000 is never published; the UI is only
    reachable through the TLS route. Rules and break-glass: `runbooks/edge.md`.
13. 🧑 **First login to the control plane — create the admin account.** (The
    one unavoidable UI touch.)
14. 🤖 **Immediately mint the agent's API credential** — *API channel before
    any UI changes*. The agent credential is the recovery path; it must exist
    before the human changes anything clickable.

## Phase 5 — Backups BEFORE workloads (⛔ invariant)

15. 🤖 `provisioning/b2/create-backup-bucket.ps1` — per-box bucket +
    bucket-scoped key (blast radius = one box).
16. 🤖 `backups-apply.yml` → `phase7-backups.sh`: resticprofile nightly set +
    `pre-backup.d/` dump hooks (control-plane postgres, app SQLite/pg dumps —
    dump-level, not raw-volume). healthchecks.io is the dead-man witness
    (`verify-deadman.yml` proves the witness itself works).
17. 🤖 **Tested restore, not just backup:** `backup-restore-drill.yml` does a
    FUNCTIONAL restore (a canary row must read back from a restored DB).
    Scheduled monthly — and that monthly drill doubles as the
    documentation-rot pass: every documented command gets executed verbatim.
18. ⛔ **No workload lands on the box until the restore drill is green.**

## Phase 6 — Monitoring + alerting

19. 🤖 Uptime Kuma (`status.`) + Beszel metrics (`metrics.`) from tracked
    compose files; in-app config converges via **idempotent bootstrap
    scripts**, never UI clicking (`provisioning/kuma/bootstrap.py`,
    `beszel/bootstrap.py`) — the scripted channel survives rebuilds.
20. 🧑 **Subscribe the phone** to the ntfy topic, then verify one live
    DOWN→UP alert end-to-end (we proved it by watching a real deploy).
21. 🤖 Second off-infra witness: UptimeRobot (`uptimerobot/bootstrap.py`).
22. 🤖 Rate-limit **public** routers only — the control plane / recovery path
    is deliberately exempt: an attacker tripping a limit must never lock the
    operator out of the fix.

## Phase 7 — Workloads and tenants (🤖)

23. Change protocol: edit tracked compose → API update → deploy. **Never edit
    in the control-plane UI** — the repo copy wins at the next converge.
24. Tenant pattern: shared postgres service that **never publishes a port**
    (`dokploy/tenant-pg.sh`), per-tenant role+DB with both-ways isolation
    verification (`tenant-db.sh` → `tenant-db-apply.yml`), **deploy-only**
    API credentials for tenant CI (`tenant-credential.sh` — read back after
    assigning; the API 200s silently on unknown ids).
25. The accumulated control-plane API landmine list (a dozen hard-won ones):
    `runbooks/dogfood.md`. Read it before touching the Dokploy API.

## Phase 8 — Operate and ratchet

26. Rebuild path (memorize): **cloud-init → host-apply → edge-apply →
    backups-apply → smoke.**
27. Every command that worked on a live box is captured into `provisioning/`
    **in the same session** — this folder is the product.
28. Leave each lesson as high up the ratchet ladder as it goes: CI check >
    idempotent script > tracked config > runbook > memory. Tag it invariant
    (never loosened) or opinion (revisable).
29. If AI agents run *on* the box: their long-lived processes get their own
    systemd unit (`agent-tmux.service` pattern). A process spawned from a
    web-IDE terminal dies with that IDE's cgroup on service restart —
    PPID=1 does not mean escaped (learned 2026-07-16, cost us every agent).

## The human's complete touch list

Everything not listed here is agent/CI-executable:

1. Create accounts + type payment details (Phase 0).
2. Mint/paste API tokens into the untracked secret store (Phase 0).
3. Approve the charter and its gates (Phase 0).
4. ⛔ Approve every spend: box purchase/resize, block storage (Phase 2+).
5. Create the control-plane admin account at first login (Phase 4).
6. Subscribe the phone to the alert topic (Phase 6).
7. ⛔ Approve every destroy/irreversible step, forever (all phases).

## Transferable lessons (one line each, enforced at the link)

- **Backups before workloads; tested restore before backups count.**
  (`backup-restore-drill.yml`)
- **Charter before code** — pinned decisions + gates prevent re-litigating
  under pressure. (`CHARTER.md`)
- **Idempotent converge = rebuild proof**; never destroy to prove it.
  (`provisioning/README.md`)
- **CI-as-hands beats fighting a locked-down network** — design access around
  measured reality, not assumptions. (`.github/workflows/*-apply.yml`)
- **Pre-stage every human step** — the human pastes/clicks/pays, nothing
  more. (step-cards in `provisioning/*/`)
- **API channel before UI changes** — mint the agent credential first; it is
  the recovery path. (Phase 4)
- **Hardening rides first boot**, or the box has a vulnerable childhood.
  (`provisioning/cloud-init/`)
- **Verdicts: capture then grep** — piping verdict commands hides failures.
  (`provisioning/checks/`)
- **Delivery-green ≠ content-true** — read back what you wrote (API 200s lie;
  assignPermissions answers 200 for unknown ids). (`runbooks/dogfood.md`)
- **The recovery path is never rate-limited, never firewalled-by-default,
  never behind the thing it recovers.** (Phase 6; `runbooks/edge.md`)
- **Version-pin the control plane; upgrade = re-derive, converge, assert.**
  (`runbooks/edge.md`)
- **Own your agents' runtime seam** — dedicated unit for anything that must
  survive a restart of what spawned it. (Phase 8)
