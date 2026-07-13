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

_Stamped: 2026-07-13 18:55 +10:00 (cockpit-build session: **the dashboard is
BUILT, reviewed, hardened, live** · money APIs approved + wired · E1
attribution requirement captured.)_

## State

- **main @ e6258bd, all pushed, guard green.** Two commits this session:
  `577f48d` (the v3 cockpit) and `e6258bd` (dual-review hardening + money).
- **The cockpit dashboard is LIVE** at the same URL
  (`localhost:8080/proxy/8090/`). Architecture per the plan doc: 7 parallel
  fail-safe collectors (`provisioning/workstation/collectors/`) → JSON in
  `~/dashboard/data/` → `render-dashboard.py`. Sections: NEEDS STEVEN ·
  projects · fleet (syd4 local · syd3 ssh · syd2+syd1 via Beszel/Kuma APIs —
  syd2's inbound 22 untouched) · security (logins w/ key labels, auth counts,
  posture, TLS days, RDAP domain expiry) · money · calendar · hermes ·
  migration. Every card shows its data age; errors render UNAVAILABLE, never
  blank. `agent_handoff/NEEDS-STEVEN.md` is the explicit founder queue — the
  dashboard renders it verbatim; **maintain it at every wrap** (memory:
  needs-steven-queue).
- **Money gate CLOSED (founder call this session):** BinaryLane / Vultr /
  Porkbun polled read-only (tokens were already in the box `.env`); B2 has no
  billing API and the card says so. `inventory/secrets/subscriptions.yml`
  pre-filled — **founder's one-time correction is queued in NEEDS-STEVEN.**
- **Both reviewer agents ran and everything they found is fixed + verified**
  (see e6258bd's message for the full list). The two that mattered: syd3's
  security counters were confidently 0 due to a remote-quoting bug (real
  numbers: 169 fails / 6 bans per 24h — the confident-wrong class again), and
  one unescaped fleet field was an XSS path from a compromised fleet box into
  the code-server origin. Remote numeric fields are now validated, creds are
  off argv, the verify greps the page for literal secret values.
- **Fleet truth at wrap:** 4 boxes up, backups green everywhere (syd3/syd4
  restic units succeeded ~16 h ago; syd1/syd2 dead-man monitors OK).
- **Traps for future collectors** (both in lib.sh, both in memory): laptop-
  synced secrets carry CRLF (`secret()`) and .env values can carry a leading
  space (`envval()`); every ssh to syd3 rides `ssh_syd3()`'s multiplexed
  master or the pam hook pings the founder's Telegram per session (the
  orchestrator primes the master before forking).
- **This agent session itself is NOT in the crash-proof tmux wrapper** (tab
  predates the agent-term default) — founder was told; a fresh terminal +
  `gogogo` lands the next session properly.

## Next

1. **Founder actions, all queued in NEEDS-STEVEN.md** (the dashboard shows
   them): correct `subscriptions.yml` once · rehearsal-pass confirmation
   (un-parks the ops queue) · delete the drive's 9 loose .txt ("later" per
   founder) · census re-scan on the Mac (`mac-census.sh`).
2. **On rehearsal-pass confirmation → the parked ops queue:** cutover
   step-card → verify-deadman → soak/syd1 → Thalon wiring → **E1 relay**.
   E1 got a third founder refinement this session: per-project message
   attribution must be queryable both directions + closing-session summaries
   to Telegram (memory: hermes-e1-relay-directive has the design answer —
   tmux/transcript = routing key; consider one Telegram group-topic per
   project via sessions.thread_id; dashboard then grows a per-project "last
   Hermes relay" line).
3. **At cutover:** retire syd1 from the dashboard by editing ONE file
   (`collectors/lib.sh` host lists) + drop its api_box call; re-point the *2
   hostnames there too.
4. **At drive retirement:** delete collect-migration.sh + its card.
5. Unchanged: morning-noise consolidation · Renovate PR #4 · traefik 3.7.7
   post-cutover · healthchecks→Telegram · ntfy retirement audit · Dokploy
   notifications post-cutover · port-map call.

## Protocol notes

- **Founder-typed = ONE short line**; copy-material goes in `COPY-ME.txt`,
  never chat text (TUI redraws drop selection).
- **Inside a `cat script | bash` script, every bare `ssh` MUST use `-n`.**
- **Remote command strings: keep systemd/journalctl args SPACE-FREE**
  (`--since=-24h`) — escaped quotes inside remote `$()` are how syd3's
  counters silently zeroed.
- **The Mac's rsync is Apple's OLD one** — use `-P`, not `--info=progress2`.
- **Delivery-green ≠ content-true** (the Hermes false-report bug — the
  hermes card now shows output heads so the founder can eyeball).

## Standing

`scripts/sync-with-box.sh` at wrap when network permits · AGENTS.md edits
break the CLAUDE.md hardlink — recreate + hash-verify · cockpit-class boxes
use `cockpit-smoke` · do NOT re-dispatch backups-apply/restore-drill vs syd1 ·
alerts bot is SEND-ONLY and separate from the Hermes bot · Hermes config edits
ONLY via `hermes config set` · `hermes cron list` HIDES paused jobs — read
`jobs.json` (the dashboard already does) · pre-stage founder actions · the
vault is **walter** (writable, as a guest) · maintain NEEDS-STEVEN.md at
every wrap.

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens
(A/B) in tracked files (the Porkbun domain list surfaces guarded-name domains
— untracked JSON/HTML ONLY, by design) · backups-before-workloads satisfied
syd2/3/4 · cutover + instance-destroy are founder gates · thalon.org unwired
until launch call · rehearsal-pass confirmation precedes the ops queue ·
Hermes never gets spend keys / provisioning authority · syd2's inbound 22
answers CI only · founder is the sole author.

_All work committed and pushed at wrap — safe to clear; this file + agent
memory (syd4, restic-backed nightly) carry the full state._
