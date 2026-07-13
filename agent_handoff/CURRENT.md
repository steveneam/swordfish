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
> Stop only at a founder gate (spend · cutover · destroy · anything named a
> founder decision below). If the box state and this file disagree, the box
> wins — say so, then fix the file.

_Stamped: 2026-07-13 21:35 +10:00 (thalon staging pack COMPLETE + auto-deploy
channel built and generalized by founder directive; E1 swordfish-topic leg
passed live.)_

## State

- **main @ HEAD, all pushed, guard green** (git log is the authority).
- **THALON STAGING PACK COMPLETE** — the whole remainder plus both actions
  from thalon's `STAGING-VERIFY-2026-07-13.md` and all three asks from their
  `AUTODEPLOY-REQUEST-2026-07-13.md` (folder: `~/work/thalon/agent_handoff/`):
  - **Fixed pin `fa54d787…@7621f5e3…` deployed** — the engine routes that
    500'd on the old image (`/blog`, rss, sitemap, llms.txt) are 200 through
    the edge; founder unblocked on /blog.
  - **Double-Basic deadlock resolved (their finding 2, option 1) — real root
    cause found:** Dokploy generates its basicauth middleware with
    `removeHeader: true`, so the app NEVER saw the Authorization header.
    Flipped false + both layers unified on the `preview:…` pair; `/app` is
    200 through staging. The flag survives deploys (tested) but security
    CRUD regenerates it — **`provisioning/thalon/staging-assert.sh`** (14
    checks, all green) asserts the posture and auto-converges that flag.
  - **Restic wiring live and CI-proven:** syd2 profile rewritten STANDALONE
    (positional-inherit landmine) with `thalon-data` in the set, `pg/**`
    out; `pre-backup.d/30-thalon-pglite-dump` calls the dump endpoint
    in-container (node fetch on loopback, token never leaves the container,
    hard 200-gate + fresh-artifact check + self-arming rot guard).
    backups-apply run 29243982813: dump `200 {bytes:4381823, ms:1165}`,
    snapshot `d1d22b8c`, repo history intact. The run shows "failure" ONLY
    from the known pre-cutover 60/63 posture ceiling (hello/status/metrics
    route checks — pass at cutover). assert-hardening now checks hook 30.
  - **Kuma watch live** (syd2 kuma = status2, monitor id 5): probes
    `/api/health` THROUGH the edge auth with the preview pair — stronger
    than the queued 401-liveness idea (a 401 only proves Traefik). Beating
    200-OK, cert-expiry on, ntfy → founder phone.
  - **Scoped CI credential cut + proven:** `provisioning/dokploy/
    tenant-credential.sh` (parameterized, idempotent, scope-verified). The
    CI recipe was exercised live with the key: `application.update`
    (image-only — never saveDockerProvider, it can clobber pull creds) →
    `application.deploy` → health 200. Key delivered via thalon's
    gitignored `.context/staging-secrets-from-swordfish.md`; full answers in
    `~/work/thalon/agent_handoff/FROM-SWORDFISH-AUTODEPLOY-2026-07-13.md`.
    Traps burned into script + `runbooks/dogfood.md` quirk ledger:
    assignPermissions wants the USER id and 200s silently on a wrong one;
    better-auth api keys default to TEN-requests-per-DAY (reads as bare
    "Unauthorized" = looks like a permission bug); update gates on
    service:create → canCreateServices=true for tenants.
- **FOUNDER DIRECTIVE (this session, mid-turn): the auto-deploy channel is
  for ALL projects, not just thalon** — every tenant's handoff pack = Dokploy
  project + scoped credential (tenant-credential.sh) + the same documented
  update→deploy→probe recipe. Project CIs deploy their own apps; swordfish
  never touches their app side (boundary unchanged).
- **E1 relay: the Swordfish-topic leg PASSED live** — founder's relay message
  arrived prefixed, reply landed back in his topic. Only the thalon-topic
  leg remains (queued in NEEDS-STEVEN).
- **`~/COPY-ME.txt` refreshed**: single preview pair now opens site AND
  workspace; the old `steven:…` workspace password is retired.
- Fleet at wrap: 4 boxes up; syd2 nightly at 15:00 UTC now carries the
  thalon volume + dump chain.

## Next

1. **E1 follow-up (queued at finding e):** silence hermes's own group
   dispatch via `allowed_chats` — READ the adapter semantics in the
   hermes-agent repo on syd3 first, config only via `hermes config set`.
2. **Morning-noise consolidation:** adopt hermes's daily-briefing cron
   pattern — one 07:30 digest instead of scattered pings (design notes in
   the hermes-cloud research, previous wrap).
3. **Founder actions — all in NEEDS-STEVEN.md** (dashboard renders it):
   subscriptions.yml correction · rehearsal-pass confirmation (un-parks the
   ops queue) · drive .txt deletion · Mac census re-scan · hermes terminal
   call · thalon-topic relay test.
4. **On rehearsal-pass → the parked ops queue:** cutover step-card →
   verify-deadman → soak/syd1. At cutover ALSO: re-point `*2` hostnames,
   retire syd1 from the dashboard (`collectors/lib.sh` host lists + its
   api_box call), thalon's CI api_base flips deploy2→deploy (they keep it a
   repo variable — already told), `staging-assert.sh` + `~/.claude.json`
   dokploy MCP DOKPLOY_URL defaults follow.
5. **When Project 1 / Project 2 land on boxes:** same tenant pack via
   tenant-credential.sh — slugs are runtime args, so guarded names never
   enter tracked files; keep Dokploy project names neutral anyway.
6. Unchanged queue: Renovate PR #4 · traefik 3.7.7 post-cutover ·
   healthchecks→Telegram · ntfy retirement audit · Dokploy notifications
   post-cutover · port-map call.

## Protocol notes

- **Founder-typed = ONE short line**; copy-material goes in `COPY-ME.txt`,
  never chat text (TUI redraws drop selection).
- **Inside a `cat script | bash` script, every bare `ssh` MUST use `-n`.**
- **Remote command strings: keep systemd/journalctl args SPACE-FREE.**
- **The Mac's rsync is Apple's OLD one** — `-P`, not `--info=progress2`.
- **Delivery-green ≠ content-true** — and its newest cousin: an API that
  200s silently on a wrong id (Dokploy assignPermissions). Read back what
  you wrote.
- Dokploy quirk ledger (all of today's traps): `runbooks/dogfood.md`.

## Standing

`scripts/sync-with-box.sh` is the LAPTOP's wrap duty (we are the box) ·
AGENTS.md edits break the CLAUDE.md hardlink — recreate + hash-verify ·
cockpit-class boxes use `cockpit-smoke` · do NOT re-dispatch
backups-apply/restore-drill vs syd1 (frozen; it lacks hook 30 by design) ·
alerts bot is SEND-ONLY and separate from the Hermes bot · Hermes config
edits ONLY via `hermes config set` · `hermes cron list` HIDES paused jobs —
read `jobs.json` · pre-stage founder actions · the vault is **walter**
(writable, as a guest) · maintain NEEDS-STEVEN.md at every wrap.

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens
(A/B) in tracked files · backups-before-workloads satisfied syd2/3/4 (thalon
chain included) · cutover + instance-destroy are founder gates · thalon.org
unwired until launch call (staging-assert retires/rewrites at launch) ·
rehearsal-pass confirmation precedes the ops queue · Hermes never gets spend
keys / provisioning authority · syd2's inbound 22 answers CI only · founder
is the sole author.

_All work committed and pushed at wrap — safe to clear; this file + agent
memory (syd4, restic-backed nightly) carry the full state._
