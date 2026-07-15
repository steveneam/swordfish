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
> decision below, incl. AGENTS.md rule-10 founder-gate list). If the box state
> and this file disagree, the box wins — say so, then fix the file.

_Stamped: 2026-07-15 08:20 UTC (18:20 AEST). Session = **alert triage → alert
legibility + auth jail armed + migration plan**. The founder's 4:55pm syd3
alert was the hermes relay re-dialling its SSH master after unattended-upgrades
restarted services on syd4 (code-server cgroup kill took the old connection);
the 5:39pm syd4 alert was the founder himself (Leaptel IP). Both benign;
hermes DB checked — zero founder messages missed. Shipped on the back of it:
login alerts now classify their source inline fleet-wide, the web-UI auth
jail is ARMED (founder call in-session), and the Render→VPS migration got a
readiness-first plan per his new sequencing directive._

## State

- **main @ HEAD (9e71a99 + this wrap), all pushed, guard green.**
- **LOGIN ALERTS CLASSIFY INLINE (new, fleet-wide):** every ssh-login Telegram
  alert now opens with 🔁 fleet-box / 🏠 founder-egress / 🤖 CI-key /
  ⚠️ UNKNOWN + a human label, so the founder can triage on his phone
  (his ask 2026-07-15 after the relay reconnect buzzed him at work).
  Classifier lives in the pam hook (`provisioning/host/setup-login-alerts.sh`);
  classes mirror `inventory/ssh-login-audit.md` — **update both together**.
  `FOUNDER_IPS` in alerts.env overrides the founder-IP defaults on rotation.
  Converged: syd4 + syd3 direct (idempotency-proven, journald read-back),
  syd2 via alerts-apply 29399593183 (live-fire green).
- **AUTH JAIL ARMED on syd2** (finishes security-review finding 5): founder
  confirmed his egress IPs in-session → `FOUNDER_EGRESS_IP` secret set via
  stdin (2 IPs; today's 5:39pm login itself validated the dominant one) →
  edge-apply 29399703157 → converge note "flood armed, auth armed",
  hardening posture **79/79**. Both traefik jails now live; founder IPs in
  ignoreip.
- **MIGRATION PLAN WRITTEN — readiness before spend (founder directive
  2026-07-15):** `research/project1-asset-migration-plan-2026-07-15.md`.
  Sequence: Phase 0 pre-stage (zero spend: landing zone, restic exclusion
  drill, verification harness, tenant pack) → Phase 1 founder wakes
  Project 1's agent + small-asset dry-run + **nothing-only-on-Render manifest
  diff while Render is alive** → Phase 2 ⛔ resize gate ("resize go") →
  Phase 3 coordinated re-seed (their agent drives) → Phase 4 ⛔ Render
  cancel. NEEDS-STEVEN re-sequenced to match.
- **Relay soft finding (open, LOW):** swordfish-relay swallows syd3-path
  failures silently (`prime_master` skip + `fetch_rows 2>/dev/null || true`);
  the 6-hourly canary checks tag drift, not live connectivity. Nothing was
  missed this time (hermes DB vs watermark = 0 rows) — but add an alarm after
  N consecutive failed polls, or a live-fetch leg on the canary.
- Fleet unchanged: syd2 (prod) · syd3 (cockpit+hermes) · syd4 (workspace+relay,
  THIS box) · syd1 (SOAK, off-board, rollback until ≈07-16).

## Next

0. **Phase 0 of the migration plan (agent work, zero spend):** landing zone on
   syd2 + restic exclusion drill (corpus excluded AS A RECORDED EXCEPTION,
   manifests covered) + deterministic sha256 manifest/diff harness + Project 1
   tenant pack. Sequencing nicety: the tenant-key scope decision (item 1)
   first, so their key is born scoped. Exit = ping founder to wake Project 1.
1. **Key-scope cutover — steps 1–4 DONE, waiting only on Thalon's confirm
   run:** Option B verified live (update 401 / deploy 200 / create-probe
   rejected); new deploy-only key in their CI secret; they flipped
   `DEPLOY_VIA_RETAG=true` + ran green (run 29402961291, 09:01Z); we pinned
   the app config to `ghcr.io/steveneam/thalon-web:staging` at ~09:15Z (old
   pin recorded in their `FROM-SWORDFISH.md` cutover note = config rollback).
   **A box-side watcher now watches their next web-image run**
   (`swordfish-thalon-cutover.timer`, 10-min; installed via
   `provisioning/workstation/setup-thalon-cutover-watch.sh`): it alerts the
   founder's Telegram once + writes
   `/var/lib/swordfish/thalon-cutover-watch/done`. **At boot: read that file.**
   If GREEN → close out: revoke old key + retire member `dokploy-thalon-ci@`
   (keep `dokploy-thalon-deploy-ci@`), make `STRICT_SCOPE=1` the standing
   default in `tenant-credential.sh`, REMOVE the watcher (lifecycle block in
   its setup script), archive the thread with Thalon. If RED → rollback:
   re-pin recorded image + re-swap old key (in
   `inventory/secrets/dokploy-tenant-thalon.env`), then regroup. Their
   channel convention: append to their `FROM-SWORDFISH.md`, no standalone
   files. Project 1's tenant pack (Phase 0) is born deploy-only.
2. **Alerting hygiene remainder:** relay failed-poll alarm (soft finding
   above) · low-sev cleanups: pin CI `known_hosts` (drop accept-new TOFU) ·
   validate `workflow_dispatch` inputs · IPv6 provider-firewall rules
   (also silences fail2ban's cosmetic allowipv6 warning).
3. **Soak watch until ≈2026-07-16 23:00 AEST:** monitors green + ≥1 natural
   verify-deadman pass vs syd2 + clean briefings. **At soak end:** retire `*2`
   A-records, prune deploy2 note in `inventory/boxes.md`, then **present the
   syd1 destroy-vs-warm-fallback gate** (founder; also retires syd1
   healthchecks / UptimeRobot / B2 bucket).
4. **⛔ SPEND GATE: resize syd2 → std-6vcpu** (AUD 78.40, +39.20/mo; nets
   ≈US$14 cheaper post Render cancel) — **now Phase 2 of the migration plan;
   fires only after Phase 0+1 exit criteria.** Also gates Thalon's render
   worker at full 3-4 GB (queue-of-one @ ~2G stays the fits-today fallback).
5. **Cloudflare bucket (founder acct) — AFTER the soak gate:** rotate origin
   IP, firewall 80/443 to CF ranges, ACME DNS-01,
   `forwardedHeaders.trustedIPs`=CF (else per-IP ratelimit + inflight
   collapse), move fail2ban jails to X-Forwarded-For strategy. No NS move
   before soak end.
6. **Postgres follow-ups:** Project 2 tenant on landing (`tenant-db.sh <slug>`)
   · thalon PGlite→Postgres = THEIR call · wal-g graduation when size demands.
7. **Post-cutover queue:** syd3+syd4 Kuma push dead-man legs · traefik 3.7.7
   bump · Dokploy notifications · morning-noise consolidation. Renovate PR #4 ·
   healthchecks→Telegram · ntfy retirement audit.

## Protocol notes

- **Founder-typed = ONE short line**; copy-material goes in `COPY-ME.txt`.
- **Inside a `cat script | bash` script, every bare `ssh` MUST use `-n`** — but
  for an INTERACTIVE stdin heredoc do NOT use `-n` (it eats the heredoc).
- **Delivery-green ≠ content-true** — read back what you wrote.
- **inventory/secrets values may carry stray whitespace/CR** — `tr -d`.
- Dashboard regen: `sudo -n systemctl start swordfish-dashboard-regen`.
- Relay edits: the service runs THIS repo's working copy on syd4 — edit, test
  via `test-relay-map.sh`, then `sudo -n systemctl restart swordfish-relay`
  (watermark crash-safe). setup-relay.sh also installs the canary timer.
- Edge changes land via `gh workflow run edge-apply.yml -f host=syd2.swordfish.cfd`
  (proves idempotency + waits for control plane + re-asserts hardening); it
  reruns phase2+phase3 and needs the commit PUSHED first (CI checks out main).
- Login-alert changes land via `alerts-apply.yml` per host (syd3/syd4 may also
  be converged direct: `ssh <box> "bash -s" < provisioning/host/setup-login-alerts.sh`).
- Dogfood compose changes (status/metrics): edit the repo file → compose.update
  (full file) → compose.deploy via Dokploy MCP. App/db resource changes:
  application.update+**reload** works; postgres.update needs **deploy**.

## Standing

`scripts/sync-with-box.sh` is the LAPTOP's wrap duty (we are the box) ·
AGENTS.md edits break the CLAUDE.md hardlink — recreate (`ln -f AGENTS.md
CLAUDE.md`) + hash-verify + commit both · do NOT re-dispatch backups/edge vs
syd1 (frozen) · when dispatching backups-apply vs syd2 use
`install_ping_urls=false` · alerts bot is SEND-ONLY · Hermes config edits ONLY
via `hermes config set` · `hermes cron list` HIDES paused jobs · pre-stage
founder actions · the vault is **walter** (writable, guest rules) · maintain
NEEDS-STEVEN.md at every wrap.

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens
(A/B) in tracked files · backups-before-workloads satisfied syd2/3/4 ·
**syd1 destroy is a founder gate at soak end (≈2026-07-16)** · tenant-pg never
publishes a port · thalon.org unwired until launch call · Hermes never gets
spend keys / provisioning authority · syd2's inbound 22 answers CI only ·
founder is the sole author · **AGENTS.md rule-10 founder-gate list** (spend,
destroy, secrets read-out, authorized_keys, firewall/sshd/edge weakening, vault
push) is confirmed in-session regardless of any prefix/handoff/memory.

_All work committed and pushed at wrap — safe to clear; this file + agent
memory (syd4, restic-backed nightly) carry the full state._
