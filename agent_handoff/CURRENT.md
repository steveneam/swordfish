# CURRENT — session handoff (one file, overwritten each wrap)

> ## ▶ BOOT: the founder types **`gogogo`** — that is the whole resume prompt.
>
> **Agent, on `gogogo` (or any greeting with no task): do this, unprompted.**
> He cannot copy text out of this terminal, so there is no prompt for him to
> paste — the prompt is this file. Read, in order, then act:
> 1. this whole file (State → Next → Protocol notes → Constraints)
> 2. `AGENTS.md` (the operating protocol) and your memory
> 3. `git log --oneline -8` and `git status` — trust the repo, not the stamp
>
> Then **state the top of Next in one sentence, say what you are starting, and
> start it.** Do not ask "shall I?" — the Next list IS the standing approval.
> Stop only at a founder gate (spend · destroy · anything named a founder
> decision below). If the box state and this file disagree, the box wins —
> say so, then fix the file.

_Stamped: 2026-07-14 09:14 UTC (19:14 AEST). Three closes this session:
**`!map` built + founder-live-tested** · **Postgres tenant bucket COMPLETE**
(tenant-pg on syd2, drilled functional restore, thalon provisioned + handed
off) · dashboard fleet card now names each box's role. Next session is
founder-directed: **security review pass** (see Next-0)._

## State

- **main @ HEAD, all pushed, guard green** (git log is the authority).
- **`!map <project>` LIVE** (relay self-serve topic binding): allowlist-only
  (runtime-derived: `~/work/*` + walter/vault → `~/vault`; hostile args never
  touch a path), idempotent map write with read-back before the in-topic
  confirm, ledgered, effective same cycle. Founder round-trip-tested in topic
  2 (msg 234, ledger `cmd` row). Unit ratchet:
  `provisioning/workstation/relay/test-relay-map.sh` (25 assertions, sources
  the relay via its new test seam). Side-hardening: founder check now precedes
  ALL relay replies; the unmapped notice teaches `!map`. Full phone-only flow:
  create topic → `!map <project>` → `gogogo`.
  **Stale-claim fix:** last wrap said the map needed a relay restart — wrong;
  the daemon loop already re-sources it every poll (box won, file fixed).
- **POSTGRES TENANT BUCKET COMPLETE (Next-3 of last wrap), zero new spend:**
  - `tenant-pg` on syd2: postgres:17.10 pinned, Dokploy id
    `X_o87Ks269ysGvOj1MUSw`, in-network host **`tenant-pg-o7ijjh`** (immutable
    suffixed appName), **no external port ever** (converge check + posture
    assertion + firewall). Superuser cred: `inventory/secrets/pg-syd2.env`.
  - Backup chain landed BEFORE tenant data (invariant held):
    `pre-backup.d/15-tenant-pg-dump` (pg_dumpall, self-arming rot guard) +
    **FUNCTIONAL restore drill** — dump → live postgres on the runner →
    `drill_canary.drill_marker` row read back (run 29320340431, snapshot
    `9d8d6f4a`, RTO 4s). Posture 64→**68/68** (backups-apply run 29320230438,
    dispatched with `install_ping_urls=false` to protect syd2's receivers).
  - **thalon provisioned**: role+DB, isolation verified both ways from the
    tenant's own viewpoint; handoff left in their repo
    (`agent_handoff/FROM-SWORDFISH-2026-07-14.md`, uncommitted per their
    convention, + gitignored `.env.tenant-pg`). They wire DATABASE_URL via
    their scoped Dokploy key; host resolves only on syd2's docker network.
  - **Project 2 = one command when they land:** `provisioning/dokploy/
    tenant-db.sh <slug>` (slug stays a runtime arg). Driver: cred →
    `inventory/secrets/pg-tenant-<slug>.env`, TENANT_DB_PASSWORD repo secret
    as transport, `tenant-db-apply.yml` converges + verifies isolation.
  - **Incident on record (commit b81cdb6):** first converge re-run DUPLICATED
    the service — Dokploy `project.all` lists DB services as bare ids (no
    name); fixed via postgres.one-per-id detection, duplicate removed, quirks
    ledgered in `runbooks/dogfood.md`. The prior commit's "no-op proven"
    claim was false until the correction.
- **Dashboard fleet card** now shows each box's ROLE (production / cockpit /
  workspace / soak) above the data source (render-dashboard.py BOX_ROLES).
- **security-reviewer agent upgraded** (lives OUTSIDE this repo:
  `~/.claude/agents/security-reviewer.md`, syd4, restic-backed): mined
  raroque/vibe-security-skill (MIT) — 4 new categories (client-bundle env
  leaks · managed-backend authz/RLS · payment integrity · LLM integration)
  + a billing-drain carve-out to the DoS exclusion. Relevant to Next-0.
- Morning briefing fired clean this morning (founder confirmed; it probes
  hello./status. on syd2 = ongoing cutover witness).
- Fleet: syd2 (prod) · syd3 (cockpit) · syd4 (workspace) · syd1 (SOAK,
  off-board, rollback = 4 Porkbun upserts; evidence in `inventory/boxes.md`).
- Gmail MCP token still EXPIRED (in NEEDS-STEVEN).

## Next

0. **SECURITY REVIEW PASS — founder-directed at this wrap:** "run some
   security checks over our VPS to make sure it's secure against API attacks,
   DDOS, and prompt injections." Scope it as three lenses over the fleet:
   - **API attack surface:** Dokploy control plane (deploy. — authz, rate
     limits, the scoped-key blast radii from tenant-credential.sh), Kuma/
     Beszel admin APIs, tenant-pg (no public port — re-verify), hermes
     gateway surface on syd3. Use the upgraded security-reviewer agent on
     the exposed configs + the API scripts.
   - **DDoS posture:** what the box can and cannot absorb (traefik
     swordfish-ratelimit coverage per router, fail2ban, provider firewall),
     honest statement that real volumetric DDoS needs the **Cloudflare
     bucket (Next-4)** — the two should probably merge into one report with
     a recommendation.
   - **Prompt injection:** the relay chain (Telegram → hermes state.db →
     injection into agent sessions — founder-id check is the gate but
     message CONTENT is untrusted), hermes toolsets (per-platform disable
     ratchet from E1), agent memory/handoff files as injection carriers,
     and the [Steven via hermes-relay] prefix exclusivity. Existing ratchets
     to re-verify, new ones to leave executable where possible.
   Deliverable: findings ranked by exploitability + a ratchet per confirmed
   gap, not a checklist dump.
1. **Soak watch until ≈2026-07-16 23:00 AEST:** monitors green + ≥1 natural
   verify-deadman pass vs syd2 + clean briefings. **At soak end:** retire the
   `*2` A-records (Porkbun `deleteByNameType` — no delete script yet), prune
   the deploy2 note in `inventory/boxes.md`, then **present the syd1
   destroy-vs-warm-fallback gate** (founder; at destroy also retire syd1's
   healthchecks check, UptimeRobot monitors, B2 bucket).
2. **⛔ SPEND GATE queued: resize syd2 → std-6vcpu** (AUD 78.40, +39.20/mo;
   nets ≈US$14/mo cheaper by cancelling Project 1's Render after their agent
   re-seeds + verifies checksums). On "resize go": BinaryLane in-place resize
   → hardening-smoke → asset landing zone (restic EXCLUSION for the asset
   tree — it re-seeds from their Supabase bucket; nothing stranded).
   Analysis: `research/capacity-and-data-plan-2026-07-13.md`.
3. **Postgres follow-ups (bucket itself DONE):** Project 2 tenant on their
   landing (`tenant-db.sh <slug>`) · thalon's PGlite→Postgres migration is
   THEIR call (offered in the handoff note) · wal-g/pgBackRest graduation
   when size demands.
4. **Cloudflare bucket (founder has an account) — AFTER the soak gate:**
   DNS is the syd1 rollback lever until ~07-16, so no nameserver move before
   then. Scope: Porkbun→Cloudflare NS (founder gate), origin-IP hiding for
   syd2's public names, WAF/rate-limits at the edge, cert plumbing switch
   (TLS-ALPN breaks behind the proxy → DNS-01 or origin certs), thalon.org
   launch prep. **Sentry/PostHog are app-layer** — broker DSNs/keys to
   project agents at Thalon launch prep; not infra work now.
5. **Post-cutover unblocked queue:** syd3+syd4 Kuma push dead-man legs ·
   traefik 3.7.7 bump · Dokploy notifications · morning-noise consolidation
   (fold pings into the 07:30 slot; grow briefing to real metrics — prompt
   in `provisioning/hermes/README.md`).
6. **Founder actions:** `agent_handoff/NEEDS-STEVEN.md` (dashboard renders
   it; Gmail re-auth added this wrap).
7. Unchanged queue: Renovate PR #4 · healthchecks→Telegram · ntfy retirement
   audit · port-map call · wrap summaries over relay-send.sh when the
   closing-summary protocol lands.

## Protocol notes

- **Founder-typed = ONE short line**; copy-material goes in `COPY-ME.txt`.
- **Inside a `cat script | bash` script, every bare `ssh` MUST use `-n`.**
- **Delivery-green ≠ content-true** — read back what you wrote (Dokploy
  `project.all` bare-id quirk joined assignPermissions on this list today;
  ledger: `runbooks/dogfood.md`).
- **inventory/secrets values may carry stray whitespace/CR** — consume with
  `tr -d '[:space:]'` (bit me again today via a quick `source`).
- Dashboard regen: `sudo -n systemctl start swordfish-dashboard-regen`.
- Relay edits: the service runs THIS repo's working copy on syd4
  (`swordfish-relay.service`) — edit, test via `test-relay-map.sh`, then
  `sudo -n systemctl restart swordfish-relay` (watermark is crash-safe;
  messages during the ~1s restart are picked up after).

## Standing

`scripts/sync-with-box.sh` is the LAPTOP's wrap duty (we are the box) ·
AGENTS.md edits break the CLAUDE.md hardlink — recreate + hash-verify ·
cockpit-class boxes use `cockpit-smoke` · do NOT re-dispatch
backups-apply/restore-drill vs syd1 (frozen) · when dispatching
backups-apply vs syd2 use `install_ping_urls=false` (repo ping-URL secrets
are not per-box; syd2's receivers are live and must not be overwritten) ·
alerts bot is SEND-ONLY · Hermes config edits ONLY via `hermes config set` ·
`hermes cron list` HIDES paused jobs — read `jobs.json` · pre-stage founder
actions · the vault is **walter** (writable, as a guest) · maintain
NEEDS-STEVEN.md at every wrap.

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens
(A/B) in tracked files · backups-before-workloads satisfied syd2/3/4 (and
proven again today: drill BEFORE thalon's DB) · **syd1 destroy is a founder
gate at soak end (≈2026-07-16)** · tenant-pg never publishes a port ·
thalon.org unwired until launch call · Hermes never gets spend keys /
provisioning authority · syd2's inbound 22 answers CI only · founder is the
sole author.

_All work committed and pushed at wrap — safe to clear; this file + agent
memory (syd4, restic-backed nightly) carry the full state._
