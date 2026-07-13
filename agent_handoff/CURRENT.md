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

_Stamped: 2026-07-13 23:05 +10:00 (**THE CUTOVER IS DONE** — executed this
session on the founder's relay-verified `cutover go`; syd2 is THE box; syd1
is in 72 h soak as the untouched rollback target.)_

## State

- **main @ HEAD, all pushed, guard green** (git log is the authority).
- **CUTOVER EXECUTED 2026-07-13 ~23:00 AEST**, per
  `provisioning/cutover-step-card.md` (kept as the record; soak + syd1-fate
  section still pending). Evidence chain:
  - DNS: `deploy./status./metrics./hello.` → 103.249.236.41 (Porkbun upsert
    ×4, TTL 600; authoritative + 1.1.1.1 confirmed within ~1 min).
  - `edge-apply` vs syd2 run **29251569671** green (converge + idempotency
    proof + full posture re-assert; Dokploy router off `deploy2.` → 404s now).
  - `hardening-smoke` vs syd2 run **29251625711** = **64/64** (suite grew +1
    with the thalon staging probe; the old 60/63 pre-cutover ceiling cleared).
  - verify-deadman natural-fire vs syd2 run **29251119226** SUCCESS (same
    day, pre-gate): nightly ran + both dead-man legs receiver-acked.
  - All four real names probed serving from syd2 with fresh LE certs
    (notAfter 2026-10-11).
  - Flips landed + re-proven: `collectors/lib.sh` (SYD1 row gone, real names
    on syd2) · `collect-fleet.sh` (3-box board) · `staging-assert.sh` +
    `tenant-credential.sh` defaults → `deploy.` · thalon repo var
    `DOKPLOY_API_BASE` → `deploy./api` (staging posture green through it) ·
    syd4 `~/.claude.json` dokploy MCP key swapped to the syd2 key (200-tested;
    **the syd1-keyed MCP would have died silently** — found at pre-flight).
  - Dashboard fleet card regenerated: syd4/syd3/syd2, syd2 deadman green.
- **syd1 = SOAK, rollback target only** (off the dashboard, untouched, still
  billing against Vultr credit): rollback = 4 Porkbun upserts back to
  45.63.24.122, ≤10 min. Do NOT deploy to it; its Dokploy IDs are parked in
  `runbooks/dogfood.md`.
- **Dashboard question answered (founder, this session):** the numbers were
  never chat-maintained — machine-visible facts collect automatically every
  15 min (hermes `jobs.json`, provider APIs, fleet); SaaS spend is the one
  schema'd table `inventory/secrets/subscriptions.yml` he can edit directly
  in code-server. What he saw was a 15-min-stale snapshot; verified current
  now (GitHub Pro US$4 on the card; morning-briefing scheduled/enabled,
  fires 21:00 UTC daily).
- Morning-briefing v0 live (hermes cron d8e6bb992d5e); tonight's run doubles
  as a free cutover witness (it probes `hello.` + `status.` — now syd2).
- Gmail MCP token still EXPIRED (founder re-auth queued; unblocks
  receipt-driven `subscriptions.yml` fills).
- Fleet: syd2 (prod, THE box) · syd3 (hermes cockpit) · syd4 (workspace,
  agent home) · syd1 (soak, off-board).

## Next

1. **Soak watch until ≈2026-07-16 23:00 AEST** (72 h from cutover): monitors
   stay green + ≥1 natural verify-deadman pass vs syd2 + morning briefings
   clean. **At soak end:** retire the `*2` A-records (Porkbun delete —
   there's no delete script yet; API `deleteByNameType`), prune the
   `deploy2` temp A-record note in `inventory/boxes.md`, then **present the
   syd1 destroy-vs-warm-fallback gate** (founder decision; at destroy also
   retire syd1's healthchecks check, UptimeRobot monitors, B2 bucket).
2. **Post-cutover unblocked queue, now open:** syd3+syd4 Kuma push dead-man
   legs (were "post-cutover follow-up" in boxes.md) · traefik 3.7.7 bump ·
   Dokploy notifications · morning-noise consolidation (fold kuma/ntfy/
   healthchecks pings into the 07:30 slot; grow briefing to real metrics —
   prompt already written, see `provisioning/hermes/README.md`).
3. **Wrap-protocol closing summaries should ride `relay-send.sh`, not
   `hermes send`** (reply-bait argument — noted in the relay design doc);
   fold in when the closing-summary protocol lands.
4. **Founder actions — NEEDS-STEVEN.md** (dashboard renders it): Dokploy
   bookmark → deploy.swordfish.cfd · subscriptions.yml FILL fields (Claude
   card; GitHub next_charge + card) · Mac census re-scan · thalon COPY-ME
   creds note · Gmail MCP re-auth.
5. **When Project 1 / Project 2 land on boxes:** tenant pack via
   `tenant-credential.sh` (defaults now point at `deploy.`) — slugs are
   runtime args, guarded names never enter tracked files.
6. Unchanged queue: Renovate PR #4 · healthchecks→Telegram · ntfy
   retirement audit · port-map call.

## Protocol notes

- **Founder-typed = ONE short line**; copy-material goes in `COPY-ME.txt`,
  never chat text (TUI redraws drop selection).
- **Inside a `cat script | bash` script, every bare `ssh` MUST use `-n`.**
- **Remote command strings: keep systemd/journalctl args SPACE-FREE.**
- **The Mac's rsync is Apple's OLD one** — `-P`, not `--info=progress2`.
- **Delivery-green ≠ content-true** — read back what you wrote; APIs can
  200 silently on wrong ids (Dokploy assignPermissions).
- **inventory/secrets values may carry stray whitespace/CR** (laptop sync):
  consume with `tr -d '[:space:]'` — a leading space 400s the Telegram API.
- Dashboard regen needs `sudo -n systemctl start swordfish-dashboard-regen`
  (deploy user, non-interactive; bare systemctl start asks for auth).
- Dokploy quirk ledger: `runbooks/dogfood.md`.

## Standing

`scripts/sync-with-box.sh` is the LAPTOP's wrap duty (we are the box) ·
AGENTS.md edits break the CLAUDE.md hardlink — recreate + hash-verify ·
cockpit-class boxes use `cockpit-smoke` · do NOT re-dispatch
backups-apply/restore-drill vs syd1 (frozen; it lacks hook 30 by design) ·
alerts bot is SEND-ONLY and separate from the Hermes bot (and the relay's
outbound voice) · Hermes config edits ONLY via `hermes config set` ·
`hermes cron list` HIDES paused jobs — read `jobs.json` · pre-stage founder
actions · the vault is **walter** (writable, as a guest) · maintain
NEEDS-STEVEN.md at every wrap.

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens
(A/B) in tracked files · backups-before-workloads satisfied syd2/3/4 ·
**syd1 destroy is a founder gate at soak end (≈2026-07-16)** · thalon.org
unwired until launch call (staging-assert retires/rewrites at launch) ·
Hermes never gets spend keys / provisioning authority · syd2's inbound 22
answers CI only · founder is the sole author.

_All work committed and pushed at wrap — safe to clear; this file + agent
memory (syd4, restic-backed nightly) carry the full state._
